import Foundation
import os
import Testing
@testable import tian

@MainActor
struct InspectFileTreeViewModelTests {

    // MARK: - FR-19a — badge match by relative path

    @Test func statusBadgeMatchesByRelativePath() async {
        let scanner = FixedScanner(gitTracked: ["auth/middleware.ts", "auth/tokens.ts", "README.md"])
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/fake-root"))
        await vm.waitForFirstScan()

        vm.updateStatus([
            GitChangedFile(status: .modified, path: "auth/middleware.ts")
        ])

        #expect(vm.statusByRelativePath["auth/middleware.ts"] == .modified)
        #expect(vm.statusByRelativePath["auth/tokens.ts"] == nil)
        #expect(vm.statusByRelativePath["README.md"] == nil)

        // The matching FileTreeNode has the relativePath used for the lookup.
        // (Use the full unfiltered tree — `auth/` is collapsed by default
        // per FR-13, so its child isn't in visibleRows yet.)
        let middleware = vm.allNodesContaining(relativePath: "auth/middleware.ts")
        #expect(middleware != nil)
    }

    // MARK: - FR-19b — rename produces R on the new path

    @Test func renamedFileBadgesNewPath() async {
        let scanner = FixedScanner(gitTracked: [
            "src/old-name.ts",     // still present on disk in this scan
            "src/new-name.ts",     // the rename target
            "untouched.txt",
        ])
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/fake-root"))
        await vm.waitForFirstScan()

        // Note: GitChangedFile only carries the *new* path for renames (see
        // GitStatusService parsing). FR-19b's "D on old path if still present"
        // requires upstream parsing changes — this test verifies the slice we
        // can express today: R lands on the rename's path.
        vm.updateStatus([
            GitChangedFile(status: .renamed, path: "src/new-name.ts")
        ])

        #expect(vm.statusByRelativePath["src/new-name.ts"] == .renamed)
        #expect(vm.statusByRelativePath["untouched.txt"] == nil)
    }

    // MARK: - Directory rows inherit descendant status

    @Test func directoryInheritsDescendantStatus() async {
        let scanner = FixedScanner(gitTracked: ["auth/middleware.ts", "auth/tokens.ts"])
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/fake-root"))
        await vm.waitForFirstScan()

        vm.updateStatus([
            GitChangedFile(status: .modified, path: "auth/middleware.ts")
        ])

        // Directory `auth` inherits its descendant's status.
        #expect(vm.statusByRelativePath["auth"] == .modified)
    }

    @Test func directoryStatusUsesHighestSeverity() async {
        let scanner = FixedScanner(gitTracked: [
            "src/feature/added.ts",
            "src/feature/changed.ts",
            "src/other/new.ts",
        ])
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/fake-root"))
        await vm.waitForFirstScan()

        // src/feature has both A and M descendants; M outranks A.
        // src/other has only A.
        vm.updateStatus([
            GitChangedFile(status: .added,    path: "src/feature/added.ts"),
            GitChangedFile(status: .modified, path: "src/feature/changed.ts"),
            GitChangedFile(status: .added,    path: "src/other/new.ts"),
        ])

        #expect(vm.statusByRelativePath["src/feature"] == .modified)
        #expect(vm.statusByRelativePath["src/other"] == .added)
        // src has both A and M descendants; should resolve to M.
        #expect(vm.statusByRelativePath["src"] == .modified)
    }

    // MARK: - FR-23 / FR-26 — selection clears when path disappears

