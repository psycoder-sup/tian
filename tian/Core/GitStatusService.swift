import Foundation
import OSLog

/// Resolved git repository paths for a directory. `isWorktree` lets callers
/// tell apart a regular repo from a linked worktree without re-parsing the
/// `gitDir` string layout.
struct RepoLocation: Sendable, Equatable {
    let gitDir: String
    let commonDir: String
    let workingTree: String
    let isWorktree: Bool
}

/// Stateless service wrapping git CLI subprocess calls.
/// All methods are async and run subprocesses on background threads.
enum GitStatusService {

    /// Detects the git repository for a given directory.
    /// Returns nil if not in a git repo (or in a bare repo with no working tree).
    static func detectRepo(
        directory: String
    ) async -> RepoLocation? {
        do {
            let result = try await runGit(
                ["rev-parse", "--git-dir", "--git-common-dir", "--show-toplevel"],
                workingDirectory: directory
            )
            guard result.exitCode == 0, !result.stdout.isEmpty else {
                Log.git.info("Not a git repo: \(directory)")
                return nil
            }

            let lines = result.stdout.components(separatedBy: "\n")
            guard lines.count >= 3,
                  !lines[0].isEmpty, !lines[1].isEmpty, !lines[2].isEmpty else {
                Log.git.info("Unexpected rev-parse output for: \(directory)")
                return nil
            }

            let gitDir = lines[0]
            let rawCommonDir = lines[1]
            let workingTree = URL(filePath: lines[2]).standardizedFileURL.path
            let directoryURL = URL(filePath: directory, directoryHint: .isDirectory)

            func canonicalize(_ path: String) -> String {
                if path.hasPrefix("/") {
                    return URL(filePath: path).standardizedFileURL.path
                }
                return URL(filePath: path, relativeTo: directoryURL)
                    .standardizedFileURL.path
            }

            let absoluteCommonDir = canonicalize(rawCommonDir)
            let absoluteGitDir = canonicalize(gitDir)

            // For a regular repo `--git-dir` and `--git-common-dir` resolve to the
            // same path; for a linked worktree `gitDir` lives under
            // `commonDir/worktrees/NAME`. Comparing the two is more reliable than
            // a `/worktrees/` substring match against `gitDir`, which would
            // false-positive on any regular repo whose absolute `.git` path
            // happens to contain that segment.
            let isWorktree = absoluteGitDir != absoluteCommonDir

            let location = RepoLocation(
                gitDir: gitDir,
                commonDir: absoluteCommonDir,
                workingTree: workingTree,
                isWorktree: isWorktree
            )
            Log.git.debug("Detected repo at \(directory): \(String(describing: location))")
            return location
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
        await parseDiffStatus(directory: directory, maxFiles: 100, recurseUntracked: false)
    }

    /// Same shape as `diffStatus` but returns the full file list (no 100-cap)
    /// and expands untracked directories into individual files. Used by the
    /// inspect panel where every entry under an untracked directory must badge
    /// (otherwise `git status` collapses `?? dir/` and the per-file ancestor
    /// propagation in `InspectFileTreeViewModel.updateStatus` can't reach
    /// nested directories or the files themselves).
    static func diffStatusFull(
        directory: String
    ) async -> (summary: GitDiffSummary, files: [GitChangedFile]) {
        await parseDiffStatus(directory: directory, maxFiles: nil, recurseUntracked: true)
    }

    private static func parseDiffStatus(
        directory: String,
        maxFiles: Int?,
        recurseUntracked: Bool
    ) async -> (summary: GitDiffSummary, files: [GitChangedFile]) {
        do {
            var args = ["status", "--porcelain=v1", "--ignore-submodules"]
            if recurseUntracked {
                args.append("--untracked-files=all")
            }
            let result = try await runGit(
                args,
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

                // Update summary counts (always, regardless of cap)
                switch status {
                case .modified: summary.modified += 1
                case .added:    summary.added += 1
                case .deleted:  summary.deleted += 1
                case .renamed:  summary.renamed += 1
                case .unmerged: summary.unmerged += 1
                }

                if maxFiles.map({ files.count < $0 }) ?? true {
                    files.append(GitChangedFile(status: status, path: path))
                }
            }

            Log.git.debug("parseDiffStatus \(directory): \(summary.totalCount) changes (\(files.count) files captured)")
            return (summary, files)
        } catch {
            Log.git.error("parseDiffStatus failed for \(directory): \(error)")
            return (.empty, [])
        }
    }

    // MARK: - Unified Diff

    /// Returns the working-tree-vs-HEAD diff for the active space's repo.
    /// Untracked files are included as fully-added entries; files larger
    /// than 512 KB or reported as binary by git produce a `GitFileDiff`
    /// with `isBinary == true` and no hunks. Each file's `lines` array is
    /// capped at 5 000 entries; hunks past the cap set `truncatedLines`.
    /// Returns `[]` when not inside a git repo.
    static func unifiedDiff(directory: String) async -> [GitFileDiff] {
        // Verify we are inside a git repo.
        do {
            let check = try await runGit(
                ["rev-parse", "--is-inside-work-tree"],
                workingDirectory: directory
            )
            guard check.exitCode == 0 else { return [] }
        } catch {
            Log.git.error("unifiedDiff repo check failed for \(directory): \(error)")
            return []
        }

        // 1. Run `git status --porcelain` to identify untracked files (excluded from HEAD diff).
        let untrackedPaths: [String]
        do {
            let statusResult = try await runGit(
                ["status", "--porcelain=v1", "--ignore-submodules"],
                workingDirectory: directory
            )
            guard statusResult.exitCode == 0 else {
                Log.git.error("git status failed in unifiedDiff for \(directory): \(statusResult.stderr)")
                return []
            }
            let statusLines = statusResult.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
            untrackedPaths = statusLines.compactMap { line -> String? in
                guard line.count >= 4, line.hasPrefix("??") else { return nil }
                return String(line.dropFirst(3))
            }
        } catch {
            Log.git.error("unifiedDiff git status failed for \(directory): \(error)")
            return []
        }

        // 2. Run `git diff --no-color --no-ext-diff --unified=3 HEAD` for tracked changes.
        var trackedDiffs: [GitFileDiff] = []
        do {
            let diffResult = try await runGit(
                ["diff", "--no-color", "--no-ext-diff", "--unified=3", "HEAD"],
                workingDirectory: directory
            )
            if diffResult.exitCode == 0 && !diffResult.stdout.isEmpty {
                trackedDiffs = parseUnifiedDiff(diffResult.stdout)
            }
        } catch {
            Log.git.error("unifiedDiff git diff failed for \(directory): \(error)")
        }

        // 3. Handle untracked files via `git diff --no-index /dev/null <path>`.
        var untrackedDiffs: [GitFileDiff] = []
        for relativePath in untrackedPaths {
            let absolutePath = (directory as NSString).appendingPathComponent(relativePath)

            // Binary/size gate: skip files > 512 KB
            if let attrs = try? FileManager.default.attributesOfItem(atPath: absolutePath),
               let fileSize = attrs[.size] as? Int,
               fileSize > 512 * 1024 {
                untrackedDiffs.append(GitFileDiff(
                    path: relativePath,
                    status: .added,
                    additions: 0,
                    deletions: 0,
                    hunks: [],
                    isBinary: true
                ))
                continue
            }

            do {
                let noIndexResult = try await runGit(
                    ["diff", "--no-color", "--no-ext-diff", "--unified=3", "--no-index",
                     "/dev/null", relativePath],
                    workingDirectory: directory
                )
                // git diff --no-index exits 1 when files differ (normal for additions)
                let output = noIndexResult.stdout
                if output.isEmpty {
                    // No readable diff — treat as binary
                    untrackedDiffs.append(GitFileDiff(
                        path: relativePath,
                        status: .added,
                        additions: 0,
                        deletions: 0,
                        hunks: [],
                        isBinary: true
                    ))
                } else {
                    // Parse and override path + status to .added
                    let parsed = parseUnifiedDiff(output)
                    for diff in parsed {
                        untrackedDiffs.append(GitFileDiff(
                            path: relativePath,
                            status: .added,
                            additions: diff.additions,
                            deletions: diff.deletions,
                            hunks: diff.hunks,
                            isBinary: diff.isBinary
                        ))
                    }
                    if parsed.isEmpty {
                        // Binary reported
                        untrackedDiffs.append(GitFileDiff(
                            path: relativePath,
                            status: .added,
                            additions: 0,
                            deletions: 0,
                            hunks: [],
                            isBinary: true
                        ))
                    }
                }
            } catch {
                Log.git.error("unifiedDiff --no-index failed for \(relativePath): \(error)")
            }
        }

        return trackedDiffs + untrackedDiffs
    }

    // MARK: - Unified Diff Parsing Helpers

    /// Parses the output of `git diff --unified` into `[GitFileDiff]`.
    private static func parseUnifiedDiff(_ output: String) -> [GitFileDiff] {
        let lines = output.components(separatedBy: "\n")
        var results: [GitFileDiff] = []

        // State
        var currentPath: String?
        var currentStatus: GitFileStatus = .modified
        var isBinary = false
        var hunks: [GitDiffHunk] = []
        var currentHunkHeader: String?
        var currentHunkLines: [GitDiffLine] = []
        var currentHunkRawCount = 0  // all diff lines in the current hunk
        var oldLineCounter = 0
        var newLineCounter = 0
        var totalEmittedLines = 0  // across all hunks for the current file
        let lineCapPerFile = 5000

        func flushHunk() {
            guard let header = currentHunkHeader else { return }
            // Overflow = raw lines in this hunk that weren't emitted
            let hunkOverflow = currentHunkRawCount - currentHunkLines.count
            hunks.append(GitDiffHunk(
                header: header,
                lines: currentHunkLines,
                truncatedLines: max(0, hunkOverflow)
            ))
            currentHunkHeader = nil
            currentHunkLines = []
            currentHunkRawCount = 0
        }

        func flushFile() {
            guard let path = currentPath else { return }
            flushHunk()
            let additions = hunks.flatMap(\.lines).filter { $0.kind == .added }.count
            let deletions = hunks.flatMap(\.lines).filter { $0.kind == .deleted }.count
            results.append(GitFileDiff(
                path: path,
                status: currentStatus,
                additions: additions,
                deletions: deletions,
                hunks: isBinary ? [] : hunks,
                isBinary: isBinary
            ))
            // Reset
            currentPath = nil
            isBinary = false
            hunks = []
            currentHunkHeader = nil
            currentHunkLines = []
            currentHunkRawCount = 0
            oldLineCounter = 0
            newLineCounter = 0
            totalEmittedLines = 0
        }

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // New file boundary
            if line.hasPrefix("diff --git ") {
                flushFile()

                // Extract path from `diff --git a/path b/path`
                // The b/ path is the destination (post-change) file — use it as primary.
                // This is the only source for binary files (no +++ line follows).
                let afterPrefix = String(line.dropFirst("diff --git ".count))
                // Format is `a/<path> b/<path>` — split on ` b/` from the right
                if let bRange = afterPrefix.range(of: " b/", options: .backwards) {
                    let bPath = String(afterPrefix[bRange.upperBound...])
                    currentPath = bPath
                }
                currentStatus = .modified
                i += 1
                continue
            }

            // Binary marker
            if line.hasPrefix("Binary files ") {
                isBinary = true
                i += 1
                continue
            }

            // Index line (contains status hints but we rely on --- / +++ for path)
            if line.hasPrefix("index ") {
                i += 1
                continue
            }

            // Old file header — capture path for deletion case (`+++ /dev/null`)
            if line.hasPrefix("--- ") {
                let rawOldPath = String(line.dropFirst(4))
                if rawOldPath != "/dev/null" {
                    // Store tentatively; will be overridden by +++ unless it's /dev/null
                    let stripped = rawOldPath.hasPrefix("a/") ? String(rawOldPath.dropFirst(2)) : rawOldPath
                    currentPath = stripped
                }
                i += 1
                continue
            }

            // New file header — extract path
            if line.hasPrefix("+++ ") {
                let rawPath = String(line.dropFirst(4))
                if rawPath == "/dev/null" {
                    // Deletion: currentPath already set from --- line
                    currentStatus = .deleted
                } else {
                    // Strip `b/` prefix from git diff output
                    currentPath = rawPath.hasPrefix("b/") ? String(rawPath.dropFirst(2)) : rawPath
                    currentStatus = .modified
                }
                i += 1
                continue
            }

            // Hunk header
            if line.hasPrefix("@@ ") {
                flushHunk()
                currentHunkHeader = line
                if let parsed = parseHunkHeader(line) {
                    oldLineCounter = parsed.oldStart
                    newLineCounter = parsed.newStart
                }
                i += 1
                continue
            }

            // Diff lines (only inside a hunk)
            guard currentHunkHeader != nil, currentPath != nil else {
                i += 1
                continue
            }

            // Skip "\ No newline at end of file" markers
            if line.hasPrefix("\\ ") {
                i += 1
                continue
            }

            // Only count valid diff content lines (+, -, space); skip blank lines at EOF
            guard line.hasPrefix("+") || line.hasPrefix("-") || line.hasPrefix(" ") else {
                i += 1
                continue
            }

            currentHunkRawCount += 1
            if totalEmittedLines < lineCapPerFile {
                let kind: GitDiffLine.Kind
                let oldNum: Int?
                let newNum: Int?
                let text: String

                if line.hasPrefix("+") {
                    kind = .added
                    oldNum = nil
                    newNum = newLineCounter
                    newLineCounter += 1
                    text = String(line.dropFirst(1))
                } else if line.hasPrefix("-") {
                    kind = .deleted
                    oldNum = oldLineCounter
                    newNum = nil
                    oldLineCounter += 1
                    text = String(line.dropFirst(1))
                } else {
                    // Context line (starts with " " or could be empty for end-of-file)
                    kind = .context
                    oldNum = oldLineCounter
                    newNum = newLineCounter
                    oldLineCounter += 1
                    newLineCounter += 1
                    text = line.isEmpty ? "" : String(line.dropFirst(1))
                }

                currentHunkLines.append(GitDiffLine(
                    kind: kind,
                    oldLineNumber: oldNum,
                    newLineNumber: newNum,
                    text: text
                ))
                totalEmittedLines += 1
            }
            // Lines beyond cap are counted in currentHunkRawCount but not emitted

            i += 1
        }

        flushFile()
        return results
    }

