import Foundation
import Observation
import OSLog

/// App-global, repo-keyed git monitor (ADR 0005).
///
/// One shared owner of all git watchers, the single `PRStatusCache`, the single
/// `DetectionCache`, two global refresh schedulers, and two global concurrency
/// lanes (a git-local shell-out lane + a separate `gh`-network lane). Sessions
/// SUBSCRIBE by `(repoID, worktreeRoot)` with reference counting: a repo's
/// watchers + cached status are created on the first subscriber and torn down —
/// tasks cancelled, status garbage-collected — at refcount zero.
///
/// This wave makes the skeleton real (ADR changes B + the mechanism for C):
///
/// - **Split signal (B).** Each repo gets TWO watchers instead of one whole-tree
///   watcher. A cheap, ALWAYS-ON **refs** watcher (`HEAD`/`refs`/`packed-refs`)
///   drives branch/refs refresh, `branchGraphDirty`, and PR-cache eviction. An
///   expensive **working-tree** watcher, GATED behind visibility/busy, drives
///   ONLY the diff/dirty summary. PR state is driven off refs eviction + a slow
///   poll + on-gate-open — never off working-tree churn — with network backoff.
/// - **Gate mechanism (C).** The working-tree watcher runs only while at least
///   one subscriber is VISIBLE or BUSY. Subscribers report activity via
///   `setSubscriberActivity`; the gate is the OR over a repo's subscribers.
///   Wave 3 feeds the real visible/busy signals; until it reports, a fresh
///   subscriber is treated as visible so its diff is never frozen.
/// - **Centralized detection.** `detect(directory:)` runs `detectRepo` behind
///   the git-local lane and caches the result in `DetectionCache`.
///
/// The read-shape (`repoStatuses` / `statusByWorktreeRoot`) matches
/// `SessionGitContext` so the Wave-3 adapter barely changes.
@MainActor @Observable
final class GitMonitor {

    /// The single app-global instance. Wave 3's `SessionGitContext` reaches the
    /// monitor through this without an app-init change.
    static let shared = GitMonitor()

    /// Global cap on concurrent git status/branch shell-out pipelines.
    static let gitLocalLimit = 4
    /// Global cap on concurrent `gh pr view` network fetches.
    static let ghNetworkLimit = 2

    /// Slow PR-status poll cadence. PR state is deliberately kept off the
    /// working-tree hot path; a background repo's badge stays live at this
    /// coarse cadence (plus refs-eviction + gate-open) instead of on every save.
    static let prPollInterval: Duration = .seconds(300)

    /// Remote git-context refresh cadence. FSEvents can't watch another host, so
    /// remote repos poll: every tick reschedules branch + working-tree, every
    /// `remotePollHeavyEvery`-th tick raises the signals a local refs batch would
    /// (PR re-fetch, branch-graph re-render). Mirrors `SessionGitContext`.
    static let remotePollInterval: Duration = .seconds(5)
    static let remotePollHeavyEvery = 6

    /// PR-fetch network backoff bounds. After a failed/empty fetch for a
    /// (repoID, branch), the next poll/gate-open trigger waits at least
    /// `prBackoffBase`, doubling up to `prBackoffMax`. A push/fetch eviction and
    /// any successful fetch reset it.
    private static let prBackoffBase: TimeInterval = 30
    private static let prBackoffMax: TimeInterval = 600

    // MARK: - Observable Read State

    /// Full git status per `GitRepoID`. Drives sidebar re-renders. Sibling
    /// worktrees collapse onto one entry here (they share a common-dir keyed
    /// `GitRepoID`); use `statusByWorktreeRoot` to distinguish them.
    private(set) var repoStatuses: [GitRepoID: GitRepoStatus] = [:]

    /// Full git status per worktree root (`git rev-parse --show-toplevel`). Lets
    /// the sidebar render each tab's own branch AND change/PR badges even when
    /// several tabs share one `GitRepoID`.
    private(set) var statusByWorktreeRoot: [String: GitRepoStatus] = [:]

    /// Set of repos whose branch graph has been invalidated by a refs FSEvents
    /// batch since the last successful Branch-tab fetch. The Branch view-model
    /// reads + clears this. Working-tree-only events do NOT add to this set.
    private(set) var branchGraphDirty: Set<GitRepoID> = []

    // MARK: - Read API (for the future sidebar adapter)

    /// The full git status for a worktree root, or nil when the root isn't
    /// subscribed / hasn't resolved yet.
    func status(forWorktreeRoot worktreeRoot: String) -> GitRepoStatus? {
        statusByWorktreeRoot[worktreeRoot]
    }

    /// The full git status for a `GitRepoID`, or nil when the repo isn't
    /// subscribed / hasn't resolved yet.
    func status(forRepo repoID: GitRepoID) -> GitRepoStatus? {
        repoStatuses[repoID]
    }