    @Test func selectionClearsWhenPathDisappears() async {
        let initialScanner = FixedScanner(gitTracked: ["auth/tokens.ts", "auth/middleware.ts"])
        let vm = InspectFileTreeViewModel(
            scanner: initialScanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/fake-root"))
        await vm.waitForFirstScan()

        // Find absolute path of auth/tokens.ts
        let tokensRow = vm.visibleRowsContaining(relativePath: "auth/tokens.ts")
            ?? vm.allNodesContaining(relativePath: "auth/tokens.ts")
        #expect(tokensRow != nil)
        guard let tokensRow else { return }

        vm.expandedPaths.insert(tokensRow.id.replacingLastPathComponent())
        vm.select(tokensRow.id)
        #expect(vm.selectedPath == tokensRow.id)

        // Re-root with a scanner that no longer contains tokens.ts.
        let scanner2 = FixedScanner(gitTracked: ["auth/middleware.ts"])
        vm.setRootForTest(URL(filePath: "/tmp/fake-root"), scanner: scanner2)
        await vm.waitForFirstScan()

        #expect(vm.selectedPath == nil)
    }

    // MARK: - FR-27 / FR-28a — setRoot cancels in-flight scan

    @Test func setRootCancelsInFlightScan() async {
        let blocking = BlockingScanner()
        let vm = InspectFileTreeViewModel(
            scanner: blocking,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .seconds(60)
        )

        let dir1 = "/tmp/blocking-dir-1"
        let dir2 = "/tmp/responsive-dir-2"

        vm.setRoot(URL(filePath: dir1))   // blocks indefinitely

        // Let the first scan task start executing the blocking scanner before
        // we cancel it. Without this wait the task may still be queued —
        // cancellation would land at the earlier `Task.isCancelled` guard in
        // `runScan`, never reaching the scanner where `cancelObserved` flips.
        try? await pollUntil(timeout: .seconds(2)) { blocking.isRunning }
        #expect(blocking.isRunning)

        // Second setRoot uses a different (non-blocking) scanner. The first
        // scan task must be cancelled. The second scan completes immediately.
        let responsive = FixedScanner(gitTracked: ["alpha.txt", "beta/gamma.txt"])
        vm.setRootForTest(URL(filePath: dir2), scanner: responsive)

        await vm.waitForFirstScan()

        #expect(vm.rootDirectory?.path == dir2)
        // None of the rows should reference dir1 — they all live under dir2.
        #expect(vm.visibleRows.allSatisfy { $0.id.hasPrefix(dir2) })
        // And the scanner used for dir2 produced visible rows.
        #expect(!vm.visibleRows.isEmpty)
        // The blocked task observed cancellation (didn't deadlock the test).
        // The cancelled scan runs concurrently; poll briefly until it exits.
        try? await pollUntil(timeout: .milliseconds(500)) {
            blocking.cancelObserved
        }
        #expect(blocking.cancelObserved)
    }

    // MARK: - FR-28 — refresh preserves expansion + selection

    @Test func refreshPreservesExpansionAndSelection() async {
        let scanner = FixedScanner(gitTracked: ["auth/tokens.ts", "auth/middleware.ts", "README.md"])
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        let root = URL(filePath: "/tmp/refresh-root")
        vm.setRoot(root)
        await vm.waitForFirstScan()

        // Expand `auth/`.
        let authID = root.path + "/auth"
        vm.toggle(authID)
        #expect(vm.expandedPaths.contains(authID))

        // Select `auth/tokens.ts`.
        let tokensID = root.path + "/auth/tokens.ts"
        vm.select(tokensID)
        #expect(vm.selectedPath == tokensID)

        // Refresh: same scanner output, fresh setRoot.
        vm.setRoot(root)
        await vm.waitForFirstScan()

        #expect(vm.expandedPaths.contains(authID))
        #expect(vm.selectedPath == tokensID)
        // Token row is still in visibleRows because auth/ is expanded.
        #expect(vm.visibleRows.contains(where: { $0.id == tokensID }))
    }

    // MARK: - Rolled-up ignored directories render as folders, not files

    @Test func ignoredDirectoryAppearsAsDirectoryNode() async {
        let scanner = FixedScanner(
            gitTracked: ["src/main.swift", "README.md"],
            gitIgnored: InspectIgnoredEntries(directories: ["node_modules"], files: [])
        )
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/fake-root"))
        await vm.waitForFirstScan()

        let node = vm.allNodesContaining(relativePath: "node_modules")
        #expect(node != nil)
        #expect(node?.isDirectory == true)
        // Sanity: a regular ignored *file* still renders as a file.
        let ignoredFiles = InspectIgnoredEntries(directories: [], files: ["debug.log"])
        let scanner2 = FixedScanner(gitTracked: ["src/main.swift"], gitIgnored: ignoredFiles)
        let vm2 = InspectFileTreeViewModel(
            scanner: scanner2,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )
        vm2.setRoot(URL(filePath: "/tmp/fake-root"))
        await vm2.waitForFirstScan()
        let logNode = vm2.allNodesContaining(relativePath: "debug.log")
        #expect(logNode != nil)
        #expect(logNode?.isDirectory == false)
    }

    @Test func ignoredDirectoryReportedAsIgnored() async {
        let scanner = FixedScanner(
            gitTracked: ["src/main.swift"],
            gitIgnored: InspectIgnoredEntries(directories: ["node_modules"], files: [])
        )
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/fake-root"))
        await vm.waitForFirstScan()

        // Both the rolled-up dir itself AND descendants must report as ignored
        // so the view can dim them — descendants come from parent walking.
        #expect(vm.isIgnored("node_modules"))
        #expect(vm.isIgnored("node_modules/pkg/index.js"))
        #expect(!vm.isIgnored("src/main.swift"))
    }

    // MARK: - Lazy expansion of rolled-up ignored directories

    @Test func togglingIgnoredDirectoryLazyLoadsChildren() async {
        let root = URL(filePath: "/tmp/fake-root")
        let nodeModulesAbs = root.path + "/node_modules"
        let scanner = FixedScanner(
            gitTracked: ["src/main.swift"],
            gitIgnored: InspectIgnoredEntries(directories: ["node_modules"], files: []),
            immediateChildren: [
                nodeModulesAbs: [
                    InspectChildEntry(name: "lodash", isDirectory: true),
                    InspectChildEntry(name: "package.json", isDirectory: false),
                ]
            ]
        )
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(root)
        await vm.waitForFirstScan()

        #expect(vm.allNodesContaining(relativePath: "node_modules/lodash") == nil)
        #expect(vm.allNodesContaining(relativePath: "node_modules/package.json") == nil)

        vm.toggle(nodeModulesAbs)
        await vm.waitForPendingIgnoredChildrenLoads()

        let lodash = vm.allNodesContaining(relativePath: "node_modules/lodash")
        let pkg = vm.allNodesContaining(relativePath: "node_modules/package.json")
        #expect(lodash?.isDirectory == true)
        #expect(pkg?.isDirectory == false)
        // Visible rows must include the lazy-loaded children, sorted dirs-first.
        let visibleRels = vm.visibleRows.map(\.relativePath)
        #expect(visibleRels.contains("node_modules/lodash"))
        #expect(visibleRels.contains("node_modules/package.json"))
        // And lazy-loaded descendants are still ignored (parent walk).
        #expect(vm.isIgnored("node_modules/lodash"))
        #expect(vm.isIgnored("node_modules/package.json"))
    }

    @Test func collapsingIgnoredDirectoryDoesNotReFetch() async {
        let root = URL(filePath: "/tmp/fake-root")
        let nodeModulesAbs = root.path + "/node_modules"
        let scanner = CountingScanner(
            gitTracked: ["src/main.swift"],
            gitIgnored: InspectIgnoredEntries(directories: ["node_modules"], files: []),
            immediateChildren: [
                nodeModulesAbs: [InspectChildEntry(name: "pkg.json", isDirectory: false)]
            ]
        )
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(root)
        await vm.waitForFirstScan()

        vm.toggle(nodeModulesAbs)             // expand → triggers load
        await vm.waitForPendingIgnoredChildrenLoads()
        #expect(scanner.immediateChildrenCallCount == 1)

        vm.toggle(nodeModulesAbs)             // collapse — no scan
        await vm.waitForPendingIgnoredChildrenLoads()
        vm.toggle(nodeModulesAbs)             // re-expand — children already loaded
        await vm.waitForPendingIgnoredChildrenLoads()
        #expect(scanner.immediateChildrenCallCount == 1)
    }

    // MARK: - FR-32 / FR-34 — slow scan flag

    @Test func slowScanFlagFlipsAfterFiveSeconds() async throws {
        let blocking = BlockingScanner()
        let vm = InspectFileTreeViewModel(
            scanner: blocking,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/slow-root"))

        // Wait long enough for the slow-flag timer to fire.
        try await Task.sleep(for: .milliseconds(150))

        #expect(vm.isInitialScanInFlight == true)
        #expect(vm.isInitialScanSlow == true)
    }

    // MARK: - Pathological roots are refused outright

    @Test func tooBroadRootStartsNoScanAndNoWatcher() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(ScanRootGuard.isTooBroad(home))   // guard precondition for this test

        let scanner = CountingScanner(gitTracked: ["should-never-be-scanned.txt"])
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .notARepo },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(home)
        await vm.waitForScansToSettle()

        #expect(vm.scanOutcome == .rootTooBroad(path: home.path))
        #expect(scanner.treeScanCallCount == 0)
        #expect(vm.hasWatcherForTest == false)
        #expect(vm.visibleRows.isEmpty)
        #expect(vm.allNodesForTest.isEmpty)
        #expect(vm.isInitialScanInFlight == false)

        // A watcher/poll tick landing on a refused root must not resurrect the
        // walk either.
        vm.refresh()
        await vm.waitForScansToSettle()
        #expect(scanner.treeScanCallCount == 0)

        // Even a root git *thinks* is a repo stays refused.
        let repoVM = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )
        repoVM.setRoot(home)
        await repoVM.waitForScansToSettle()
        #expect(repoVM.scanOutcome == .rootTooBroad(path: home.path))
        #expect(scanner.treeScanCallCount == 0)
        #expect(repoVM.hasWatcherForTest == false)
    }

    @Test func movingOffATooBroadRootScansNormally() async {
        let scanner = FixedScanner(gitTracked: ["src/main.swift"])
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(FileManager.default.homeDirectoryForCurrentUser)
        await vm.waitForScansToSettle()
        #expect(vm.visibleRows.isEmpty)

        vm.setRoot(URL(filePath: "/tmp/fake-root"))
        await vm.waitForScansToSettle()

        #expect(vm.scanOutcome == .normal)
        #expect(vm.allNodesContaining(relativePath: "src/main.swift") != nil)
    }

    // MARK: - Truncated scans

    @Test func truncatedScanReportsOutcomeAndRendersPartialTree() async {
        let scanner = FixedScanner(
            gitTracked: ["a.txt", "deep/b.txt"],
            fileSystemTruncation: .entryCap(limit: InspectFileScanner.maxFileSystemEntries)
        )
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .notARepo },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/truncated-root"))
        await vm.waitForScansToSettle()

        #expect(vm.scanOutcome == .truncated(
            reason: .entryCap(limit: InspectFileScanner.maxFileSystemEntries),
            shown: 2
        ))
        // The partial tree still renders.
        #expect(vm.allNodesContaining(relativePath: "a.txt") != nil)
        #expect(vm.allNodesContaining(relativePath: "deep/b.txt") != nil)

        // A subsequent clean scan clears the banner.
        vm.setRootForTest(
            URL(filePath: "/tmp/truncated-root"),
            scanner: FixedScanner(gitTracked: ["a.txt"])
        )
        await vm.waitForScansToSettle()
        #expect(vm.scanOutcome == .normal)
    }

    // The bug: any truncation was reported as `.truncated(limit: 20_000)`, so a
    // tree pruned by DEPTH — three files deep in a nested project — rendered
    // "Showing first 20,000 items" above three rows. The reason and the count
    // shown must both be the real ones.
    @Test func depthTruncatedScanReportsDepthReasonAndShownCount() async {
        let scanner = FixedScanner(
            gitTracked: ["a.txt", "deep/b.txt", "deep/c.txt"],
            fileSystemTruncation: .depthCap(depth: InspectFileScanner.maxFileSystemDepth)
        )
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .notARepo },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/deep-root"))
        await vm.waitForScansToSettle()

        #expect(vm.scanOutcome == .truncated(
            reason: .depthCap(depth: InspectFileScanner.maxFileSystemDepth),
            shown: 3
        ))
    }

    @Test func examinedCapTruncationSurfacesAsItsOwnReason() async {
        let scanner = FixedScanner(
            gitTracked: ["only.txt"],
            fileSystemTruncation: .examinedCap(limit: InspectFileScanner.maxFileSystemExamined)
        )
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .notARepo },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/dir-forest-root"))
        await vm.waitForScansToSettle()

        #expect(vm.scanOutcome == .truncated(
            reason: .examinedCap(limit: InspectFileScanner.maxFileSystemExamined),
            shown: 1
        ))
    }

    // MARK: - Refresh coalescing

    @Test func refreshesDuringScanCoalesceIntoOneTrailingScan() async throws {
        let gated = GatedScanner(paths: ["alpha.txt", "beta/gamma.txt"])
        let vm = InspectFileTreeViewModel(
            scanner: gated,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .seconds(60)
        )

        vm.setRoot(URL(filePath: "/tmp/coalesce-root"))
        try await pollUntil(timeout: .seconds(2)) { gated.isRunning }
        #expect(gated.treeScanCallCount == 1)

        // A burst of FS events while the first scan is parked: none of these may
        // spawn a scan of their own.
        for _ in 0..<10 { vm.refresh() }
        #expect(gated.treeScanCallCount == 1)

        gated.release()
        await vm.waitForScansToSettle()

        // Exactly one trailing rescan — the 10 refreshes collapsed into it.
        #expect(gated.treeScanCallCount == 2)
        #expect(vm.visibleRows.isEmpty == false)

        // And nothing keeps scanning once the tree has settled.
        try await Task.sleep(for: .milliseconds(100))
        #expect(gated.treeScanCallCount == 2)
    }

    @Test func refreshWithNoScanInFlightScansImmediately() async {
        let scanner = CountingScanner(gitTracked: ["one.txt"])
        let vm = InspectFileTreeViewModel(
            scanner: scanner,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )

        vm.setRoot(URL(filePath: "/tmp/refresh-idle-root"))
        await vm.waitForScansToSettle()
        #expect(scanner.treeScanCallCount == 1)

        vm.refresh()
        await vm.waitForScansToSettle()
        #expect(scanner.treeScanCallCount == 2)
    }

    // MARK: - Cancellation stops the tree build

    @Test func buildNodesAbandonsWorkWhenCancelled() async {
        // Enough entries that the build loop is the expensive half of a scan —
        // on a capped filesystem walk this is 20k paths.
        let paths = (0..<5_000).map { "dir\($0 % 64)/file\($0).txt" }

        let build = Task.detached { () -> Int in
            // Park until this task is cancelled, then run the build: it must
            // refuse to grind through the paths rather than return a tree
            // nobody is waiting for.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
            let result = try InspectFileTreeViewModel.buildNodes(
                rootPath: "/tmp/cancelled-build",
                paths: paths
            )
            return result.nodes.count
        }
        build.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await build.value
        }
    }

    @Test func cancellingScanLeavesNoStaleTree() async throws {
        let blocking = BlockingScanner()
        let vm = InspectFileTreeViewModel(
            scanner: blocking,
            classify: { _ in .mainCheckout },
            slowFlagDelay: .seconds(60)
        )

        vm.setRoot(URL(filePath: "/tmp/cancel-root-1"))
        try await pollUntil(timeout: .seconds(2)) { blocking.isRunning }

        // Re-root to nil: the in-flight scan is cancelled and must never write
        // its nodes (nor a partially built tree) into the empty state.
        vm.setRoot(nil)
        try await pollUntil(timeout: .seconds(1)) { blocking.cancelObserved }
        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.allNodesForTest.isEmpty)
        #expect(vm.visibleRows.isEmpty)
        #expect(vm.rootDirectory == nil)
    }

    // MARK: - Watcher debounce scales with the root's kind

    @Test func nonRepoRootGetsLongerWatcherDebounce() async {
        let repoVM = InspectFileTreeViewModel(
            scanner: FixedScanner(gitTracked: ["src/main.swift"]),
            classify: { _ in .mainCheckout },
            slowFlagDelay: .milliseconds(50)
        )
        repoVM.setRoot(URL(filePath: "/tmp/debounce-repo"))
        await repoVM.waitForScansToSettle()
        #expect(repoVM.startedWatcherDebounceForTest == .milliseconds(250))

        let looseVM = InspectFileTreeViewModel(
            scanner: FixedScanner(gitTracked: ["notes.md"]),
            classify: { _ in .notARepo },
            slowFlagDelay: .milliseconds(50)
        )
        looseVM.setRoot(URL(filePath: "/tmp/debounce-loose"))
        await looseVM.waitForScansToSettle()
        #expect(looseVM.startedWatcherDebounceForTest == .seconds(2))
    }
}

