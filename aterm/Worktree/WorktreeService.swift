import Foundation
import Darwin

/// Git and filesystem operations for worktree management.
/// All methods are static and run off the main actor.
enum WorktreeService {

    // MARK: - Path Resolution

    /// Resolves the worktree container directory for a given repo.
    ///
    /// - If `worktreeDir` is absolute (starts with `~/` or `/`), returns
    ///   `<expanded-worktreeDir>/<repo-name>`.
    /// - If relative, returns `<repoRoot>/<worktreeDir>`.
    static func resolveWorktreeBase(repoRoot: String, worktreeDir: String) -> String {
        let expanded = NSString(string: worktreeDir).expandingTildeInPath
        if expanded.hasPrefix("/") {
            let repoName = URL(filePath: repoRoot).lastPathComponent
            return (expanded as NSString).appendingPathComponent(repoName)
        } else {
            return (repoRoot as NSString).appendingPathComponent(worktreeDir)
        }
    }

    /// Returns `true` when the resolved worktree base is inside the repo root.
    static func isWorktreeInsideRepo(repoRoot: String, worktreeDir: String) -> Bool {
        let base = resolveWorktreeBase(repoRoot: repoRoot, worktreeDir: worktreeDir)
        let repoURL = URL(filePath: repoRoot).standardizedFileURL.path
        return base.hasPrefix(repoURL)
    }

    // MARK: - Git Operations

    /// Resolves the git repository root from a directory path.
    /// - Parameter directory: Absolute path to a directory inside a git repo.
    /// - Returns: Absolute path to the repo root.
    /// - Throws: `WorktreeError.notAGitRepo` if the directory is not inside a git repository.
    static func resolveRepoRoot(from directory: String) async throws -> String {
        let result = try await runGit(["rev-parse", "--show-toplevel"],
                                      workingDirectory: directory)
        guard result.exitCode == 0, !result.stdout.isEmpty else {
            throw WorktreeError.notAGitRepo(directory: directory)
        }
        return result.stdout
    }