    /// Removes a repo from the `branchGraphDirty` set. Called by the Branch
    /// view-model after a successful branch-graph refetch.
    func clearBranchGraphDirty(repoID: GitRepoID) {
        branchGraphDirty.remove(repoID)
    }

    // MARK: - Subscription State

    /// Opaque handle identifying one `(repoID, worktreeRoot, subscriber)`
    /// subscription. Returned by `subscribe`, passed back to `unsubscribe` and
    /// `setSubscriberActivity`.
    struct SubscriptionToken: Hashable, Sendable {
        fileprivate let id: UUID
    }

    /// The repo + worktree root a token resolves to. Kept so `unsubscribe` can
    /// decrement the right refcounts without the caller re-supplying them.
    private struct Subscription {
        let repoID: GitRepoID
        let worktreeRoot: String
    }

    /// A subscriber's current visibility/busy signal — the input to the
    /// working-tree gate. Defaults to visible so a fresh subscriber's diff is
    /// never frozen before Wave 3 reports the real signal.
    private struct SubscriberActivity {
        var visible: Bool
        var busy: Bool
        static let `default` = SubscriberActivity(visible: true, busy: false)
    }

    /// Identifies one status entry a refresh writes to. `.repo` is the
    /// `GitRepoID`-keyed status; `.root` is a per-worktree-root status.
    private enum StatusTarget: Hashable, Sendable {
        case repo(GitRepoID)
        case root(String, GitRepoID)
    }

    /// Live subscriptions keyed by token.
    private var subscriptions: [SubscriptionToken: Subscription] = [:]

    /// Per-subscriber activity (visible/busy). Drives the working-tree gate.
    private var subscriberActivity: [SubscriptionToken: SubscriberActivity] = [:]

    /// Reference count per repo. A repo's watchers/status are created when this
    /// goes 0→1 and torn down when it returns to 0.
    private var repoRefCounts: [GitRepoID: Int] = [:]

    /// Directory used for the repo-level refresh (the first subscriber's working
    /// tree). Removed on teardown; watcher/poller callbacks read this to decide
    /// whether the repo is still live.
    private var repoDirectories: [GitRepoID: String] = [:]

    /// The `RepoLocation` of the first subscriber, kept so the working-tree
    /// watcher can be (re)built on gate-open without the caller re-supplying it.
    private var repoLocations: [GitRepoID: RepoLocation] = [:]

    /// `commonDir` canonicalized once at first subscribe, so the refs watcher's
    /// `pathsAffect*` classification never calls `realpath(3)` on the callback.
    private var canonicalCommonDirByRepo: [GitRepoID: String] = [:]

    /// Set of subscribed worktree roots per repo, so a refresh can re-resolve
    /// each root's independent branch/diff/PR status.
    private var worktreeRootsByRepo: [GitRepoID: Set<String>] = [:]

    // MARK: - Watchers, Pollers & Tasks

    /// Always-on refs watcher per repo (HEAD/refs/packed-refs). Drives the cheap
    /// branch/refs refresh, `branchGraphDirty`, and PR-cache eviction.
    private var refsWatchers: [GitRepoID: GitRepoWatcher] = [:]

    /// Gated working-tree watcher per repo. Present only while the repo's gate
    /// is open (≥1 visible/busy subscriber). Drives ONLY the diff refresh.
    private var workingTreeWatchers: [GitRepoID: GitRepoWatcher] = [:]

    /// Slow PR-status poller per repo (300s). One of the three PR-fetch drivers.
    private var prPollers: [GitRepoID: PollingRefresher] = [:]

    /// Interval poller standing in for FSEvents on remote repos (FSEvents can't
    /// cross hosts). Mutually exclusive with `refsWatchers`/`workingTreeWatchers`
    /// per repo — the poll drives both refs and working-tree refreshes.
    private var remotePollers: [GitRepoID: PollingRefresher] = [:]
    /// Per-repo tick counter so the remote poller raises the heavier
    /// FSEvents-only signals only every Nth tick.
    private var remotePollTicks: [GitRepoID: Int] = [:]

    /// In-flight branch/refs refresh tasks per status target, cancelled on
    /// re-entry.
    private var inFlightBranchTasks: [StatusTarget: Task<Void, Never>] = [:]

    /// In-flight working-tree (diff) refresh tasks per status target, cancelled
    /// on re-entry.
    private var inFlightWorkingTreeTasks: [StatusTarget: Task<Void, Never>] = [:]

    /// In-flight PR fetch tasks per repo, keyed inner by a per-call UUID so a
    /// completing task removes only its own entry. The outer key lets teardown
    /// cancel every fetch for a repo in one pass.
    private var prFetchTasks: [GitRepoID: [UUID: Task<Void, Never>]] = [:]

