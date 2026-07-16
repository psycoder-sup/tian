import Foundation
import Testing
@testable import tian

@MainActor
struct GitMonitorTests {

    // MARK: - Shared Watcher & Status

    /// Two subscribers to the SAME repoID share ONE refs watcher and one
    /// repo-level status entry.
    @Test func twoSubscribersToSameRepoShareOneWatcherAndStatus() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let monitor = GitMonitor()
        let location = try await detectLocation(for: repo)
        let repoID = GitRepoID(path: location.commonDir)

        let t1 = monitor.subscribe(location: location, worktreeRoot: location.workingTree)
        let t2 = monitor.subscribe(location: location, worktreeRoot: location.workingTree)

        // The repo-level and per-root statuses resolve via independent async
        // refreshes (branch vs. working-tree), and either can win the race for
        // the shared `gitLocal` lane — so `status(forRepo:) != nil` alone can
        // already be true from the working-tree refresh landing first, with
        // branchName still nil. Poll on the actual condition asserted below
        // (branchName resolved), not just object presence. Generous timeout:
        // under the full parallel suite, GitMonitor's bounded lanes
        // (gitLocal=4, ghNetwork=2) can be starved by hundreds of concurrent
        // tests, so a tight deadline flakes even though the wait itself is
        // correct.
        try await pollUntil(timeout: 10.0) {
            monitor.status(forRepo: repoID)?.branchName?.isEmpty == false
                && monitor.status(forWorktreeRoot: location.workingTree) != nil
        }

        // One always-on refs watcher, shared by both subscribers.
        #expect(monitor.activeWatcherCount == 1)
        #expect(monitor.repoStatuses.count == 1)
        #expect(monitor.status(forWorktreeRoot: location.workingTree) != nil)
        let status = monitor.status(forRepo: repoID)
        #expect(status?.branchName?.isEmpty == false)