// MARK: - Test scanners

private final class FixedScanner: InspectFileScanning, @unchecked Sendable {
    private let gitTracked: [String]
    private let gitIgnored: InspectIgnoredEntries
    /// Keyed by absolute path; returned by `scanImmediateChildren` to drive
    /// lazy expansion of rolled-up ignored directories.
    private let immediateChildren: [String: [InspectChildEntry]]
    /// Makes `scanFileSystem` report a bounded walk (`.notARepo` roots only).
    private let fileSystemTruncation: InspectScanTruncation?

    init(
        gitTracked: [String],
        gitIgnored: InspectIgnoredEntries = .empty,
        immediateChildren: [String: [InspectChildEntry]] = [:],
        fileSystemTruncation: InspectScanTruncation? = nil
    ) {
        self.gitTracked = gitTracked
        self.gitIgnored = gitIgnored
        self.immediateChildren = immediateChildren
        self.fileSystemTruncation = fileSystemTruncation
    }

    func scanGitTracked(workingTree: String) async throws -> [String] { gitTracked }
    func scanGitIgnored(workingTree: String) async throws -> InspectIgnoredEntries { gitIgnored }
    func scanFileSystem(root: URL) async throws -> InspectScanResult {
        InspectScanResult(paths: gitTracked, truncation: fileSystemTruncation)
    }
    func scanImmediateChildren(absolutePath: String) async throws -> [InspectChildEntry] {
        immediateChildren[absolutePath] ?? []
    }
}