    /// Per-(repoID, branch) PR-fetch network backoff. Present only while a
    /// branch is being backed off after a failed/empty fetch.
    private struct PRBackoffKey: Hashable {
        let repoPath: String
        let branch: String
    }
    private var prBackoff: [PRBackoffKey: (nextAllowed: Date, delay: TimeInterval)] = [:]

    // MARK: - Shared Owned Resources

    /// The single shared PR status cache (300-second TTL). Owned here so a repo
    /// with several subscribing sessions polls `gh` once, not once per session.
    private let prCache = PRStatusCache()

    /// The single shared repo-detection cache. `detect(directory:)` reads/writes
    /// it so an OSC 7 cwd storm doesn't re-shell `git rev-parse` per event.
    private let detectionCache = DetectionCache()

    /// Repo detection seam. Defaults to `GitStatusService.detectRepo`; injectable
    /// so tests can assert `detect` caches without shelling out.
    @ObservationIgnored
    private let detector: @Sendable (String) async -> RepoLocation?

    /// Global lane capping concurrent git status/branch shell-outs.
    let gitLocal = AsyncSemaphore(limit: GitMonitor.gitLocalLimit)

    /// Global lane capping concurrent `gh pr view` network fetches.
    let ghNetwork = AsyncSemaphore(limit: GitMonitor.ghNetworkLimit)

    /// Trailing-debounce + global concurrency cap coalescing refs FSEvents-driven
    /// branch refreshes. `@ObservationIgnored` because the scheduler is internal
    /// plumbing, not observable state — and `lazy` is incompatible with the
    /// accessor the `@Observable` macro would otherwise emit.
    @ObservationIgnored
    private lazy var refsScheduler = RefreshScheduler<GitRepoID>(
        debounce: .milliseconds(250),
        maxConcurrent: 4
    ) { [weak self] repoID in
        await MainActor.run { [weak self] in
            guard let self, self.repoRefCounts[repoID] != nil else { return }
            self.refreshBranchAndRefs(repoID: repoID)
        }
    }

    /// Trailing-debounce + global concurrency cap coalescing working-tree
    /// FSEvents-driven diff refreshes. Skips when the gate is closed (no
    /// working-tree watcher) so a late-firing debounce can't resurrect the diff.
    @ObservationIgnored
    private lazy var workingTreeScheduler = RefreshScheduler<GitRepoID>(
        debounce: .milliseconds(250),
        maxConcurrent: 4
    ) { [weak self] repoID in
        await MainActor.run { [weak self] in
            guard let self, self.repoRefCounts[repoID] != nil else { return }
            guard self.workingTreeWatchers[repoID] != nil else { return }
            self.refreshWorkingTree(repoID: repoID)
        }
    }

    // MARK: - Test Seams

    /// Number of repos being actively watched (always-on refs watchers + remote
    /// pollers). Exposed for testing.
    var activeWatcherCount: Int { refsWatchers.count + remotePollers.count }

    /// Number of active (gate-open) working-tree watchers. Exposed for testing
    /// the gate.
    var activeWorkingTreeWatcherCount: Int { workingTreeWatchers.count }

    /// Monotonic count of PR fetches launched. Exposed for testing that the
    /// working-tree refresh never triggers a PR fetch.
    @ObservationIgnored
    private(set) var prFetchLaunchCount: Int = 0

    // MARK: - Init

    /// - Parameter detector: repo-detection seam, defaulting to
    ///   `GitStatusService.detectRepo`. Tests inject a counting stub.
    init(
        detector: @escaping @Sendable (String) async -> RepoLocation? = {
            await GitStatusService.detectRepo(directory: $0)
        }
    ) {
        self.detector = detector
    }

    // MARK: - Detection

    /// Detects (and caches) the git repo for a directory. On a cache hit returns
    /// immediately; on a miss runs `detectRepo` behind the global `gitLocal` lane
    /// and stores the result (positive or negative) in `DetectionCache`. The seam
    /// Wave 3's `SessionGitContext` calls instead of `GitStatusService.detectRepo`
    /// directly.
    func detect(directory: String) async -> RepoLocation? {
        switch detectionCache.get(directory: directory) {
        case .hit(let location):
            return location
        case .miss:
            await gitLocal.acquire()
            let location = await detector(directory)
            await gitLocal.release()
            detectionCache.set(directory: directory, location: location)
            return location
        }
    }

    // MARK: - Subscription

