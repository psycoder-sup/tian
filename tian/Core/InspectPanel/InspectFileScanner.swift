import Foundation

enum InspectFileScanner {

    /// Returns POSIX-relative paths (no leading `./`) for every tracked or
    /// untracked-not-ignored file under `workingTree`. Throws if `git`
    /// returns a non-zero exit code.
    ///
    /// Implementation note: shells out to
    /// `git ls-files --cached --others --exclude-standard -z` and decodes
    /// the NUL-separated output. Using git itself avoids re-implementing
    /// `.gitignore` parsing and keeps semantics identical to the user's
    /// `git status` output (FR-15, FR-15a, FR-16).
    static func scanGitTracked(workingTree: String) async throws -> [String] {
        let result = try await runGit(
            ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            workingDirectory: workingTree
        )
        guard result.exitCode == 0 else {
            throw ScannerError.gitFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        // -z separates entries by NUL. Decode and drop the trailing empty
        // element that follows the final NUL byte.
        guard let raw = String(data: result.stdoutData, encoding: .utf8) else {
            throw ScannerError.decodeFailed
        }
        return raw.split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Returns POSIX-relative paths for every non-hidden file under `root`
    /// using `FileManager`. Used when the directory is not in a git repo.
    /// Skips hidden entries (leading dot), bundle internals (`*.app/Contents`),
    /// and standard junk like `.DS_Store`. Symlinks are returned as files
    /// without following the target (FR-17).
    static func scanFileSystem(root: URL) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            try enumerateFileSystem(root: root)
        }.value
    }

    private static func enumerateFileSystem(root: URL) throws -> [String] {
        let fm = FileManager.default
        let standardizedRoot = root.standardizedFileURL
        let rootPath = standardizedRoot.path

        // skipsHiddenFiles drops dotfiles in the FileManager fallback
        // (the plan's docstring specifies "every non-hidden file" here);
        // skipsPackageDescendants stops us descending into `*.app/Contents`
        // and similar bundle internals.
        guard let enumerator = fm.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }  // skip per-entry errors, keep walking
        ) else {
            return []
        }

        var paths: [String] = []
        for case let url as URL in enumerator {
            // Determine kind without following symlinks (FR-17).
            let resourceValues = try? url.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey,
            ])
            let isSymlink = resourceValues?.isSymbolicLink ?? false
            let isRegular = resourceValues?.isRegularFile ?? false

            // Symlinks count as files; regular files are obvious. Skip dirs
            // (they're traversed by the enumerator) and unknown specials.
            guard isSymlink || isRegular else { continue }

            // Filter common noise.
            let name = url.lastPathComponent
            if name == ".DS_Store" { continue }

            let absolute = url.standardizedFileURL.path
            guard let relative = relativize(absolute, against: rootPath) else { continue }
            paths.append(relative)
        }
        return paths
    }

    /// Strips `rootPath` prefix and a trailing `/`. Returns nil if the path
    /// isn't under root (shouldn't happen via `enumerator(at:)` but defensive).
    private static func relativize(_ absolute: String, against rootPath: String) -> String? {
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard absolute.hasPrefix(prefix) else {
            return absolute == rootPath ? "" : nil
        }
        return String(absolute.dropFirst(prefix.count))
    }

    enum ScannerError: Error, CustomStringConvertible {
        case gitFailed(exitCode: Int32, stderr: String)
        case decodeFailed

        var description: String {
            switch self {
            case .gitFailed(let code, let stderr):
                return "git ls-files exited \(code): \(stderr)"
            case .decodeFailed:
                return "git ls-files output was not valid UTF-8"
            }
        }
    }

    /// Runs `git` with the given arguments, returning raw stdout bytes
    /// alongside exit/stderr metadata. Mirrors `GitStatusService.runGit`'s
    /// pattern but exposes `Data` (since `-z` output isn't newline-trimmable).
    private static func runGit(
        _ arguments: [String],
        workingDirectory: String
    ) async throws -> (exitCode: Int32, stdoutData: Data, stderr: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks"] + arguments
        process.currentDirectoryURL = URL(filePath: workingDirectory)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let stdoutPipe = Pipe()
                    let stderrPipe = Pipe()
                    process.standardOutput = stdoutPipe
                    process.standardError = stderrPipe

                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }

                    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    let stderr = String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .newlines) ?? ""
                    continuation.resume(returning: (process.terminationStatus, stdoutData, stderr))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