/// Scanner variant that records how many times each scan entry point is called
/// — used to verify lazy-load caching (don't re-fetch on every toggle), refresh
/// coalescing, and that a refused root scans nothing at all.
private final class CountingScanner: InspectFileScanning, @unchecked Sendable {
    private struct Counts {
        var immediateChildren = 0
        var treeScans = 0
    }
    private let gitTracked: [String]
    private let gitIgnored: InspectIgnoredEntries
    private let immediateChildren: [String: [InspectChildEntry]]
    private let counts = OSAllocatedUnfairLock<Counts>(initialState: Counts())

    var immediateChildrenCallCount: Int { counts.withLock { $0.immediateChildren } }
    /// `scanGitTracked` + `scanFileSystem` calls — i.e. how many full tree
    /// scans the view model kicked off.
    var treeScanCallCount: Int { counts.withLock { $0.treeScans } }

    init(
        gitTracked: [String],
        gitIgnored: InspectIgnoredEntries = .empty,
        immediateChildren: [String: [InspectChildEntry]] = [:]
    ) {
        self.gitTracked = gitTracked
        self.gitIgnored = gitIgnored
        self.immediateChildren = immediateChildren
    }

    func scanGitTracked(workingTree: String) async throws -> [String] {
        counts.withLock { $0.treeScans += 1 }
        return gitTracked
    }
    func scanGitIgnored(workingTree: String) async throws -> InspectIgnoredEntries { gitIgnored }
    func scanFileSystem(root: URL) async throws -> InspectScanResult {
        counts.withLock { $0.treeScans += 1 }
        return .complete(gitTracked)
    }
    func scanImmediateChildren(absolutePath: String) async throws -> [InspectChildEntry] {
        counts.withLock { $0.immediateChildren += 1 }
        return immediateChildren[absolutePath] ?? []
    }
}