    /// Subscribes to git status for `(location, worktreeRoot)`, returning a token
    /// to release it. On the FIRST subscriber for a repo (keyed on
    /// `location.commonDir`) this starts the always-on refs watching + slow PR
    /// poll (or a remote poller) and opens the working-tree gate if the fresh,
    /// default-visible subscriber warrants it. Further subscribers share the
    /// watchers and cached status; the specific worktree root is always refreshed
    /// so sibling worktrees get independent badges.
    func subscribe(location: RepoLocation, worktreeRoot: String) -> SubscriptionToken {
        let repoID = GitRepoID(path: location.commonDir)
        let token = SubscriptionToken(id: UUID())
        subscriptions[token] = Subscription(repoID: repoID, worktreeRoot: worktreeRoot)
        subscriberActivity[token] = .default

        worktreeRootsByRepo[repoID, default: []].insert(worktreeRoot)
        if repoDirectories[repoID] == nil {
            repoDirectories[repoID] = location.workingTree
        }

        let previousCount = repoRefCounts[repoID, default: 0]
        repoRefCounts[repoID] = previousCount + 1

        if previousCount == 0 {
            repoLocations[repoID] = location
            canonicalCommonDirByRepo[repoID] = GitRepoWatcher.canonicalizedPath(location.commonDir)
            startRepoWatching(repoID: repoID, location: location)
            // Eager branch (all targets) so a freshly-subscribed tab renders
            // without waiting for a debounce.
            refreshBranchAndRefs(repoID: repoID)
            if isRemote(repoID) {
                // Remote repos have no FSEvents gate; poll drives the diff, so
                // do the eager catch-up here.
                refreshWorkingTree(repoID: repoID)
            } else {
                // Local: opening the gate (default-visible) does the eager
                // working-tree refresh + gate-open PR fetch.
                updateGate(repoID: repoID)
            }
            Log.git.debug("GitMonitor subscribed first for repo: \(repoID.path)")
        } else {
            // Subsequent subscriber, possibly adding a NEW worktree root.
            refreshBranch(target: .root(worktreeRoot, repoID))
            if isRemote(repoID) || workingTreeWatchers[repoID] != nil {
                refreshWorkingTreeTarget(target: .root(worktreeRoot, repoID))
            }
            // A fresh default-visible subscriber may re-open a gate that all
            // prior subscribers had closed.
            updateGate(repoID: repoID)
        }
        return token
    }

    /// Releases a subscription. Decrements the repo's refcount; on the LAST
    /// unsubscribe for a repo the watchers are stopped, its in-flight tasks are
    /// cancelled, and its cached status is garbage-collected. A worktree root's
    /// per-root status is dropped once no remaining subscription references it.
    func unsubscribe(_ token: SubscriptionToken) {
        guard let sub = subscriptions.removeValue(forKey: token) else { return }
        subscriberActivity.removeValue(forKey: token)
        let repoID = sub.repoID

        // GC the per-worktree-root status if no other subscription needs it.
        let rootStillReferenced = subscriptions.values.contains { $0.worktreeRoot == sub.worktreeRoot }
        if !rootStillReferenced {
            worktreeRootsByRepo[repoID]?.remove(sub.worktreeRoot)
            if worktreeRootsByRepo[repoID]?.isEmpty == true {
                worktreeRootsByRepo.removeValue(forKey: repoID)
            }
            inFlightBranchTasks.removeValue(forKey: .root(sub.worktreeRoot, repoID))?.cancel()
            inFlightWorkingTreeTasks.removeValue(forKey: .root(sub.worktreeRoot, repoID))?.cancel()
            statusByWorktreeRoot.removeValue(forKey: sub.worktreeRoot)
        }

        let newCount = (repoRefCounts[repoID] ?? 1) - 1
        if newCount <= 0 {
            repoRefCounts.removeValue(forKey: repoID)
            tearDownRepo(repoID)
        } else {
            repoRefCounts[repoID] = newCount
            // A departed subscriber may have been the last visible/busy one.
            updateGate(repoID: repoID)
        }
    }

    /// Reports a subscriber's current visibility/busy signal. Recomputes the
    /// repo's working-tree gate (the OR over its subscribers' `visible || busy`)
    /// and opens/closes the working-tree watcher accordingly. Wave 3 feeds the
    /// real signals; until then every subscriber defaults to visible.
    func setSubscriberActivity(_ token: SubscriptionToken, visible: Bool, busy: Bool) {
        guard let sub = subscriptions[token] else { return }
        subscriberActivity[token] = SubscriberActivity(visible: visible, busy: busy)
        updateGate(repoID: sub.repoID)
    }

