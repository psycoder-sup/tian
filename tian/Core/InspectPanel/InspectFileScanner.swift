import Foundation

/// Rolled-up ignored entries returned by `git ls-files --ignored --directory`,
/// split by kind so callers can render the directory entries as expandable
/// `.directory` nodes rather than mistakenly flattening them into files.
struct InspectIgnoredEntries: Sendable, Equatable {
    var directories: Set<String>
    var files: Set<String>

    static let empty = InspectIgnoredEntries(directories: [], files: [])

    var all: Set<String> { directories.union(files) }
}

struct InspectChildEntry: Sendable, Hashable {
    let name: String
    let isDirectory: Bool
}

enum InspectFileScanner {

    /// Returns POSIX-relative paths (no leading `./`) for every tracked or
    /// untracked non-ignored file under `workingTree`.
    /// Throws if `git` returns a non-zero exit code.
    ///
    /// Implementation note: shells out to
    /// `git ls-files --cached --others --exclude-standard -z`.
    /// Ignored entries are omitted here; callers that want to show them as
    /// single dimmed nodes merge in the rolled-up directory entries returned
    /// by `scanGitIgnored`. `git ls-files` itself never recurses into `.git/`.
    static func scanGitTracked(workingTree: String) async throws -> [String] {
        let result = try await runGit(
            ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            workingDirectory: workingTree
        )
        guard result.exitCode == 0 else {
            throw ScannerError.gitFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        guard let raw = String(data: result.stdoutData, encoding: .utf8) else {
            throw ScannerError.decodeFailed
        }
        return raw.split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Returns the relative paths git considers ignored under `workingTree`,
    /// split into rolled-up directories and individually-listed files. A
    /// `.gitignore` line of `node_modules/` produces the directory entry
    /// `node_modules` (its 50k descendants are NOT enumerated; expand-on-demand
    /// uses `scanImmediateChildren` instead). A pattern like `*.log` produces
    /// individual file entries. `--directory` keeps this query cheap on big
    /// repos. Callers walk parent prefixes when checking inheritance.
    static func scanGitIgnored(workingTree: String) async throws -> InspectIgnoredEntries {
        let result = try await runGit(
            ["ls-files", "--others", "--ignored", "--exclude-standard",
             "--directory", "-z"],
            workingDirectory: workingTree
        )
        guard result.exitCode == 0 else {
            throw ScannerError.gitFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        guard let raw = String(data: result.stdoutData, encoding: .utf8) else {
            throw ScannerError.decodeFailed
        }
        var directories: Set<String> = []
        var files: Set<String> = []
        for entry in raw.split(separator: "\0", omittingEmptySubsequences: true) {
            let s = String(entry)
            // git's `--directory` flag emits a trailing `/` for rolled-up
            // directories, which is the only signal we have to distinguish
            // them from individual ignored files (e.g. `*.log` matches).
            if s.hasSuffix("/") {
                directories.insert(String(s.dropLast()))
            } else {
                files.insert(s)
            }
        }
        return InspectIgnoredEntries(directories: directories, files: files)
    }

    /// Returns immediate (one-level, non-recursive) children of `absolutePath`,
    /// each tagged as file or directory. Used to lazy-load contents of
    /// rolled-up ignored directories when the user expands them — the rolled-
    /// up form means we never enumerated descendants during the main scan.
    /// Symlinks count as files; junk like `.DS_Store` is filtered out.
    static func scanImmediateChildren(absolutePath: String) async throws -> [InspectChildEntry] {
        try await Task.detached(priority: .userInitiated) {
            try enumerateImmediateChildren(absolutePath: absolutePath)
        }.value
    }

    private static func enumerateImmediateChildren(absolutePath: String) throws -> [InspectChildEntry] {
        let url = URL(filePath: absolutePath)
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey],
            options: []
        )
        return contents.compactMap { child in
            guard let meta = childMetadata(at: child) else { return nil }
            return InspectChildEntry(name: meta.name, isDirectory: meta.isDirectory)
        }
    }

    /// Common file-classification logic for `FileManager`-based scans:
    /// strips `.DS_Store` noise and resolves directory/symlink kind without
    /// following symlinks (FR-17). Returns nil for entries the caller should
    /// skip outright.
    private static func childMetadata(
        at url: URL
    ) -> (name: String, isSymlink: Bool, isDirectory: Bool, isRegular: Bool)? {
        let name = url.lastPathComponent
        if name == ".DS_Store" { return nil }
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey,
        ])
        let isSymlink = values?.isSymbolicLink ?? false
        return (
            name: name,
            isSymlink: isSymlink,
            isDirectory: !isSymlink && (values?.isDirectory ?? false),
            isRegular: values?.isRegularFile ?? false
        )
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
            guard let meta = childMetadata(at: url) else { continue }
            // Skip dirs (traversed by the enumerator) and unknown specials.
            guard meta.isSymlink || meta.isRegular else { continue }
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