private final class BlockingScanner: InspectFileScanning, Sendable {
    private struct State {
        var isRunning = false
        var cancelObserved = false
    }
    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    var isRunning: Bool { state.withLock { $0.isRunning } }
    var cancelObserved: Bool { state.withLock { $0.cancelObserved } }

    func scanGitTracked(workingTree: String) async throws -> [String] {
        state.withLock { $0.isRunning = true }
        // Loop until cancellation. Yield so the runtime can deliver cancel.
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
        state.withLock { $0.cancelObserved = true }
        try Task.checkCancellation()
        return []
    }

    func scanFileSystem(root: URL) async throws -> InspectScanResult {
        .complete(try await scanGitTracked(workingTree: root.path))
    }
}

/// Counting scanner whose tree scans park until `release()` — lets a test hold
/// a scan in flight, fire refreshes at it, and then watch what lands.
private final class GatedScanner: InspectFileScanning, Sendable {
    private struct State {
        var treeScans = 0
        var isRunning = false
        var isReleased = false
    }
    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let paths: [String]

    init(paths: [String]) { self.paths = paths }

    var treeScanCallCount: Int { state.withLock { $0.treeScans } }
    var isRunning: Bool { state.withLock { $0.isRunning } }
    func release() { state.withLock { $0.isReleased = true } }