    /// Stops watching a repo and clears every trace of it (last-subscriber GC).
    private func tearDownRepo(_ repoID: GitRepoID) {
        for target in Array(inFlightBranchTasks.keys) where owningRepoID(target) == repoID {
            inFlightBranchTasks.removeValue(forKey: target)?.cancel()
        }
        for target in Array(inFlightWorkingTreeTasks.keys) where owningRepoID(target) == repoID {
            inFlightWorkingTreeTasks.removeValue(forKey: target)?.cancel()
        }
        if let inner = prFetchTasks.removeValue(forKey: repoID) {
            for task in inner.values { task.cancel() }
        }
        refsScheduler.cancel(key: repoID)
        workingTreeScheduler.cancel(key: repoID)
        stopRefsWatcher(repoID: repoID)
        stopWorkingTreeWatcher(repoID: repoID)
        stopPRPoller(repoID: repoID)
        stopRemotePoller(repoID: repoID)

        // Drop any per-root statuses still attributed to this repo.
        if let roots = worktreeRootsByRepo.removeValue(forKey: repoID) {
            for root in roots {
                inFlightBranchTasks.removeValue(forKey: .root(root, repoID))?.cancel()
                inFlightWorkingTreeTasks.removeValue(forKey: .root(root, repoID))?.cancel()
                statusByWorktreeRoot.removeValue(forKey: root)
            }
        }

        repoStatuses.removeValue(forKey: repoID)
        branchGraphDirty.remove(repoID)
        repoDirectories.removeValue(forKey: repoID)
        repoLocations.removeValue(forKey: repoID)
        canonicalCommonDirByRepo.removeValue(forKey: repoID)
        prBackoff = prBackoff.filter { $0.key.repoPath != repoID.path }
        prCache.evict(repoID: repoID)
        Log.git.debug("GitMonitor tore down repo: \(repoID.path)")
    }

    // MARK: - Status-Target Helpers

    /// Every status entry a repo currently owns: its `GitRepoID`-keyed status
    /// plus one per subscribed worktree root.
    private func targets(for repoID: GitRepoID) -> [StatusTarget] {
        var result: [StatusTarget] = [.repo(repoID)]
        for root in worktreeRootsByRepo[repoID] ?? [] {
            result.append(.root(root, repoID))
        }
        return result
    }

    private func owningRepoID(_ target: StatusTarget) -> GitRepoID {
        switch target {
        case .repo(let repoID): return repoID
        case .root(_, let repoID): return repoID
        }
    }

    /// The directory a refresh shells git in for this target.
    private func directory(for target: StatusTarget) -> String? {
        switch target {
        case .repo(let repoID): return repoDirectories[repoID]
        case .root(let root, _): return root
        }
    }

    /// True while the target is still subscribed (guards against a torn-down
    /// repo / GC'd root being resurrected by a late task).
    private func targetIsLive(_ target: StatusTarget) -> Bool {
        switch target {
        case .repo(let repoID): return repoRefCounts[repoID] != nil
        case .root(let root, let repoID): return worktreeRootsByRepo[repoID]?.contains(root) == true
        }
    }

    private func currentStatus(for target: StatusTarget) -> GitRepoStatus? {
        switch target {
        case .repo(let repoID): return repoStatuses[repoID]
        case .root(let root, _): return statusByWorktreeRoot[root]
        }
    }

    /// Writes a status entry, skipping the Observable write when nothing visible
    /// changed (equality ignores `lastUpdated`) — avoids sidebar re-renders on
    /// every FSEvents batch during noisy activity.
    private func writeStatus(_ status: GitRepoStatus, for target: StatusTarget) {
        switch target {
        case .repo(let repoID):
            if repoStatuses[repoID] != status { repoStatuses[repoID] = status }
        case .root(let root, _):
            if statusByWorktreeRoot[root] != status { statusByWorktreeRoot[root] = status }
        }
    }

    /// A blank status shell to merge branch/diff/PR fields into on first resolve.
    private func emptyStatus(for repoID: GitRepoID) -> GitRepoStatus {
        GitRepoStatus(
            repoID: repoID,
            branchName: nil,
            isDetachedHead: false,
            diffSummary: .empty,
            changedFiles: [],
            prStatus: nil,
            lastUpdated: Date()
        )
    }

    // MARK: - Branch / Refs Refresh

    /// Refreshes branch + refs (NOT diff, NOT PR-on-miss) for a repo and each of
    /// its subscribed worktree roots. Cancels any in-flight branch task per
    /// target on re-entry. PR is only seeded from a cache hit here — fetches are
    /// driven by refs eviction, the slow poll, and gate-open.
    func refreshBranchAndRefs(repoID: GitRepoID) {
        guard repoRefCounts[repoID] != nil else { return }
        for target in targets(for: repoID) {
            refreshBranch(target: target)
        }
    }

    private func refreshBranch(target: StatusTarget) {
        guard targetIsLive(target), let directory = directory(for: target) else { return }
        inFlightBranchTasks[target]?.cancel()

        let repoID = owningRepoID(target)
        let gitLocal = self.gitLocal
        let task = Task { [weak self] in
            await gitLocal.acquire()
            let branch = await GitStatusService.currentBranch(directory: directory)
            await gitLocal.release()

            guard !Task.isCancelled, let self, self.targetIsLive(target) else {
                self?.inFlightBranchTasks.removeValue(forKey: target)
                return
            }

            var status = self.currentStatus(for: target) ?? self.emptyStatus(for: repoID)
            let branchChanged = status.branchName != branch?.name
            status.branchName = branch?.name
            status.isDetachedHead = branch?.isDetached ?? false
            status.lastUpdated = Date()

            // Seed PR from cache only; never launch a fetch on miss. On a branch
            // switch the prior branch's PR must not render under the new name.
            if let branchName = branch?.name {
                if branchChanged { status.prStatus = nil }
                if case .hit(let cached) = self.prCache.get(repoID: repoID, branch: branchName) {
                    status.prStatus = cached
                }
            } else {
                status.prStatus = nil
            }

            self.writeStatus(status, for: target)
            self.inFlightBranchTasks.removeValue(forKey: target)
        }
        inFlightBranchTasks[target] = task
    }