    /// Parses a hunk header line like `@@ -10,6 +10,8 @@ optional context`.
    private static func parseHunkHeader(
        _ header: String
    ) -> (oldStart: Int, oldLen: Int, newStart: Int, newLen: Int)? {
        // Format: @@ -<oldStart>[,<oldLen>] +<newStart>[,<newLen>] @@
        let pattern = #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: header,
                  range: NSRange(header.startIndex..., in: header)
              ) else {
            return nil
        }

        func int(_ idx: Int) -> Int? {
            let r = match.range(at: idx)
            guard r.location != NSNotFound,
                  let range = Range(r, in: header) else { return nil }
            return Int(header[range])
        }

        guard let oldStart = int(1), let newStart = int(3) else { return nil }
        let oldLen = int(2) ?? 1
        let newLen = int(4) ?? 1
        return (oldStart, oldLen, newStart, newLen)
    }

    /// Fetches GitHub PR status for the given branch using `gh` CLI.
    /// Returns nil if gh is not installed, not authenticated, no PR exists, or any error occurs.
    /// Has a 10-second timeout per NFR-006.
    static func fetchPRStatus(
        directory: String,
        branch: String
    ) async -> PRStatus? {
        let result = await withTimeout(seconds: 10) {
            await Self._fetchPRStatus(directory: directory, branch: branch)
        }
        return result ?? nil
    }

    private static func _fetchPRStatus(
        directory: String,
        branch: String
    ) async -> PRStatus? {
        Log.git.info("fetchPRStatus start: branch=\(branch) dir=\(directory)")
        do {
            let result = try await runProcess(
                executablePath: "/usr/bin/env",
                arguments: ["gh", "pr", "view", branch, "--json", "number,state,url,isDraft"],
                workingDirectory: directory
            )
            guard result.exitCode == 0, !result.stdout.isEmpty else {
                Log.git.info("gh pr view branch=\(branch) exit=\(result.exitCode) stderr=\(result.stderr)")
                return nil
            }

            guard let data = result.stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let prNumber = json["number"] as? Int,
                  let stateString = json["state"] as? String,
                  let urlString = json["url"] as? String,
                  let url = URL(string: urlString) else {
                Log.git.info("Failed to parse gh pr view output for \(branch): \(result.stdout)")
                return nil
            }

            let isDraft = json["isDraft"] as? Bool ?? false

            let state: PRState
            if isDraft {
                state = .draft
            } else {
                switch stateString.uppercased() {
                case "OPEN": state = .open
                case "MERGED": state = .merged
                case "CLOSED": state = .closed
                default:
                    Log.git.info("Unknown PR state for \(branch): \(stateString)")
                    return nil
                }
            }

            Log.git.info("PR status for \(branch): #\(prNumber) \(state.rawValue)")
            return PRStatus(number: prNumber, state: state, url: url)
        } catch {
            Log.git.info("fetchPRStatus threw for \(branch): \(error)")
            return nil
        }
    }

    // MARK: - Commit Graph (FR-T20 / FR-T20a / FR-T25)

    /// Incremented once per subprocess invoked by `commitGraph`. Readable in
    /// tests to assert exactly 3 subprocess calls per fetch.
    nonisolated(unsafe) static var commitGraphSubprocessCounter: Int = 0

    /// Returns the commit graph rooted at HEAD for the active space's repo.
    /// Walks back up to 50 commits along first-parent of all local branch
    /// tips; lanes capped at 6 (FR-T20a). Returns `nil` when not inside a
    /// git repo. Issues exactly three subprocess calls: `git log`,
    /// `git for-each-ref`, `git tag -l`.
    static func commitGraph(directory: String) async -> GitCommitGraph? {
        // ── Subprocess #1: git log ──────────────────────────────────────────
        // %H  = full SHA
        // %h  = short SHA (7)
        // %P  = parent SHAs (space-separated)
        // %an = author name
        // %at = author timestamp (unix)
        // %s  = subject
        // %D  = ref names (decoration, comma-separated, no parentheses)
        let logFormat = "%H%x09%h%x09%P%x09%an%x09%at%x09%s%x09%D"
        let logResult: (exitCode: Int32, stdout: String, stderr: String)
        do {
            logResult = try await runGit(
                ["log", "--max-count=50", "--date-order",
                 "--pretty=format:\(logFormat)", "--all"],
                workingDirectory: directory
            )
            commitGraphSubprocessCounter += 1
        } catch {
            Log.git.error("commitGraph git log failed for \(directory): \(error)")
            return nil
        }
        guard logResult.exitCode == 0 else {
            Log.git.info("commitGraph: not a git repo or empty repo at \(directory)")
            return nil
        }

        // ── Subprocess #2: git for-each-ref ────────────────────────────────
        let refResult: (exitCode: Int32, stdout: String, stderr: String)
        do {
            refResult = try await runGit(
                ["for-each-ref", "refs/heads", "refs/remotes",
                 "--format=%(refname:short) %(objectname)"],
                workingDirectory: directory
            )
            commitGraphSubprocessCounter += 1
        } catch {
            Log.git.error("commitGraph git for-each-ref failed for \(directory): \(error)")
            return nil
        }

        // ── Subprocess #3: git tag -l ───────────────────────────────────────
        let tagResult: (exitCode: Int32, stdout: String, stderr: String)
        do {
            tagResult = try await runGit(
                ["tag", "-l", "--format=%(objectname:short) %(refname:short)"],
                workingDirectory: directory
            )
            commitGraphSubprocessCounter += 1
        } catch {
            Log.git.error("commitGraph git tag failed for \(directory): \(error)")
            return nil
        }

        // ── Parse tag dictionary: shortSha → tagName ───────────────────────
        var tagByShortSha: [String: String] = [:]
        for line in tagResult.stdout.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            guard parts.count >= 2 else { continue }
            let tagShort = parts[0]
            let tagName = parts[1...].joined(separator: " ")
            tagByShortSha[tagShort] = tagName
        }

        // ── Parse for-each-ref: build refName → fullSha and fullSha → [refName] ──
        var refBySha: [String: [String]] = [:]    // fullSha → local branch names
        var remoteRefBySha: [String: [String]] = [:] // fullSha → remote ref names
        var allRemoteRefNames = Set<String>()         // all remote ref short names (e.g. "origin/beta")
        for line in refResult.stdout.components(separatedBy: "\n") {
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            guard parts.count == 2 else { continue }
            let refName = parts[0]
            let sha = parts[1]
            if refName.hasPrefix("origin/") || refName.contains("/") {
                remoteRefBySha[sha, default: []].append(refName)
                allRemoteRefNames.insert(refName)
            } else {
                refBySha[sha, default: []].append(refName)
            }
        }

        // ── Parse git log output ────────────────────────────────────────────
        struct RawCommit {
            let sha: String
            let shortSha: String
            let parentShas: [String]
            let author: String
            let when: Date
            let subject: String
            let decorations: [String] // ref decorations on this commit
        }

        var rawCommits: [RawCommit] = []
        var headBranchName: String? = nil
        var headShortSha: String? = nil
        var trackedRemote: String? = nil   // e.g. "origin/beta"

        for line in logResult.stdout.components(separatedBy: "\n") where !line.isEmpty {
            let cols = line.components(separatedBy: "\t")
            guard cols.count >= 6 else { continue }
            let sha = cols[0]
            let shortSha = cols[1]
            let parentShasRaw = cols[2]
            let author = cols[3]
            let timestampStr = cols[4]
            let subject = cols[5]
            let decorationsRaw = cols.count >= 7 ? cols[6] : ""

            let parentShas = parentShasRaw.isEmpty
                ? []
                : parentShasRaw.components(separatedBy: " ").filter { !$0.isEmpty }
            let when = Date(timeIntervalSince1970: Double(timestampStr) ?? 0)

            // Parse decoration string: "HEAD -> branchName, origin/branchName, tagName"
            var decorations: [String] = []
            var isHead = false
            var decoratedBranch: String? = nil
            var decoratedRemote: String? = nil

            if !decorationsRaw.isEmpty {
                let parts = decorationsRaw.components(separatedBy: ", ")
                for part in parts {
                    let trimmed = part.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("HEAD -> ") {
                        isHead = true
                        let branchPart = String(trimmed.dropFirst("HEAD -> ".count))
                        decoratedBranch = branchPart
                        decorations.append(branchPart)
                    } else if trimmed == "HEAD" {
                        // Detached HEAD
                        isHead = true
                    } else {
                        decorations.append(trimmed)
                        if trimmed.hasPrefix("origin/") || trimmed.contains("/") {
                            if decoratedRemote == nil { decoratedRemote = trimmed }
                        }
                    }
                }
            }

            // Capture HEAD info from the first (newest) commit that carries HEAD
            if isHead && headBranchName == nil {
                headShortSha = shortSha
                if let branch = decoratedBranch {
                    headBranchName = branch
                    // Check if there's a matching origin/<branch> in the same decoration
                    // (e.g. "HEAD -> beta, origin/beta") → tracked remote
                    let expectedRemote = "origin/\(branch)"
                    if decorations.contains(expectedRemote) {
                        trackedRemote = expectedRemote
                    } else if let dr = decoratedRemote {
                        trackedRemote = dr
                    }
                }
                // else: detached HEAD — headBranchName stays nil
            }

            rawCommits.append(RawCommit(
                sha: sha,
                shortSha: shortSha,
                parentShas: parentShas,
                author: author,
                when: when,
                subject: subject,
                decorations: decorations
            ))
        }

        guard !rawCommits.isEmpty else {
            // Empty repo
            return GitCommitGraph(lanes: [], commits: [], collapsedLaneCount: 0)
        }

        let headShort = headShortSha ?? rawCommits[0].shortSha

        // ── Build set of SHAs in the commit window ─────────────────────────
        let commitShaSet = Set(rawCommits.map(\.sha))

        // ── Determine candidate lanes ───────────────────────────────────────
        // A lane corresponds to a local branch whose tip is in the commit window.
        // Plus HEAD's branch (even if detached, we create a synthetic lane).

        struct LaneCandidate {
            let id: String
            let label: String
            let isHead: Bool
            let hasTrackedRemote: Bool
            var commitCount: Int   // number of commits in window this branch is "closest to"
        }

        // Count commits attributed to each local branch:
        // For each commit, the "owning" branch is determined by for-each-ref SHA matches.
        // We count how many commits in the window can be reached from each branch tip.
        var branchCommitCount: [String: Int] = [:]
        let allCommitShas = rawCommits.map(\.sha)

        for (sha, branches) in refBySha {
            // Only count branches whose tip is in the commit window
            if let idx = allCommitShas.firstIndex(of: sha) {
                for branch in branches {
                    // Branch tip at position idx → it "owns" commits from idx onwards
                    // (i.e., commits that are ancestors). Simple approximation:
                    // count = commits from index idx to end of list (idx+1 because index
                    // 0 is the newest; branches further from HEAD own fewer commits)
                    branchCommitCount[branch] = (branchCommitCount[branch] ?? 0) + (allCommitShas.count - idx)
                }
            } else {
                // Branch tip not in window — skip, count 0
                for branch in branches {
                    branchCommitCount[branch] = branchCommitCount[branch] ?? 0
                }
            }
        }

        // Build candidates from all local branches with tips in the commit window
        var candidates: [LaneCandidate] = []
        var seenIds = Set<String>()

        // HEAD lane first
        let headId: String
        let headLabel: String
        if let branch = headBranchName {
            headId = branch
            headLabel = branch
        } else {
            // Detached HEAD
            headId = "HEAD@\(headShort)"
            headLabel = headShort
        }
        candidates.append(LaneCandidate(
            id: headId,
            label: headLabel,
            isHead: true,
            hasTrackedRemote: trackedRemote != nil,
            commitCount: branchCommitCount[headId] ?? (allCommitShas.count)
        ))
        seenIds.insert(headId)

        // Collect remaining branches
        var remaining: [LaneCandidate] = []
        for (sha, branches) in refBySha {
            guard commitShaSet.contains(sha) else { continue }
            for branch in branches {
                guard !seenIds.contains(branch) else { continue }
                seenIds.insert(branch)
                // A branch has a tracked remote if "origin/<branchName>" exists in the remote refs
                let isTrackedRemote = allRemoteRefNames.contains("origin/\(branch)")
                remaining.append(LaneCandidate(
                    id: branch,
                    label: branch,
                    isHead: false,
                    hasTrackedRemote: isTrackedRemote,
                    commitCount: branchCommitCount[branch] ?? 0
                ))
            }
        }

        // Sort remaining: tracked remote first, then by commit count desc, then alphabetical
        remaining.sort { a, b in
            if a.hasTrackedRemote != b.hasTrackedRemote { return a.hasTrackedRemote }
            if a.commitCount != b.commitCount { return a.commitCount > b.commitCount }
            return a.id < b.id
        }
        candidates.append(contentsOf: remaining)

        // ── Apply 6-lane cap ────────────────────────────────────────────────
        let maxNamedLanes = 6
        let namedCandidates: [LaneCandidate]
        let collapsedCount: Int
        if candidates.count > maxNamedLanes {
            namedCandidates = Array(candidates.prefix(maxNamedLanes))
            collapsedCount = candidates.count - maxNamedLanes
        } else {
            namedCandidates = candidates
            collapsedCount = 0
        }

        // Build GitLane array
        var lanes: [GitLane] = namedCandidates.enumerated().map { idx, c in
            GitLane(id: c.id, label: c.label, colorIndex: idx, isCollapsed: false)
        }
        if collapsedCount > 0 {
            lanes.append(GitLane(
                id: "__other__",
                label: "other",
                colorIndex: lanes.count,
                isCollapsed: true
            ))
        }

        // Build a fast lookup: laneId → laneIndex
        var laneIndexByID: [String: Int] = [:]
        for (idx, lane) in lanes.enumerated() {
            laneIndexByID[lane.id] = idx
        }
        let otherLaneIndex = collapsedCount > 0 ? lanes.count - 1 : nil

        // ── Build commit SHA→lane mapping ───────────────────────────────────
        // For each commit, determine its primary lane:
        //   1. If any decoration matches a named lane → use that lane
        //   2. If HEAD is on this commit → headId lane
        //   3. Otherwise → first lane whose tip SHA matches
        //   4. Fallback: other lane (or lane 0)
        func laneIndex(for raw: RawCommit) -> Int {
            // Check decorations for named lanes
            for dec in raw.decorations {
                if let idx = laneIndexByID[dec] { return idx }
            }
            // Check for-each-ref: if this commit's SHA is a branch tip
            if let branches = refBySha[raw.sha] {
                for branch in branches {
                    if let idx = laneIndexByID[branch] { return idx }
                }
            }
            // Fallback to other or lane 0
            return otherLaneIndex ?? 0
        }

        // ── Assemble GitCommit array ────────────────────────────────────────
        let commits: [GitCommit] = rawCommits.map { raw in
            // Collect headRefs: all branch names (local + remote) decorating this commit
            var headRefs = raw.decorations.filter { !$0.hasPrefix("HEAD") }
            // Add remote refs that point to this commit
            if let remotes = remoteRefBySha[raw.sha] {
                for r in remotes where !headRefs.contains(r) {
                    headRefs.append(r)
                }
            }

            // Tag lookup — try shortSha prefix match
            let tag = tagByShortSha[raw.shortSha]
                ?? tagByShortSha.first(where: { raw.sha.hasPrefix($0.key) })?.value

            return GitCommit(
                sha: raw.sha,
                shortSha: raw.shortSha,
                laneIndex: laneIndex(for: raw),
                parentShas: raw.parentShas,
                author: raw.author,
                when: raw.when,
                subject: raw.subject,
                isMerge: raw.parentShas.count > 1,
                headRefs: headRefs,
                tag: tag
            )
        }

        return GitCommitGraph(lanes: lanes, commits: commits, collapsedLaneCount: collapsedCount)
    }

    private static func runProcess(
        executablePath: String,
        arguments: [String],
        workingDirectory: String
    ) async throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(filePath: executablePath)
        process.arguments = arguments
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

                    let stdout = String(data: stdoutData, encoding: .utf8)?
                        .trimmingCharacters(in: .newlines) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .newlines) ?? ""
                    continuation.resume(returning: (process.terminationStatus, stdout, stderr))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
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
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        // --no-optional-locks prevents background reads (e.g. `git status`) from
        // racing with user-initiated writes on `.git/index.lock`.
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

                    let stdout = String(data: stdoutData, encoding: .utf8)?
                        .trimmingCharacters(in: .newlines) ?? ""
                    let stderr = String(data: stderrData, encoding: .utf8)?
                        .trimmingCharacters(in: .newlines) ?? ""
                    continuation.resume(returning: (process.terminationStatus, stdout, stderr))
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
