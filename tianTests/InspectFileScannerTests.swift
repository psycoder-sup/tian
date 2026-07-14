import Foundation
import Testing
@testable import tian

struct InspectFileScannerTests {

    // `git ls-files --cached --others --exclude-standard -z` yields tracked
    // and untracked non-ignored files. Ignored entries are intentionally
    // excluded from the scanner; the view model merges rolled-up ignored
    // directory entries from `scanGitIgnored` separately so they appear as
    // single dimmed nodes instead of 50k+ individual paths.
    // `git ls-files --others --ignored --exclude-standard --directory` returns
    // rolled-up directory entries with a trailing slash and individually-listed
    // file entries without one. The scanner splits them so the view model can
    // render directories as expandable nodes with lazy-loaded children.
    @Test func gitIgnoredSplitsDirectoriesAndFiles() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // .gitignore: `node_modules/` (rolled-up dir) + `*.log` (file pattern).
        let gitignorePath = (repo as NSString).appendingPathComponent(".gitignore")
        try "node_modules/\n*.log\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)

        // Ignored directory with descendants — `--directory` should roll up.
        let nodeModules = (repo as NSString).appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(atPath: nodeModules, withIntermediateDirectories: true)
        let nm1 = (nodeModules as NSString).appendingPathComponent("pkg.json")
        try "{}".write(toFile: nm1, atomically: true, encoding: .utf8)

        // Ignored individual file matching `*.log`.
        let logPath = (repo as NSString).appendingPathComponent("debug.log")
        try "log".write(toFile: logPath, atomically: true, encoding: .utf8)