    // MARK: - Working-Tree (Diff) Refresh

    /// Refreshes ONLY the diff/dirty summary for a repo and each of its
    /// subscribed worktree roots, cancelling any in-flight diff task per target
    /// on re-entry. Never touches branch or PR fields.
    func refreshWorkingTree(repoID: GitRepoID) {
        guard repoRefCounts[repoID] != nil else { return }
        for target in targets(for: repoID) {
            refreshWorkingTreeTarget(target: target)
        }
    }

    private func refreshWorkingTreeTarget(target: StatusTarget) {
        guard targetIsLive(target), let directory = directory(for: target) else { return }
        inFlightWorkingTreeTasks[target]?.cancel()

        let repoID = owningRepoID(target)
        let gitLocal = self.gitLocal
        let task = Task { [weak self] in
            await gitLocal.acquire()
            let diff = await GitStatusService.diffStatus(directory: directory)
            await gitLocal.release()

            guard !Task.isCancelled, let self, self.targetIsLive(target) else {
                self?.inFlightWorkingTreeTasks.removeValue(forKey: target)
                return
            }

            var status = self.currentStatus(for: target) ?? self.emptyStatus(for: repoID)
            status.diffSummary = diff.summary
            status.changedFiles = diff.files
            status.lastUpdated = Date()
            self.writeStatus(status, for: target)
            self.inFlightWorkingTreeTasks.removeValue(forKey: target)
        }
        inFlightWorkingTreeTasks[target] = task
    }

    // MARK: - PR Fetch (off the working-tree path)

    /// On-demand PR refresh for a repo — the `git.refresh` IPC path. Evicts the
    /// repo's PR cache, clears any PR network-backoff for its (repo, branch)
    /// targets, and forces a PR refetch (bypassing backoff) for each currently
    /// subscribed worktree-root branch, reusing the private PR-fetch machinery +
    /// the `ghNetwork` lane. Same shape as the refs-eviction branch of
    /// `processRefsFSEventBatch`, but triggered explicitly rather than by an
    /// FSEvents remote-ref change: `gh pr create` against an already-pushed branch
    /// makes no local ref change, so the watcher never fires and only this can
    /// update the badge without waiting for the slow poll. No-op when the repo
    /// isn't subscribed.
    func refreshPR(repoID: GitRepoID) {
        guard repoRefCounts[repoID] != nil else { return }
        prCache.evict(repoID: repoID)
        clearPRBackoff(repoID: repoID)
        for target in targets(for: repoID) {
            maybeFetchPR(target: target, bypassBackoff: true)
        }
    }

    /// Considers a PR fetch for a target. Skips when the branch is unknown, when
    /// backoff is active (unless `bypassBackoff`), or when the cache is fresh.
    /// Eviction paths pass `bypassBackoff` and have already made the cache miss.
    private func maybeFetchPR(target: StatusTarget, bypassBackoff: Bool) {
        guard targetIsLive(target), let directory = directory(for: target) else { return }
        let repoID = owningRepoID(target)
        guard let branch = currentStatus(for: target)?.branchName, !branch.isEmpty else { return }
        if !bypassBackoff, !prFetchAllowed(repoID: repoID, branch: branch) { return }
        if case .hit = prCache.get(repoID: repoID, branch: branch) { return }
        launchPRFetch(target: target, repoID: repoID, branch: branch, directory: directory)
    }

    /// Launches a PR status fetch through the global `ghNetwork` lane unless one
    /// is already in flight for this (repo, branch), writing the result into the
    /// target's status and updating network backoff on the outcome.
    private func launchPRFetch(target: StatusTarget, repoID: GitRepoID, branch: String, directory: String) {
        guard let fetchGen = prCache.markPending(repoID: repoID, branch: branch) else { return }
        prFetchLaunchCount += 1
        let taskID = UUID()
        let ghNetwork = self.ghNetwork
        let prTask = Task { [weak self] in
            defer {
                self?.prCache.clearPending(repoID: repoID, branch: branch, generation: fetchGen)
                self?.prFetchTasks[repoID]?.removeValue(forKey: taskID)
            }
            await ghNetwork.acquire()
            let fetched = await GitStatusService.fetchPRStatus(directory: directory, branch: branch)
            await ghNetwork.release()
            guard !Task.isCancelled, let self else { return }
            self.prCache.set(repoID: repoID, branch: branch, status: fetched, generation: fetchGen)
            // A nil result is a failure OR a genuine "no PR" — either way, back
            // off so a flaky/absent PR isn't re-polled every trigger.
            self.recordPRFetchResult(repoID: repoID, branch: branch, success: fetched != nil)

            // Skip the write if the branch moved (stale overwrite) or the PR
            // didn't change (avoid Observable churn on TTL-expiry refetches).
            if var current = self.currentStatus(for: target),
               current.branchName == branch,
               current.prStatus != fetched {
                current.prStatus = fetched
                self.writeStatus(current, for: target)
            }
        }
        prFetchTasks[repoID, default: [:]][taskID] = prTask
    }