    func scanGitTracked(workingTree: String) async throws -> [String] {
        state.withLock { $0.treeScans += 1; $0.isRunning = true }
        while !(state.withLock { $0.isReleased }) {
            try Task.checkCancellation()
            try? await Task.sleep(for: .milliseconds(5))
        }
        state.withLock { $0.isRunning = false }
        return paths
    }

    func scanFileSystem(root: URL) async throws -> InspectScanResult {
        .complete(try await scanGitTracked(workingTree: root.path))
    }
}

// MARK: - Test affordances on the view-model

@MainActor
extension InspectFileTreeViewModel {
    /// Test seam: `setRoot` with a substituted scanner. Used by tests that
    /// need to start a second scan with different scanner behavior than the
    /// one passed to `init`.
    func setRootForTest(_ url: URL?, scanner: InspectFileScanning) {
        self.replaceScanner(scanner)
        self.setRoot(url)
    }

    func visibleRowsContaining(relativePath: String) -> FileTreeNode? {
        visibleRows.first(where: { $0.relativePath == relativePath })
    }

    func allNodesContaining(relativePath: String) -> FileTreeNode? {
        allNodesForTest.first(where: { $0.relativePath == relativePath })
    }
}

private extension String {
    func replacingLastPathComponent() -> String {
        (self as NSString).deletingLastPathComponent
    }
}

