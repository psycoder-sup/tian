import Foundation
import OSLog

/// Stateless service wrapping git CLI subprocess calls.
/// All methods are async and run subprocesses on background threads.
enum GitStatusService {

    /// Detects the git repository for a given directory.
    /// Returns the git dir and common dir paths, or nil if not in a git repo.
    static func detectRepo(
        directory: String
    ) async -> (gitDir: String, commonDir: String)? {
        do {
            // Single subprocess: get both --git-dir and --git-common-dir at once
            let result = try await runGit(
                ["rev-parse", "--git-dir", "--git-common-dir"],
                workingDirectory: directory
            )
            guard result.exitCode == 0, !result.stdout.isEmpty else {
                Log.git.info("Not a git repo: \(directory)")
                return nil
            }

            let lines = result.stdout.components(separatedBy: "\n")
            guard lines.count >= 2, !lines[0].isEmpty, !lines[1].isEmpty else {
                Log.git.info("Unexpected rev-parse output for: \(directory)")
                return nil
            }

            let gitDir = lines[0]
            let rawCommonDir = lines[1]

            // Canonicalize commonDir to an absolute path
            let absoluteCommonDir: String
            if rawCommonDir.hasPrefix("/") {
                absoluteCommonDir = URL(filePath: rawCommonDir).standardizedFileURL.path
            } else {
                absoluteCommonDir = URL(filePath: rawCommonDir, relativeTo: URL(filePath: directory))
                    .standardizedFileURL.path
            }

            Log.git.debug("Detected repo at \(directory): gitDir=\(gitDir), commonDir=\(absoluteCommonDir)")
            return (gitDir: gitDir, commonDir: absoluteCommonDir)
        } catch {
            Log.git.error("detectRepo failed for \(directory): \(error)")
            return nil
        }
    }

    /// Returns the current branch name and whether HEAD is detached.
    static func currentBranch(
        directory: String
    ) async -> (name: String, isDetached: Bool)? {
        do {
            let symbolicResult = try await runGit(
                ["symbolic-ref", "--short", "HEAD"],
                workingDirectory: directory
            )
            if symbolicResult.exitCode == 0, !symbolicResult.stdout.isEmpty {
                return (name: symbolicResult.stdout, isDetached: false)
            }

            // Detached HEAD — fall back to abbreviated SHA
            let revParseResult = try await runGit(
                ["rev-parse", "--short", "HEAD"],
                workingDirectory: directory
            )
            if revParseResult.exitCode == 0, !revParseResult.stdout.isEmpty {
                return (name: revParseResult.stdout, isDetached: true)
            }

            Log.git.info("Could not determine branch for: \(directory)")
            return nil
        } catch {
            Log.git.error("currentBranch failed for \(directory): \(error)")
            return nil
        }
    }

    /// Returns a diff summary and list of changed files for the given directory.
    /// Caps the files array at 100 entries while summary totals reflect the full count.
    static func diffStatus(
        directory: String
    ) async -> (summary: GitDiffSummary, files: [GitChangedFile]) {
        do {
            let result = try await runGit(
                ["status", "--porcelain=v1", "--ignore-submodules"],
                workingDirectory: directory
            )
            guard result.exitCode == 0 else {
                Log.git.error("git status failed for \(directory): \(result.stderr)")
                return (.empty, [])
            }
            guard !result.stdout.isEmpty else {
                Log.git.debug("Clean repo: \(directory)")
                return (.empty, [])
            }

            let lines = result.stdout.components(separatedBy: "\n")
                .filter { !$0.isEmpty }

            var summary = GitDiffSummary()
            var files: [GitChangedFile] = []
            let maxFiles = 100

            let unmergedPairs: Set<String> = ["DD", "AU", "UD", "UA", "DU", "AA", "UU"]

            for line in lines {
                guard line.count >= 4 else { continue }

                let xy = String(line.prefix(2))
                let x = xy.first!
                let y = xy.last!

                // Skip ignored files
                if xy == "!!" { continue }

                // Determine file status from XY code
                let status: GitFileStatus
                if unmergedPairs.contains(xy) {
                    status = .unmerged
                } else if x == "R" {
                    status = .renamed
                } else if xy == "??" || x == "A" {
                    status = .added
                } else if x == "D" || y == "D" {
                    status = .deleted
                } else if x == "M" || y == "M" {
                    status = .modified
                } else {
                    continue
                }

                // Extract path — handle rename format "ORIG -> DEST"
                let rawPath = String(line.dropFirst(3))
                let path: String
                if status == .renamed, let arrowRange = rawPath.range(of: " -> ") {
                    path = String(rawPath[arrowRange.upperBound...])
                } else {
                    path = rawPath
                }

                // Update summary counts (always)
                switch status {
                case .modified: summary.modified += 1
                case .added:    summary.added += 1
                case .deleted:  summary.deleted += 1
                case .renamed:  summary.renamed += 1
                case .unmerged: summary.unmerged += 1
                }

                // Cap files array at maxFiles
                if files.count < maxFiles {
                    files.append(GitChangedFile(status: status, path: path))
                }
            }

            Log.git.debug("diffStatus \(directory): \(summary.totalCount) changes (\(files.count) files captured)")
            return (summary, files)
        } catch {
            Log.git.error("diffStatus failed for \(directory): \(error)")
            return (.empty, [])
        }
    }

    // MARK: - Utilities

    /// Wraps an async operation with a timeout. Returns nil if the operation exceeds the deadline.
    static func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @Sendable @escaping () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
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
                    .trimmingCharacters(in: .newlines) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .newlines) ?? ""
                continuation.resume(returning: (process.terminationStatus, stdout, stderr))
            }
        }
    }
}