    /// After the gate opens, fetch PR once for each target — but only after the
    /// eager branch refresh resolves the branch (so we know the cache key).
    /// A one-shot catch-up, distinct from `refreshBranchAndRefs` (which never
    /// launches a fetch on its own).
    private func fetchPROnGateOpen(repoID: GitRepoID) {
        let branchTasks = targets(for: repoID).compactMap { inFlightBranchTasks[$0] }
        Task { [weak self] in
            for task in branchTasks { _ = await task.value }
            guard let self, self.repoRefCounts[repoID] != nil else { return }
            for target in self.targets(for: repoID) {
                self.maybeFetchPR(target: target, bypassBackoff: false)
            }
        }
    }

    private func prFetchAllowed(repoID: GitRepoID, branch: String) -> Bool {
        guard let entry = prBackoff[PRBackoffKey(repoPath: repoID.path, branch: branch)] else { return true }
        return Date() >= entry.nextAllowed
    }

    private func recordPRFetchResult(repoID: GitRepoID, branch: String, success: Bool) {
        let key = PRBackoffKey(repoPath: repoID.path, branch: branch)
        if success {
            prBackoff.removeValue(forKey: key)
        } else {
            let previous = prBackoff[key]?.delay ?? 0
            let next = min(max(Self.prBackoffBase, previous * 2), Self.prBackoffMax)
            prBackoff[key] = (nextAllowed: Date().addingTimeInterval(next), delay: next)
        }
    }

    private func clearPRBackoff(repoID: GitRepoID) {
        prBackoff = prBackoff.filter { $0.key.repoPath != repoID.path }
    }

    // MARK: - Gate

    private func isRemote(_ repoID: GitRepoID) -> Bool { remotePollers[repoID] != nil }

    /// Recomputes and applies the working-tree gate for a repo. The gate is the
    /// OR over the repo's subscribers' `(visible || busy)`. On a closed→open
    /// transition, start the working-tree watcher + do one eager diff refresh +
    /// one gate-open PR fetch. On open→closed, stop the FSEventStream entirely.
    private func updateGate(repoID: GitRepoID) {
        guard repoRefCounts[repoID] != nil else { return }
        // Remote repos poll for everything — there is no FSEvents gate.
        guard remotePollers[repoID] == nil else { return }

        let shouldBeOpen = gateShouldBeOpen(repoID: repoID)
        let isOpen = workingTreeWatchers[repoID] != nil

        if shouldBeOpen && !isOpen {
            startWorkingTreeWatcher(repoID: repoID)
            refreshWorkingTree(repoID: repoID)   // eager catch-up
            fetchPROnGateOpen(repoID: repoID)     // one PR fetch on gate-open
        } else if !shouldBeOpen && isOpen {
            stopWorkingTreeWatcher(repoID: repoID)
        }
    }

    private func gateShouldBeOpen(repoID: GitRepoID) -> Bool {
        for (token, sub) in subscriptions where sub.repoID == repoID {
            let activity = subscriberActivity[token] ?? .default
            if activity.visible || activity.busy { return true }
        }
        return false
    }

    // MARK: - Watcher / Poller Lifecycle

    /// Starts the always-on watching for a repo on its first subscriber: a remote
    /// poller if the working tree lives on another host, else the refs watcher +
    /// slow PR poll. The gated working-tree watcher is started separately by the
    /// gate.
    private func startRepoWatching(repoID: GitRepoID, location: RepoLocation) {
        if RemoteExecutionRegistry.shared.channel(forDirectory: location.workingTree) != nil {
            startRemotePoller(repoID: repoID)
            return
        }
        startRefsWatcher(repoID: repoID, location: location)
        startPRPoller(repoID: repoID)
    }

