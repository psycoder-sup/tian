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

/// Why a bounded walk didn't see the whole tree. The panel quotes the reason
/// back to the user, so "we stopped" and "we skipped branches" have to stay
/// distinguishable — a depth-pruned tree of 300 files must not claim it is
/// showing the first 20,000 items.
enum InspectScanTruncation: Sendable, Equatable {
    /// Stopped: hit the cap on returned files (`maxFileSystemEntries`).
    case entryCap(limit: Int)
    /// Stopped: hit the ceiling on entries *examined* (`maxFileSystemExamined`).
    /// A directory-heavy forest holds few files but costs the same to walk.
    case examinedCap(limit: Int)
    /// Pruned: directories at/below `maxFileSystemDepth` were not descended.
    case depthCap(depth: Int)
}

/// Result of a bounded filesystem walk.
struct InspectScanResult: Sendable, Equatable {
    let paths: [String]
    /// nil == the walk enumerated everything.
    let truncation: InspectScanTruncation?

    var isTruncated: Bool { truncation != nil }

    init(paths: [String], truncation: InspectScanTruncation?) {
        self.paths = paths
        self.truncation = truncation
    }

    /// Convenience for scanners that cap results themselves (the remote `find`
    /// walk) and only know that they trimmed the list.
    init(paths: [String], isTruncated: Bool) {
        self.init(paths: paths, truncation: isTruncated ? .entryCap(limit: paths.count) : nil)
    }

    static func complete(_ paths: [String]) -> InspectScanResult {
        InspectScanResult(paths: paths, truncation: nil)
    }
}

/// Thread-safe flag the synchronous filesystem walk polls to learn that the
/// awaiting task was cancelled. `Task.detached` does not inherit cancellation
/// and a blocking `FileManager.enumerator` loop can't await, so cancellation
/// has to reach the walk out-of-band.
private final class ScanCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        cancelled = true
    }
}

enum InspectFileScanner {

    /// Hard cap on entries returned by the non-repo `FileManager` walk. A
    /// session rooted at `$HOME` would otherwise enumerate millions of entries.
    static let maxFileSystemEntries = 20_000

    /// Hard ceiling on entries *examined* by the non-repo walk. The entry cap
    /// bounds the result, not the work: a directory forest with few files in it
    /// (a `node_modules` tree, a package cache) stays under `maxFileSystemEntries`
    /// forever while costing millions of `stat`s. This bounds the walk itself.
    static let maxFileSystemExamined = 200_000

    /// Hard cap on directory depth below the root for the non-repo walk.
    /// Directories at this depth are not descended into.
    static let maxFileSystemDepth = 12

    /// How often the walk polls the cancellation flag, in entries examined.
    private static let cancellationCheckStride = 256

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
    ///
    /// The walk is bounded — at most `maxEntries` paths returned, at most
    /// `maxExamined` entries visited, never descending more than `maxDepth`
    /// directories below `root` — and stops promptly when the awaiting task is
    /// cancelled, throwing `CancellationError`. Without those bounds a session
    /// rooted at `$HOME` walks millions of entries, and without cancellation the
    /// FS-event refresh piles walkers up until the app hangs. `truncation` names
    /// whichever bound cut the walk short.
    ///
    /// `maxEntries` / `maxExamined` / `maxDepth` are injectable so tests can
    /// exercise the caps without materializing 20k files; production callers use
    /// the defaults. `onEntryExamined` is a test probe for observing walk progress.
    static func scanFileSystem(
        root: URL,
        maxEntries: Int = maxFileSystemEntries,
        maxExamined: Int = maxFileSystemExamined,
        maxDepth: Int = maxFileSystemDepth,
        onEntryExamined: (@Sendable () -> Void)? = nil
    ) async throws -> InspectScanResult {
        let cancellation = ScanCancellationFlag()
        return try await withTaskCancellationHandler {
            // The walk is blocking, synchronous work — keep it off the caller's
            // thread (and off the MainActor) on a global queue. A detached Task
            // would not see cancellation, hence the explicit flag.
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try enumerateFileSystem(
                            root: root,
                            maxEntries: maxEntries,
                            maxExamined: maxExamined,
                            maxDepth: maxDepth,
                            cancellation: cancellation,
                            onEntryExamined: onEntryExamined
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func enumerateFileSystem(
        root: URL,
        maxEntries: Int,
        maxExamined: Int,
        maxDepth: Int,
        cancellation: ScanCancellationFlag,
        onEntryExamined: (@Sendable () -> Void)?
    ) throws -> InspectScanResult {
        let fm = FileManager.default
        let standardizedRoot = root.standardizedFileURL
        let rootPath = standardizedRoot.path

        // Cancellation can land before the queue picks this up.
        if cancellation.isCancelled { throw CancellationError() }

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
            return .complete([])
        }

        var paths: [String] = []
        /// The bound that ended the walk, if any. Outranks depth pruning below:
        /// stopping is a stronger statement than trimming a branch.
        var stopped: InspectScanTruncation?
        var depthPruned = false
        var examined = 0

        for case let url as URL in enumerator {
            if examined % cancellationCheckStride == 0, cancellation.isCancelled {
                throw CancellationError()
            }
            // The entry cap bounds what we return; this bounds what we walk.
            // Directories cost a visit each without ever landing in `paths`.
            if examined >= maxExamined {
                stopped = .examinedCap(limit: maxExamined)
                break
            }
            examined += 1
            onEntryExamined?()

            guard let meta = childMetadata(at: url) else { continue }
            let absolute = url.standardizedFileURL.path
            guard let relative = relativize(absolute, against: rootPath),
                  !relative.isEmpty else { continue }
            // Root's immediate children are depth 1. Counting separator bytes
            // keeps this allocation-free — `split` would build a `[Substring]`
            // per examined entry just to read its count.
            let depth = relative.utf8.count(where: { $0 == UInt8(ascii: "/") }) + 1

            if meta.isDirectory {
                // Prune with skipDescendants rather than filtering results —
                // filtering deep paths afterwards would still pay for the walk.
                // A pruned directory marks the tree partial even in the rare
                // case it turns out to be empty.
                if depth >= maxDepth {
                    enumerator.skipDescendants()
                    depthPruned = true
                }
                continue  // directories are traversed, not returned
            }
            // Skip unknown specials (sockets, fifos, ...).
            guard meta.isSymlink || meta.isRegular else { continue }

            if paths.count >= maxEntries {
                stopped = .entryCap(limit: maxEntries)
                break
            }
            paths.append(relative)
        }
        let truncation = stopped ?? (depthPruned ? .depthCap(depth: maxDepth) : nil)
        return InspectScanResult(paths: paths, truncation: truncation)
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