        let result = try await InspectFileScanner.scanGitIgnored(workingTree: repo)
        #expect(result.directories.contains("node_modules"))
        #expect(result.files.contains("debug.log"))
        // Rolled-up dir must NOT also appear in files (and vice versa).
        #expect(!result.files.contains("node_modules"))
        #expect(!result.directories.contains("debug.log"))
        // Descendants of the rolled-up dir must not be enumerated.
        #expect(!result.files.contains("node_modules/pkg.json"))
    }

    // `scanImmediateChildren` powers lazy expansion of rolled-up ignored
    // directories. Returns one-level children, each tagged file or directory.
    @Test func scanImmediateChildrenReturnsOneLevelKinds() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let fileA = (dir as NSString).appendingPathComponent("a.txt")
        try "a".write(toFile: fileA, atomically: true, encoding: .utf8)

        let nestedDir = (dir as NSString).appendingPathComponent("nested")
        try FileManager.default.createDirectory(atPath: nestedDir, withIntermediateDirectories: true)
        // Grandchild — must NOT appear at the parent level.
        let nestedFile = (nestedDir as NSString).appendingPathComponent("b.txt")
        try "b".write(toFile: nestedFile, atomically: true, encoding: .utf8)

        let children = try await InspectFileScanner.scanImmediateChildren(absolutePath: dir)
        let byName = Dictionary(uniqueKeysWithValues: children.map { ($0.name, $0.isDirectory) })

        #expect(byName["a.txt"] == false)
        #expect(byName["nested"] == true)
        // Grandchild must not surface — only one level deep.
        #expect(byName["b.txt"] == nil)
    }

    @Test func gitTrackedReturnsTrackedAndUntrackedNotIgnored() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Tracked file (committed by makeTempGitRepo as README.md). Add another.
        let trackedPath = (repo as NSString).appendingPathComponent("tracked.txt")
        try "tracked".write(toFile: trackedPath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "tracked.txt"], in: repo)
        try runGitSync(["commit", "-m", "add tracked"], in: repo)

        // .gitignore lists ignored.txt.
        let gitignorePath = (repo as NSString).appendingPathComponent(".gitignore")
        try "ignored.txt\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)

        // Untracked-not-ignored file.
        let untrackedPath = (repo as NSString).appendingPathComponent("untracked.txt")
        try "untracked".write(toFile: untrackedPath, atomically: true, encoding: .utf8)

        // Ignored file — present on disk and referenced by .gitignore.
        let ignoredPath = (repo as NSString).appendingPathComponent("ignored.txt")
        try "ignored".write(toFile: ignoredPath, atomically: true, encoding: .utf8)

        let result = try await InspectFileScanner.scanGitTracked(workingTree: repo)
        #expect(result.contains("tracked.txt"))
        #expect(result.contains("untracked.txt"))
        // With --exclude-standard the scanner no longer returns ignored files;
        // the view model merges rolled-up ignored dirs from scanGitIgnored.
        #expect(!result.contains("ignored.txt"))
    }

    // FR-15 / FR-22 — outside a git repo, fall back to FileManager enumeration.
    @Test func fileSystemFallbackEnumeratesNonGitDir() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let fileA = (dir as NSString).appendingPathComponent("a.txt")
        try "a".write(toFile: fileA, atomically: true, encoding: .utf8)

        let nestedDir = (dir as NSString).appendingPathComponent("nested")
        try FileManager.default.createDirectory(atPath: nestedDir, withIntermediateDirectories: true)
        let nestedFile = (nestedDir as NSString).appendingPathComponent("b.txt")
        try "b".write(toFile: nestedFile, atomically: true, encoding: .utf8)

        let result = try await InspectFileScanner.scanFileSystem(root: URL(filePath: dir))
        #expect(result.paths.contains("a.txt"))
        #expect(result.paths.contains("nested/b.txt"))
        // No leading `./`.
        #expect(!result.paths.contains(where: { $0.hasPrefix("./") }))
        // Well under every cap — the tree shown is complete.
        #expect(result.truncation == nil)
        #expect(result.isTruncated == false)
    }

    @Test func fileSystemFallbackOnEmptyDirReturnsEmpty() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let result = try await InspectFileScanner.scanFileSystem(root: URL(filePath: dir))
        #expect(result.paths.isEmpty)
        #expect(result.isTruncated == false)
    }

    // FR-16 — hidden dotfiles (`.env`) shown when not gitignored.
    @Test func dotfilesShownWhenNotIgnored() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let envPath = (repo as NSString).appendingPathComponent(".env")
        try "SECRET=1".write(toFile: envPath, atomically: true, encoding: .utf8)

        let result = try await InspectFileScanner.scanGitTracked(workingTree: repo)
        #expect(result.contains(".env"))
    }

    // FR-17 — symlinks shown as files, target not followed.
    @Test func symlinksReturnedAsFiles() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Create the symlink target outside `dir` so that following the
        // symlink would (incorrectly) surface the target file.
        let outsideDir = try makeTempDir()
        defer { cleanup(outsideDir) }
        let targetPath = (outsideDir as NSString).appendingPathComponent("target.txt")
        try "target contents".write(toFile: targetPath, atomically: true, encoding: .utf8)

        let linkPath = (dir as NSString).appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: targetPath)

        let result = try await InspectFileScanner.scanFileSystem(root: URL(filePath: dir))
        #expect(result.paths.contains("link.txt"))
        // Symlink target must not surface under the symlink path.
        #expect(!result.paths.contains(where: { $0.contains("target.txt") }))
    }

    // MARK: - Bounded, cancellable filesystem walk

    // The bug this guards: the walk ran in a `Task.detached` (which does not
    // inherit cancellation) and never polled for it, so every "cancelled" scan
    // kept enumerating to completion. FS-event refreshes fire ~1/sec, so
    // walkers piled up until the app hit 600% CPU / multi-GB RSS.
    //
    // Asserting only that `CancellationError` surfaces would have PASSED
    // against the buggy code (the awaiting task throws on cancellation while
    // the detached walk grinds on). So this test proves the walk itself halts:
    // it counts entries examined via the walk's own probe, cancels early, then
    // waits long enough for a runaway walk to have visited the whole tree and
    // asserts the counter never moved again and never reached the total.
    @Test func cancelledFileSystemScanStopsWalking() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // 20 dirs x 50 files = 1020 entries. The probe sleeps 2ms per entry, so
        // an uncancelled walk needs ~2s to finish.
        let directoryCount = 20
        let filesPerDirectory = 50
        let totalEntries = directoryCount + directoryCount * filesPerDirectory
        for d in 0..<directoryCount {
            let sub = (dir as NSString).appendingPathComponent("dir\(d)")
            try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
            for f in 0..<filesPerDirectory {
                let file = (sub as NSString).appendingPathComponent("f\(f).txt")
                try "x".write(toFile: file, atomically: true, encoding: .utf8)
            }
        }

        let examined = Counter()
        let task = Task {
            try await InspectFileScanner.scanFileSystem(
                root: URL(filePath: dir),
                maxEntries: 100_000,
                maxDepth: 32,
                onEntryExamined: {
                    examined.increment()
                    usleep(2_000)  // 2ms — slow the walk so cancellation lands mid-flight
                }
            )
        }

        // Wait for the walk to get going, then cancel it mid-flight.
        var waited = 0
        while examined.value < 20 && waited < 300 {
            try await Task.sleep(for: .milliseconds(10))
            waited += 1
        }
        #expect(examined.value >= 20, "walk never started; the rest of this test proves nothing")
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        let atCancellation = examined.value
        // A runaway walk would visit the remaining ~800 entries in this window.
        try await Task.sleep(for: .milliseconds(1_500))

        #expect(examined.value == atCancellation, "enumeration kept running after cancellation")
        #expect(examined.value < totalEntries, "walk ran to completion despite cancellation")
        // Cancellation is polled every 256 entries, so the walk stops within
        // one stride of the flag being set — nowhere near the full tree.
        #expect(examined.value <= 512)
    }

    // Caps are injected here so the test doesn't have to materialize 20k files;
    // the production defaults are `maxFileSystemEntries` / `maxFileSystemDepth`.
    @Test func fileSystemScanEnforcesEntryCap() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        for i in 0..<10 {
            let file = (dir as NSString).appendingPathComponent("f\(i).txt")
            try "x".write(toFile: file, atomically: true, encoding: .utf8)
        }

        let result = try await InspectFileScanner.scanFileSystem(
            root: URL(filePath: dir),
            maxEntries: 4
        )
        #expect(result.paths.count == 4)
        #expect(result.truncation == .entryCap(limit: 4))
    }

    // The entry cap bounds the *result*, not the *work*: directories are visited
    // but never land in `paths`, so a forest of directories holding almost no
    // files would walk forever under the entry cap alone. The examined ceiling
    // is what actually bounds the walk — this tree has zero files, so nothing
    // but that ceiling can stop it.
    @Test func fileSystemScanEnforcesExaminedCapOnDirectoryHeavyTree() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // 60 directories, no files, all at depth 1-2 — under the entry and
        // depth caps by a mile.
        for d in 0..<30 {
            let sub = (dir as NSString).appendingPathComponent("dir\(d)/inner")
            try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        }

        let examined = Counter()
        let result = try await InspectFileScanner.scanFileSystem(
            root: URL(filePath: dir),
            maxEntries: 20_000,
            maxExamined: 10,
            maxDepth: 12,
            onEntryExamined: { examined.increment() }
        )

        #expect(result.truncation == .examinedCap(limit: 10))
        #expect(result.paths.isEmpty)
        // The walk stopped at the ceiling instead of enumerating all 60 dirs.
        #expect(examined.value == 10)
    }

    @Test func fileSystemScanEnforcesDepthCap() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // f0.txt, l1/f1.txt, l1/l2/f2.txt, ... one file per level.
        var current = dir
        let root = (dir as NSString).appendingPathComponent("f0.txt")
        try "x".write(toFile: root, atomically: true, encoding: .utf8)
        for level in 1...5 {
            current = (current as NSString).appendingPathComponent("l\(level)")
            try FileManager.default.createDirectory(atPath: current, withIntermediateDirectories: true)
            let file = (current as NSString).appendingPathComponent("f\(level).txt")
            try "x".write(toFile: file, atomically: true, encoding: .utf8)
        }

        let result = try await InspectFileScanner.scanFileSystem(
            root: URL(filePath: dir),
            maxDepth: 3
        )
        // Depth 3 admits `f0.txt` (1), `l1/f1.txt` (2), `l1/l2/f2.txt` (3);
        // `l1/l2/l3` is at the cap, so it is never descended into.
        #expect(result.paths.sorted() == ["f0.txt", "l1/f1.txt", "l1/l2/f2.txt"])
        #expect(!result.paths.contains(where: { $0.split(separator: "/").count > 3 }))
        // Pruned by depth, NOT stopped at the entry cap — the banner would
        // otherwise offer to show "the first 20,000" of these three files.
        #expect(result.truncation == .depthCap(depth: 3))
    }

    @Test func fileSystemScanUnderCapsIsNotTruncated() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let nested = (dir as NSString).appendingPathComponent("a/b")
        try FileManager.default.createDirectory(atPath: nested, withIntermediateDirectories: true)
        try "x".write(toFile: (dir as NSString).appendingPathComponent("top.txt"),
                      atomically: true, encoding: .utf8)
        try "x".write(toFile: (nested as NSString).appendingPathComponent("deep.txt"),
                      atomically: true, encoding: .utf8)

        let result = try await InspectFileScanner.scanFileSystem(root: URL(filePath: dir))
        #expect(result.paths.sorted() == ["a/b/deep.txt", "top.txt"])
        #expect(result.truncation == nil)
        #expect(result.isTruncated == false)
    }

    // Both bounds hit at once: the one that STOPPED the walk wins over the one
    // that merely trimmed a branch, so the banner says "too large", not "too deep".
    @Test func stoppingBoundOutranksDepthPruning() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Files at the root (so the entry cap can bite) plus a branch below the
        // depth cap (so pruning happens too).
        for i in 0..<10 {
            try "x".write(toFile: (dir as NSString).appendingPathComponent("f\(i).txt"),
                          atomically: true, encoding: .utf8)
        }
        let deep = (dir as NSString).appendingPathComponent("a/b/c/d")
        try FileManager.default.createDirectory(atPath: deep, withIntermediateDirectories: true)

        let result = try await InspectFileScanner.scanFileSystem(
            root: URL(filePath: dir),
            maxEntries: 2,
            maxDepth: 2
        )
        #expect(result.truncation == .entryCap(limit: 2))
    }

    // MARK: - Helpers

    /// Counts entries the walk examined. Mutated from the walk's queue and read
    /// from the test's task, hence the lock.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-scanner-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)
        let readme = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readme, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial"], in: dir)
        return dir
    }

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-scanner-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func runGitSync(_ args: [String], in dir: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(filePath: dir)
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw StringError("git \(args.joined(separator: " ")) failed: \(msg)")
        }
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private struct StringError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
