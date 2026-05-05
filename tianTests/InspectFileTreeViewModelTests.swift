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

    // MARK: - FR-21 — directory rows have no badge

    @Test func directoryRowsHaveNoBadge() async {
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

        // The directory `auth` does not appear in statusByRelativePath even
        // though its descendant is modified.
        #expect(vm.statusByRelativePath["auth"] == nil)
        #expect(vm.statusByRelativePath["auth/"] == nil)
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
}

// MARK: - Test scanners

private final class FixedScanner: InspectFileScanning, @unchecked Sendable {
    private let gitTracked: [String]
    init(gitTracked: [String]) { self.gitTracked = gitTracked }

    func scanGitTracked(workingTree: String) async throws -> [String] { gitTracked }
    func scanFileSystem(root: URL) async throws -> [String] { gitTracked }
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

    func scanFileSystem(root: URL) async throws -> [String] {
        try await scanGitTracked(workingTree: root.path)
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

@MainActor
private func pollUntil(
    timeout: Duration,
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    }
}