    /// Resolves the main (first) worktree path for a repository.
    /// - Parameter repoRoot: Absolute path to the repo root.
    /// - Returns: Absolute path to the main worktree.
    static func resolveMainWorktreePath(repoRoot: String) async throws -> String {
        let result = try await runGit(["worktree", "list", "--porcelain"],
                                      workingDirectory: repoRoot)
        guard result.exitCode == 0 else {
            throw WorktreeError.gitError(command: "git worktree list --porcelain",
                                         stderr: result.stderr)
        }
        for line in result.stdout.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                return String(line.dropFirst("worktree ".count))
            }
        }
        throw WorktreeError.gitError(command: "git worktree list --porcelain",
                                     stderr: "Failed to parse worktree path from output")
    }

    /// Creates a new git worktree.
    /// - Parameters:
    ///   - repoRoot: Absolute path to the repo root.
    ///   - worktreeDir: Worktree base directory (absolute or relative to repo root).
    ///   - branchName: Branch name (may contain `/` for nested branches).
    ///   - existingBranch: If true, checks out an existing branch instead of creating a new one.
    /// - Returns: Absolute path to the created worktree directory.
    static func createWorktree(
        repoRoot: String,
        worktreeDir: String,
        branchName: String,
        existingBranch: Bool
    ) async throws -> String {
        let base = resolveWorktreeBase(repoRoot: repoRoot, worktreeDir: worktreeDir)
        let worktreePath = (base as NSString).appendingPathComponent(branchName)

        var args: [String]
        if existingBranch {
            args = ["worktree", "add", worktreePath, branchName]
        } else {
            args = ["worktree", "add", worktreePath, "-b", branchName]
        }

        let result = try await runGit(args, workingDirectory: repoRoot)
        guard result.exitCode == 0 else {
            if result.stderr.contains("already exists") {
                if result.stderr.contains("a branch named") {
                    throw WorktreeError.branchAlreadyExists(branchName: branchName)
                }
                throw WorktreeError.worktreePathExists(path: worktreePath)
            }
            throw WorktreeError.gitError(command: "git worktree add", stderr: result.stderr)
        }
        return worktreePath
    }

    /// Removes a git worktree.
    /// - Parameters:
    ///   - repoRoot: Absolute path to the repo root.
    ///   - worktreePath: Absolute path to the worktree to remove.
    ///   - force: If true, forces removal even with uncommitted changes.
    static func removeWorktree(
        repoRoot: String,
        worktreePath: String,
        force: Bool
    ) async throws {
        var args = ["worktree", "remove", worktreePath]
        if force { args.append("--force") }

        let result = try await runGit(args, workingDirectory: repoRoot)
        guard result.exitCode == 0 else {
            if result.stderr.contains("modified or untracked files") ||
                result.stderr.contains("changes not committed") {
                throw WorktreeError.uncommittedChanges(path: worktreePath)
            }
            throw WorktreeError.gitError(command: "git worktree remove", stderr: result.stderr)
        }
    }

    /// Checks whether a local branch exists.
    /// - Returns: `true` if `refs/heads/<branchName>` resolves successfully.
    static func branchExists(repoRoot: String, branchName: String) async throws -> Bool {
        let result = try await runGit(
            ["rev-parse", "--verify", "refs/heads/\(branchName)"],
            workingDirectory: repoRoot
        )
        return result.exitCode == 0
    }

    // MARK: - Filesystem Operations

    /// Walks parent directories upward from a removed worktree path,
    /// removing each empty directory until reaching the worktree container dir.
    /// - Parameters:
    ///   - worktreePath: Absolute path to the (already removed) worktree.
    ///   - worktreeDir: Worktree base directory (absolute or relative to repo root).
    ///   - repoRoot: Absolute path to the repo root.
    static func pruneEmptyParents(
        worktreePath: String,
        worktreeDir: String,
        repoRoot: String
    ) throws {
        let fm = FileManager.default
        let stopAt = URL(filePath: resolveWorktreeBase(repoRoot: repoRoot, worktreeDir: worktreeDir))
            .standardizedFileURL
            .path
        var current = URL(filePath: worktreePath).standardizedFileURL

        while current.path != stopAt && current.path.hasPrefix(stopAt) {
            let contents = try? fm.contentsOfDirectory(at: current, includingPropertiesForKeys: nil)
            guard let contents, contents.isEmpty else { break }
            try fm.removeItem(at: current)
            current = current.deletingLastPathComponent().standardizedFileURL
        }
    }

    /// Copies files from the main worktree to a new worktree based on copy rules.
    /// Uses POSIX `glob()` for source pattern expansion.
    /// Logs warnings on failure but does not throw.
    static func copyFiles(
        copyRules: [CopyRule],
        mainWorktreePath: String,
        newWorktreePath: String
    ) {
        let fm = FileManager.default
        let destBase = URL(filePath: newWorktreePath)

        for rule in copyRules {
            let pattern = (mainWorktreePath as NSString).appendingPathComponent(rule.source)

            var gt = glob_t()
            defer { globfree(&gt) }
            let flags = GLOB_TILDE | GLOB_BRACE
            let result = glob(pattern, flags, nil, &gt)

            guard result == 0 else {
                if result == GLOB_NOMATCH {
                    Log.worktree.warning("No files matched pattern '\(rule.source)'")
                }
                continue
            }

            for i in 0..<Int(gt.gl_pathc) {
                guard let cPath = gt.gl_pathv[i],
                      let matchPath = String(validatingCString: cPath) else {
                    continue
                }

                let sourceURL = URL(filePath: matchPath)
                let relativePath = String(matchPath.dropFirst(mainWorktreePath.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

                let destURL: URL
                if rule.dest == "." || rule.dest.hasSuffix("/") {
                    destURL = destBase
                        .appendingPathComponent(rule.dest)
                        .appendingPathComponent(sourceURL.lastPathComponent)
                } else {
                    destURL = destBase
                        .appendingPathComponent(rule.dest)
                }

                do {
                    let destDir = destURL.deletingLastPathComponent()
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                    try fm.copyItem(at: sourceURL, to: destURL)
                } catch {
                    Log.worktree.warning(
                        "Failed to copy '\(relativePath)': \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    /// Ensures the worktree directory is listed in `.gitignore`.
    /// Appends the entry if missing; creates `.gitignore` if it doesn't exist.
    /// No-op when the worktree base is outside the repo (absolute `worktreeDir`).
    static func ensureGitignore(repoRoot: String, worktreeDir: String) throws {
        guard isWorktreeInsideRepo(repoRoot: repoRoot, worktreeDir: worktreeDir) else { return }
        let gitignorePath = (repoRoot as NSString).appendingPathComponent(".gitignore")
        let entry = worktreeDir

        if FileManager.default.fileExists(atPath: gitignorePath) {
            let content = try String(contentsOfFile: gitignorePath, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            let alreadyPresent = lines.contains {
                $0.trimmingCharacters(in: .whitespaces) == entry
            }
            if !alreadyPresent {
                let block = "\n# aterm worktree directory\n\(entry)\n"
                let handle = try FileHandle(forWritingTo: URL(filePath: gitignorePath))
                handle.seekToEndOfFile()
                handle.write(Data(block.utf8))
                handle.closeFile()
            }
        } else {
            let content = "# aterm worktree directory\n\(entry)\n"
            try content.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        }
    }

    /// Checks whether the worktree directory already exists on disk.
    static func worktreePathExists(
        repoRoot: String,
        worktreeDir: String,
        branchName: String
    ) -> Bool {
        let base = resolveWorktreeBase(repoRoot: repoRoot, worktreeDir: worktreeDir)
        let path = (base as NSString).appendingPathComponent(branchName)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            && isDir.boolValue
    }

    /// Returns the URL for `.aterm/config.toml` if it exists in the repo root.
    static func resolveConfigFile(repoRoot: URL) -> URL? {
        let configURL = repoRoot
            .appendingPathComponent(".aterm")
            .appendingPathComponent("config.toml")
        return FileManager.default.fileExists(atPath: configURL.path) ? configURL : nil
    }

    // MARK: - Private

    private static func runGit(
        _ arguments: [String],
        workingDirectory: String
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/git")
                process.arguments = arguments
                process.currentDirectoryURL = URL(filePath: workingDirectory)

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

                let stdout = String(data: stdoutData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: (process.terminationStatus, stdout, stderr))
            }
        }
    }
}