        monitor.unsubscribe(t1)
        monitor.unsubscribe(t2)
    }

    // MARK: - Refcount / GC Lifecycle

    /// Unsubscribing ONE of two subscribers keeps the watcher + status alive;
    /// unsubscribing the LAST tears the watcher down and GCs the status.
    @Test func lastUnsubscribeTearsDownWatcherAndGCsStatus() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let monitor = GitMonitor()
        let location = try await detectLocation(for: repo)
        let repoID = GitRepoID(path: location.commonDir)

        let t1 = monitor.subscribe(location: location, worktreeRoot: location.workingTree)
        let t2 = monitor.subscribe(location: location, worktreeRoot: location.workingTree)

        try await pollUntil(timeout: 5.0) { monitor.status(forRepo: repoID) != nil }
        #expect(monitor.activeWatcherCount == 1)

        // One unsubscribe: watcher + status survive.
        monitor.unsubscribe(t1)
        #expect(monitor.activeWatcherCount == 1)
        #expect(monitor.status(forRepo: repoID) != nil)

        // Last unsubscribe: watcher torn down, status GC'd.
        monitor.unsubscribe(t2)
        #expect(monitor.activeWatcherCount == 0)
        #expect(monitor.activeWorkingTreeWatcherCount == 0)
        #expect(monitor.status(forRepo: repoID) == nil)
        #expect(monitor.status(forWorktreeRoot: location.workingTree) == nil)
        #expect(monitor.repoStatuses.isEmpty)
        #expect(monitor.statusByWorktreeRoot.isEmpty)
    }

    /// A repeated subscribe/unsubscribe cycle for the same repo re-creates the
    /// watcher cleanly (refcount returns to zero and back).
    @Test func resubscribeAfterFullTeardownRecreatesWatcher() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let monitor = GitMonitor()
        let location = try await detectLocation(for: repo)
        let repoID = GitRepoID(path: location.commonDir)

        let first = monitor.subscribe(location: location, worktreeRoot: location.workingTree)
        try await pollUntil(timeout: 5.0) { monitor.status(forRepo: repoID) != nil }
        #expect(monitor.activeWatcherCount == 1)
        monitor.unsubscribe(first)
        #expect(monitor.activeWatcherCount == 0)

        let second = monitor.subscribe(location: location, worktreeRoot: location.workingTree)
        try await pollUntil(timeout: 5.0) { monitor.status(forRepo: repoID) != nil }
        #expect(monitor.activeWatcherCount == 1)
        monitor.unsubscribe(second)
        #expect(monitor.activeWatcherCount == 0)
    }

    // MARK: - Split Watchers & Gate (ADR changes B + C)

    /// The always-on refs watcher exists whenever a repo is subscribed, even
    /// after the working-tree gate closes.
    @Test func refsWatcherPresentWhileSubscribedEvenWhenGateClosed() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let monitor = GitMonitor()
        let location = try await detectLocation(for: repo)
        let repoID = GitRepoID(path: location.commonDir)

        let token = monitor.subscribe(location: location, worktreeRoot: location.workingTree)
        try await pollUntil(timeout: 5.0) { monitor.status(forRepo: repoID) != nil }

        // Fresh subscriber defaults to visible → gate open, both watchers live.
        #expect(monitor.activeWatcherCount == 1)
        #expect(monitor.activeWorkingTreeWatcherCount == 1)

        // Going non-visible + non-busy closes the working-tree gate, but the
        // cheap refs watcher stays on to keep branch/PR live.
        monitor.setSubscriberActivity(token, visible: false, busy: false)
        #expect(monitor.activeWatcherCount == 1)
        #expect(monitor.activeWorkingTreeWatcherCount == 0)

        monitor.unsubscribe(token)
    }

    /// `setSubscriberActivity` opens/closes the working-tree gate with OR
    /// semantics across multiple subscribers, and busy alone keeps it open.
    @Test func gateIsOrOverSubscribersVisibleOrBusy() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let monitor = GitMonitor()
        let location = try await detectLocation(for: repo)
        let repoID = GitRepoID(path: location.commonDir)

        let t1 = monitor.subscribe(location: location, worktreeRoot: location.workingTree)
        let t2 = monitor.subscribe(location: location, worktreeRoot: location.workingTree)
        try await pollUntil(timeout: 5.0) { monitor.status(forRepo: repoID) != nil }

        // Both default-visible → gate open.
        #expect(monitor.activeWorkingTreeWatcherCount == 1)

        // One goes idle: the other visible subscriber keeps the gate open.
        monitor.setSubscriberActivity(t1, visible: false, busy: false)
        #expect(monitor.activeWorkingTreeWatcherCount == 1)

        // Both idle: gate closes.
        monitor.setSubscriberActivity(t2, visible: false, busy: false)
        #expect(monitor.activeWorkingTreeWatcherCount == 0)

        // Busy (not visible) re-opens the gate — a background session actively
        // writing files keeps its diff badge live.
        monitor.setSubscriberActivity(t1, visible: false, busy: true)
        #expect(monitor.activeWorkingTreeWatcherCount == 1)

        monitor.unsubscribe(t1)
        monitor.unsubscribe(t2)
    }

    /// Re-opening the gate does one eager working-tree catch-up refresh — a
    /// change made while the gate was closed (no working-tree watcher running)
    /// shows up right after the gate re-opens.
    @Test func gateOpenTriggersEagerWorkingTreeRefresh() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let monitor = GitMonitor()
        let location = try await detectLocation(for: repo)
        let root = location.workingTree

        let token = monitor.subscribe(location: location, worktreeRoot: root)
        try await pollUntil(timeout: 5.0) { monitor.status(forWorktreeRoot: root) != nil }

        // Close the gate: no working-tree watcher can see subsequent edits.
        monitor.setSubscriberActivity(token, visible: false, busy: false)
        #expect(monitor.activeWorkingTreeWatcherCount == 0)

        // Introduce a working-tree change while the gate is closed.
        let newFile = (repo as NSString).appendingPathComponent("scratch.txt")
        try "hello".write(toFile: newFile, atomically: true, encoding: .utf8)

        // Re-open the gate → the eager catch-up refresh must pick up the change
        // (the FSEvents watcher was stopped, so only the catch-up can).
        monitor.setSubscriberActivity(token, visible: true, busy: false)
        #expect(monitor.activeWorkingTreeWatcherCount == 1)
        try await pollUntil(timeout: 5.0) {
            monitor.status(forWorktreeRoot: root)?.diffSummary.isEmpty == false
        }

        monitor.unsubscribe(token)
    }

    /// A working-tree diff refresh must NOT trigger a PR fetch (PR is driven off
    /// refs eviction / poll / gate-open only).
    @Test func workingTreeRefreshDoesNotTriggerPRFetch() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let monitor = GitMonitor()
        let location = try await detectLocation(for: repo)
        let repoID = GitRepoID(path: location.commonDir)

        let token = monitor.subscribe(location: location, worktreeRoot: location.workingTree)
        try await pollUntil(timeout: 5.0) { monitor.status(forRepo: repoID) != nil }
        // Let any gate-open PR fetch settle so the baseline is stable.
        try await Task.sleep(for: .milliseconds(400))

        let before = monitor.prFetchLaunchCount
        monitor.refreshWorkingTree(repoID: repoID)
        try await Task.sleep(for: .milliseconds(400))
        #expect(monitor.prFetchLaunchCount == before)

        monitor.unsubscribe(token)
    }

    // MARK: - Refs Batch → branchGraphDirty
    //
    // Migrated from the deleted `SessionGitContextBranchDirtyTests`: that
    // behaviour now lives on `GitMonitor.processRefsFSEventBatch(...)` +
    // `branchGraphDirty` / `clearBranchGraphDirty`. Driven directly (no
    // subscribe needed) with a synthetic repoID — a refs/heads path is
    // branch-graph-only, so it never touches the PR-eviction/fetch path.

    /// A refs FSEvents batch under `refs/heads/*` sets `branchGraphDirty` for
    /// the repo.
    @Test func refsHeadsBatchSetsBranchGraphDirty() {
        let monitor = GitMonitor()
        let commonDir = "/tmp/testrepo/.git"
        let repoID = GitRepoID(path: commonDir)
        let paths = [commonDir + "/refs/heads/feature"]

        monitor.processRefsFSEventBatch(repoID: repoID, paths: paths, canonicalCommonDir: commonDir)

        #expect(monitor.branchGraphDirty.contains(repoID))
    }

    /// A working-tree-only batch does NOT set `branchGraphDirty`.
    @Test func workingTreeBatchDoesNotSetBranchGraphDirty() {
        let monitor = GitMonitor()
        let commonDir = "/tmp/testrepo/.git"
        let repoID = GitRepoID(path: commonDir)
        let paths = ["/tmp/testrepo/src/main.swift", "/tmp/testrepo/README.md"]

        monitor.processRefsFSEventBatch(repoID: repoID, paths: paths, canonicalCommonDir: commonDir)

        #expect(!monitor.branchGraphDirty.contains(repoID))
    }

    /// `clearBranchGraphDirty(repoID:)` removes the repo from the set.
    @Test func clearBranchGraphDirtyRemovesEntry() {
        let monitor = GitMonitor()
        let commonDir = "/tmp/testrepo/.git"
        let repoID = GitRepoID(path: commonDir)
        let paths = [commonDir + "/refs/heads/main"]

        // Pre-populate via a branch-graph-affecting batch.
        monitor.processRefsFSEventBatch(repoID: repoID, paths: paths, canonicalCommonDir: commonDir)
        #expect(monitor.branchGraphDirty.contains(repoID))

        monitor.clearBranchGraphDirty(repoID: repoID)

        #expect(!monitor.branchGraphDirty.contains(repoID))
    }

    // MARK: - On-Demand PR Refresh

    /// `refreshPR(repoID:)` forces a fresh PR fetch even when the branch already
    /// has a cached result and active network-backoff: it evicts the PR cache,
    /// clears the backoff, and launches a fetch bypassing backoff. Asserted via
    /// the `prFetchLaunchCount` seam — one `refreshPR` call launches exactly one
    /// additional fetch. (Both guards it defeats — the cache `.hit` and the
    /// backoff — would otherwise make `maybeFetchPR` skip.)
    @Test func refreshPRForcesRefetchBypassingCacheAndBackoff() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let monitor = GitMonitor()
        let location = try await detectLocation(for: repo)
        let repoID = GitRepoID(path: location.commonDir)

        let token = monitor.subscribe(location: location, worktreeRoot: location.workingTree)
        // The PR cache key is the branch name, so wait until it resolves. The
        // gate-open fetch (nil PR on a remote-less temp repo) seeds cache + backoff.
        try await pollUntil(timeout: 5.0) {
            monitor.status(forRepo: repoID)?.branchName?.isEmpty == false
        }
        // Let the gate-open fetch settle so the seed (cached nil PR + recorded
        // backoff) is genuinely in place; `refreshPR`'s evict also clears any
        // lingering pending, so the launch count is deterministic regardless.
        try await Task.sleep(for: .milliseconds(400))

        let before = monitor.prFetchLaunchCount
        monitor.refreshPR(repoID: repoID)
        #expect(monitor.prFetchLaunchCount == before + 1)

        monitor.unsubscribe(token)
    }

    // MARK: - Centralized Detection Cache

    /// `detect` caches: a second call for the same directory within the TTL does
    /// not re-run detection (asserted via an injected counting detector).
    @Test func detectCachesWithinTTL() async {
        let counter = CallCounter()
        let location = RepoLocation(
            gitDir: "/repo/.git",
            commonDir: "/repo/.git",
            workingTree: "/repo",
            isWorktree: false
        )
        let monitor = GitMonitor(detector: { _ in
            await counter.increment()
            return location
        })

        let first = await monitor.detect(directory: "/repo")
        let second = await monitor.detect(directory: "/repo")

        #expect(first == location)
        #expect(second == location)
        // Only the first call shells out; the second is a cache hit.
        #expect(await counter.value == 1)
    }

    /// `detect` caches negative results too — a not-a-repo directory isn't
    /// re-detected on the immediately following call.
    @Test func detectCachesNegativeResult() async {
        let counter = CallCounter()
        let monitor = GitMonitor(detector: { _ in
            await counter.increment()
            return nil
        })

        let first = await monitor.detect(directory: "/not/a/repo")
        let second = await monitor.detect(directory: "/not/a/repo")

        #expect(first == nil)
        #expect(second == nil)
        #expect(await counter.value == 1)
    }

    // MARK: - Global Concurrency Lanes

    /// The monitor configures its two lanes at the ADR-mandated caps.
    @Test func configuresGlobalConcurrencyLaneLimits() {
        #expect(GitMonitor.gitLocalLimit == 4)
        #expect(GitMonitor.ghNetworkLimit == 2)
    }

    /// `AsyncSemaphore` — the primitive both lanes are built from — caps the
    /// number of concurrent holders at its limit under contention.
    @Test func asyncSemaphoreCapsParallelismAtLimit() async {
        let limit = 2
        let semaphore = AsyncSemaphore(limit: limit)
        let tracker = ConcurrencyTracker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    await semaphore.acquire()
                    await tracker.enter()
                    try? await Task.sleep(for: .milliseconds(15))
                    await tracker.leave()
                    await semaphore.release()
                }
            }
        }

        let peak = await tracker.maxConcurrent
        #expect(peak >= 1)
        #expect(peak <= limit)
    }

    // MARK: - Helpers

    /// Counts detector invocations across actor hops.
    private actor CallCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    /// Tracks the peak number of concurrently-held slots.
    private actor ConcurrencyTracker {
        private var current = 0
        private(set) var maxConcurrent = 0
        func enter() {
            current += 1
            maxConcurrent = max(maxConcurrent, current)
        }
        func leave() {
            current -= 1
        }
    }

    private func detectLocation(for directory: String) async throws -> RepoLocation {
        guard let location = await GitStatusService.detectRepo(directory: directory) else {
            throw StringError("failed to detect git repo at \(directory)")
        }
        return location
    }

    private func pollUntil(timeout: Double, condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for condition after \(timeout)s")
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir,
                                                 withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)

        let readmePath = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readmePath, atomically: true, encoding: .utf8)

        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)

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