    /// Cheap, always-on refs watcher. Its batch drives PR-cache eviction (on
    /// push/fetch), `branchGraphDirty` (on commit / branch switch), and a
    /// debounced branch refresh.
    private func startRefsWatcher(repoID: GitRepoID, location: RepoLocation) {
        guard refsWatchers[repoID] == nil else { return }
        let watchPaths = GitRepoWatcher.resolveRefsWatchPaths(for: location)
        let canonicalCommonDir = canonicalCommonDirByRepo[repoID]
            ?? GitRepoWatcher.canonicalizedPath(location.commonDir)

        let watcher = GitRepoWatcher(watchPaths: watchPaths) { [weak self] paths in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.repoDirectories[repoID] != nil else { return }
                self.processRefsFSEventBatch(
                    repoID: repoID,
                    paths: paths,
                    canonicalCommonDir: canonicalCommonDir
                )
                self.refsScheduler.schedule(key: repoID)
            }
        }
        refsWatchers[repoID] = watcher
    }

    /// Processes a single refs FSEvents batch. Evicts the PR cache and drives a
    /// PR fetch on a remote-ref change (push/fetch), and sets `branchGraphDirty`
    /// on a local-ref / HEAD change. Extracted for testability — the production
    /// watcher calls this on the MainActor; tests call it directly.
    ///
    /// - Note: Does NOT schedule the branch refresh; the caller does.
    func processRefsFSEventBatch(repoID: GitRepoID, paths: [String], canonicalCommonDir: String) {
        if GitRepoWatcher.pathsAffectPRState(paths, canonicalCommonDir: canonicalCommonDir) {
            prCache.evict(repoID: repoID)
            // A real push/fetch is a strong reason to retry now — reset backoff.
            clearPRBackoff(repoID: repoID)
            for target in targets(for: repoID) {
                maybeFetchPR(target: target, bypassBackoff: true)
            }
        }
        if GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: canonicalCommonDir),
           !branchGraphDirty.contains(repoID) {
            branchGraphDirty.insert(repoID)
        }
    }

    /// Gated working-tree watcher. Its batch drives ONLY the diff refresh.
    private func startWorkingTreeWatcher(repoID: GitRepoID) {
        guard workingTreeWatchers[repoID] == nil, let location = repoLocations[repoID] else { return }
        let watchPaths = GitRepoWatcher.resolveWorkingTreeWatchPaths(for: location)

        let watcher = GitRepoWatcher(watchPaths: watchPaths) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.repoDirectories[repoID] != nil else { return }
                self.workingTreeScheduler.schedule(key: repoID)
            }
        }
        workingTreeWatchers[repoID] = watcher
    }

    /// Slow per-repo PR poll — one of the three PR-fetch drivers.
    private func startPRPoller(repoID: GitRepoID) {
        guard prPollers[repoID] == nil else { return }
        let poller = PollingRefresher(interval: Self.prPollInterval) { [weak self] in
            guard let self, self.repoRefCounts[repoID] != nil else { return }
            for target in self.targets(for: repoID) {
                self.maybeFetchPR(target: target, bypassBackoff: false)
            }
        }
        prPollers[repoID] = poller
        poller.start()
    }

    /// Remote poller: FSEvents can't cross hosts, so both refs and working-tree
    /// collapse to this poll. Mirrors `SessionGitContext.startWatcher`'s remote
    /// branch.
    private func startRemotePoller(repoID: GitRepoID) {
        guard remotePollers[repoID] == nil else { return }
        let poller = PollingRefresher(interval: Self.remotePollInterval) { [weak self] in
            guard let self, self.repoDirectories[repoID] != nil else { return }
            let tick = (self.remotePollTicks[repoID] ?? 0) + 1
            self.remotePollTicks[repoID] = tick
            self.refreshBranchAndRefs(repoID: repoID)
            self.refreshWorkingTree(repoID: repoID)
            if tick % Self.remotePollHeavyEvery == 0 {
                // The signals a local refs batch raises — undetectable remotely,
                // so raise them on a cadence to force PR re-fetch + branch-graph
                // re-render.
                self.prCache.evict(repoID: repoID)
                self.clearPRBackoff(repoID: repoID)
                if !self.branchGraphDirty.contains(repoID) {
                    self.branchGraphDirty.insert(repoID)
                }
                for target in self.targets(for: repoID) {
                    self.maybeFetchPR(target: target, bypassBackoff: true)
                }
            }
        }
        remotePollers[repoID] = poller
        poller.start()
    }

    private func stopRefsWatcher(repoID: GitRepoID) {
        refsWatchers[repoID]?.stop()
        refsWatchers.removeValue(forKey: repoID)
    }

    private func stopWorkingTreeWatcher(repoID: GitRepoID) {
        workingTreeWatchers[repoID]?.stop()
        workingTreeWatchers.removeValue(forKey: repoID)
        workingTreeScheduler.cancel(key: repoID)
    }

    private func stopPRPoller(repoID: GitRepoID) {
        prPollers[repoID]?.stop()
        prPollers.removeValue(forKey: repoID)
    }

    private func stopRemotePoller(repoID: GitRepoID) {
        remotePollers[repoID]?.stop()
        remotePollers.removeValue(forKey: repoID)
        remotePollTicks.removeValue(forKey: repoID)
    }
}
