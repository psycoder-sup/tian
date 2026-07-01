import Foundation
import Observation
import OSLog

/// Per-Space git repository context. Detects repos from pane working directories,
/// tracks pane-to-repo assignments, and maintains branch name status for the sidebar.
@MainActor @Observable
final class SpaceGitContext {

    // MARK: - Observable State

    /// Map of detected repos to their current status. Drives sidebar re-renders.
    private(set) var repoStatuses: [GitRepoID: GitRepoStatus] = [:]

    /// Set of repos whose branch graph has been invalidated by an FSEvents
    /// batch since the last successful Branch-tab fetch. The Branch view-
    /// model reads + clears this. Working-tree-only events do NOT add to
    /// this set.
    private(set) var branchGraphDirty: Set<GitRepoID> = []

    /// Maps each pane ID to its detected repo (nil entry = not yet detected or not in a repo).
    private(set) var paneRepoAssignments: [UUID: GitRepoID] = [:]

    /// Ordered list of pinned repos for display. First is worktree-derived repo if applicable.
    private(set) var pinnedRepoOrder: [GitRepoID] = []

    // MARK: - Private State

    /// The repo ID derived from worktreePath (if set). Always sorted first in pinnedRepoOrder.
    private var worktreeRepoID: GitRepoID?

    /// The retained worktree-init detection task. Pane-driven detection awaits
    /// this before deciding whether a pane may drive the shared repo's status,
    /// removing the restore-time parent-vs-worktree race.
    private var worktreeDetectionTask: Task<Void, Never>?

    /// Tracks in-flight refresh tasks per repo for cancellation on rapid re-triggers.
    private var inFlightTasks: [GitRepoID: Task<Void, Never>] = [:]

    /// Set to true by `teardown()`. Guards `refreshRepo` against late-firing
    /// scheduled refreshes that pass through `await semaphore.acquire()` after
    /// the Space has been torn down.
    private var isTornDown = false

    /// Trailing-debounce + global concurrency cap for git refresh during
    /// FSEvents storms (e.g., active dev server churning files across many
    /// pinned repos). The scheduler dispatches to `refreshRepo` after the
    /// debounce window, throttling at most 2 concurrent git pipelines.
    ///
    /// `@ObservationIgnored` because the scheduler is internal mutation
    /// plumbing, not observable model state — and `lazy` is incompatible
    /// with the `@ObservationTracked` accessor the macro otherwise emits.
    @ObservationIgnored
    private lazy var refreshScheduler = RefreshScheduler<GitRepoID>(
        debounce: .milliseconds(250),
        maxConcurrent: 2
    ) { [weak self] repoID in
        await MainActor.run { [weak self] in
            guard let self else { return }
            guard let dir = self.repoDirectories[repoID] else { return }
            self.refreshRepo(repoID: repoID, directory: dir)
        }
    }

    /// Last-known working directory per pane.
    private var paneDirectories: [UUID: String] = [:]

    /// A directory we know maps to a specific repo, used for branch refresh.
    private var repoDirectories: [GitRepoID: String] = [:]

    /// Root working tree path per repo, used for same-repo prefix checks.
    private var repoRoots: [GitRepoID: String] = [:]

    /// PR status cache with 60-second TTL.
    private let prCache = PRStatusCache()

    /// Tracks in-flight PR fetch tasks per repo, keyed inner by a per-call
    /// UUID so a completing task removes only its own entry. The outer key
    /// exists so `teardown`/`unpinRepo` can cancel all fetches for a repo
    /// in one pass.
    private var prFetchTasks: [GitRepoID: [UUID: Task<Void, Never>]] = [:]

    /// Active FSEvents watchers per repo.
    private var watchers: [GitRepoID: GitRepoWatcher] = [:]

    // MARK: - Public Computed

    /// Number of active FSEvents watchers. Exposed for testing.
    var activeWatcherCount: Int { watchers.count }

    // MARK: - Init

    /// Creates a git context for a Space.
    /// - Parameter worktreePath: If non-nil, eagerly detects the repo from this path.
    init(worktreePath: URL?) {
        if let worktreePath {
            // Kick off detection directly (not via an outer Task) so
            // `worktreeDetectionTask` is assigned during init — before any
            // `paneAdded` restore call runs.
            detectAndRefresh(paneID: nil, directory: worktreePath.path, isWorktreeInit: true)
        }
    }

    // MARK: - Public Methods

    /// Called when the Space's worktree path is set post-init.
    /// Triggers eager repo detection and marks the repo as the worktree repo for sort priority.
    func setWorktreePath(_ path: String) {
        detectAndRefresh(paneID: nil, directory: path, isWorktreeInit: true)
    }

    /// Called when a pane's working directory changes (OSC 7).
    func paneWorkingDirectoryChanged(paneID: UUID, newDirectory: String) {
        paneDirectories[paneID] = newDirectory

        // Skip re-detection if this pane is already assigned to a repo
        // and the new directory is within the same repo root.
        if let existingRepoID = paneRepoAssignments[paneID],
           let repoRoot = repoRoots[existingRepoID],
           pathIsWithin(newDirectory, repoRoot) {
            // Same repo — just refresh branch info without re-detecting.
            // Set repoDirectories BEFORE scheduling so the scheduler's
            // handler resolves the latest directory when it fires.
            repoDirectories[existingRepoID] = newDirectory
            refreshScheduler.schedule(key: existingRepoID)
            return
        }

        // Detect new repo — pane may be moving to a different repo or a non-git dir
        Task { [weak self] in
            guard let self else { return }

            // Don't race the worktree-init detection: it and this pane path
            // target the same shared worktree/parent GitRepoID (see
            // detectAndRefresh). await returns immediately for non-worktree
            // spaces (task is nil).
            await self.worktreeDetectionTask?.value

            let repo = await GitStatusService.detectRepo(directory: newDirectory)

            if let repo {
                let newRepoID = GitRepoID(path: repo.commonDir)

                // Read current assignment AFTER await to avoid stale capture
                // (rapid calls could have reassigned pane to an intermediate repo)
                let previousRepoID = self.paneRepoAssignments[paneID]

                // Update pane assignment
                self.paneRepoAssignments[paneID] = newRepoID

                // A worktree and its parent repo share one GitRepoID. A pane
                // whose directory is in the parent (not the worktree) must not
                // overwrite the worktree's authoritative directory/status — but
                // is still tracked below for pinning/GC.
                let collidesWithParent = self.collidesWithParentWorktree(
                    repoID: newRepoID, directory: newDirectory)

                if !collidesWithParent {
                    self.repoDirectories[newRepoID] = newDirectory
                }
                if self.repoRoots[newRepoID] == nil {
                    self.repoRoots[newRepoID] = repo.workingTree
                }

                // Add new repo if not already pinned
                if !self.pinnedRepoOrder.contains(newRepoID) {
                    self.pinnedRepoOrder.append(newRepoID)
                    self.sortPinnedRepoOrder()
                    self.startWatcher(repoID: newRepoID, location: repo)
                    Log.git.debug("Pinned new repo: \(newRepoID.path)")
                }

                if !collidesWithParent {
                    self.refreshScheduler.schedule(key: newRepoID)
                }

                // Garbage collect previous repo if pane moved to a different repo
                if let previousRepoID, newRepoID != previousRepoID {
                    let stillReferenced = self.paneRepoAssignments.values.contains(previousRepoID)
                    if !stillReferenced {
                        self.unpinRepo(previousRepoID)
                    }
                }
            }
            // If repo is nil (non-git dir), do NOT update pane assignment.
            // The pane keeps its previous repo association (sticky pinning FR-020.3).
        }
    }

    /// Called when a new pane is created or restored with a known working directory.
    func paneAdded(paneID: UUID, workingDirectory: String?) {
        guard let wd = workingDirectory, !wd.isEmpty, wd != "~" else { return }
        paneDirectories[paneID] = wd
        detectAndRefresh(paneID: paneID, directory: wd)
    }

    /// Called when a pane is closed. Cleans up assignments and garbage-collects orphaned repos.
    func paneRemoved(paneID: UUID) {
        paneDirectories.removeValue(forKey: paneID)
        guard let repoID = paneRepoAssignments.removeValue(forKey: paneID) else { return }

        let stillReferenced = paneRepoAssignments.values.contains(repoID)
        if !stillReferenced {
            unpinRepo(repoID)
        }
    }

    /// Manually triggers a git status refresh for all pinned repos.
    func refresh() {
        for repoID in pinnedRepoOrder {
            guard let directory = repoDirectories[repoID] else { continue }
            // Drop any pending scheduler debounce so it can't race-cancel the
            // manual refresh we're about to start.
            refreshScheduler.cancel(key: repoID)
            refreshRepo(repoID: repoID, directory: directory)
        }
    }

    /// Evicts cached PR status for every pinned repo and triggers a refresh.
    /// Used by the `git.refresh` IPC so callers (e.g. a Claude PostToolUse
    /// hook after `gh pr create`) can update the badge without waiting for
    /// the 60s cache TTL to expire — `gh pr create` against an already-pushed
    /// branch makes no local file change, so the FSEvents-based eviction
    /// path doesn't fire.
    func refreshPR() {
        for repoID in pinnedRepoOrder {
            prCache.evict(repoID: repoID)
            guard let directory = repoDirectories[repoID] else { continue }
            refreshRepo(repoID: repoID, directory: directory)
        }
    }

    /// Removes a repo from the `branchGraphDirty` set. Called by the Branch
    /// view-model after a successful branch-graph refetch.
    func clearBranchGraphDirty(repoID: GitRepoID) {
        branchGraphDirty.remove(repoID)
    }

    /// Cancels all in-flight tasks and clears state. Called on Space close.
    func teardown() {
        isTornDown = true
        worktreeDetectionTask?.cancel()
        worktreeDetectionTask = nil
        for task in inFlightTasks.values { task.cancel() }
        inFlightTasks.removeAll()
        for inner in prFetchTasks.values {
            for task in inner.values { task.cancel() }
        }
        prFetchTasks.removeAll()
        refreshScheduler.cancelAll()
        repoStatuses.removeAll()
        paneRepoAssignments.removeAll()
        pinnedRepoOrder.removeAll()
        paneDirectories.removeAll()
        repoDirectories.removeAll()
        repoRoots.removeAll()
        for watcher in watchers.values { watcher.stop() }
        watchers.removeAll()
        prCache.evictAll()
    }

    // MARK: - Private

    /// True when `dir` is `root` itself or a descendant of `root`. Centralizes
    /// the path-prefix logic shared by the same-repo fast path and the worktree
    /// parent-collision guard.
    private func pathIsWithin(_ dir: String, _ root: String) -> Bool {
        if dir == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return dir.hasPrefix(prefix)
    }

    /// True when `repoID` is the Space's own worktree repo but `directory` is
    /// OUTSIDE the worktree working tree — i.e. a pane in the PARENT repo (which
    /// shares the worktree's GitRepoID). Such a pane must not drive the shared
    /// repo's directory/status. Anchored on `repoRoots[worktreeRepoID]`, the same
    /// git-derived path the same-repo fast path compares against.
    private func collidesWithParentWorktree(repoID: GitRepoID, directory: String) -> Bool {
        guard let wtID = worktreeRepoID, repoID == wtID, let wtRoot = repoRoots[wtID]
        else { return false }
        return !pathIsWithin(directory, wtRoot)
    }

    /// Sorts pinnedRepoOrder: worktree repo first (if applicable), then alphabetical by path.
    private func sortPinnedRepoOrder() {
        let worktreeID = self.worktreeRepoID
        pinnedRepoOrder.sort { a, b in
            if a == worktreeID { return true }
            if b == worktreeID { return false }
            return a.path < b.path
        }
    }

    /// Unpins a repo and cleans up all associated state.
    private func unpinRepo(_ repoID: GitRepoID) {
        // Never GC the Space's own worktree repo — it's owned by the Space's
        // worktreePath, not by any pane, so pane removal/move must not remove it.
        // teardown() clears everything directly and does not route through here.
        guard repoID != worktreeRepoID else { return }

        inFlightTasks[repoID]?.cancel()
        inFlightTasks.removeValue(forKey: repoID)
        if let inner = prFetchTasks[repoID] {
            for task in inner.values { task.cancel() }
        }
        prFetchTasks.removeValue(forKey: repoID)
        refreshScheduler.cancel(key: repoID)
        repoStatuses.removeValue(forKey: repoID)
        repoDirectories.removeValue(forKey: repoID)
        repoRoots.removeValue(forKey: repoID)
        pinnedRepoOrder.removeAll { $0 == repoID }
        stopWatcher(repoID: repoID)
        Log.git.debug("Unpinned orphaned repo: \(repoID.path)")
    }

    /// Detects the git repo for a directory and refreshes its status.
    /// - Parameters:
    ///   - paneID: The pane that triggered detection (nil for worktree-path init).
    ///   - directory: The working directory to detect from.
    ///   - isWorktreeInit: If true, sets worktreeRepoID for sort priority.
    private func detectAndRefresh(paneID: UUID?, directory: String, isWorktreeInit: Bool = false) {
        let task = Task { [weak self] in
            guard let self else { return }

            // A pane-driven detection must not race the worktree-init detection:
            // both target the shared worktree/parent GitRepoID, and the
            // worktree's authoritative state must settle before we decide
            // whether this pane may drive it. The worktree-init task must not
            // await itself; the await is a no-op for non-worktree spaces (nil).
            if !isWorktreeInit {
                await self.worktreeDetectionTask?.value
            }

            guard let repo = await GitStatusService.detectRepo(directory: directory) else {
                if let paneID {
                    self.paneRepoAssignments.removeValue(forKey: paneID)
                }
                return
            }

            let repoID = GitRepoID(path: repo.commonDir)

            if isWorktreeInit {
                self.worktreeRepoID = repoID
            }

            if let paneID {
                self.paneRepoAssignments[paneID] = repoID
            }

            // For worktrees this resolves to the worktree's own root, not the
            // main repo — so the same-repo prefix check at paneWorkingDirectoryChanged
            // works correctly for panes scoped to a linked worktree.
            if self.repoRoots[repoID] == nil {
                self.repoRoots[repoID] = repo.workingTree
            }

            // Add to pinned order if new
            if !self.pinnedRepoOrder.contains(repoID) {
                self.pinnedRepoOrder.append(repoID)
                self.sortPinnedRepoOrder()
                Log.git.debug("Pinned new repo: \(repoID.path)")
            }

            self.startWatcher(repoID: repoID, location: repo)

            // A worktree and its parent repo share one GitRepoID (keyed on
            // --git-common-dir). On restore, a claude pane persisted in the
            // PARENT repo would otherwise overwrite the worktree's authoritative
            // directory and render the parent's branch. Track the pane for
            // lifecycle above, but never let it drive the shared repo's status.
            let collidesWithParent = !isWorktreeInit
                && self.collidesWithParentWorktree(repoID: repoID, directory: directory)
            if collidesWithParent {
                Log.git.debug("Worktree space: parent-repo pane tracked but not driving status: \(directory)")
                return
            }

            self.repoDirectories[repoID] = directory
            self.refreshRepo(repoID: repoID, directory: directory)
        }

        // Retain the worktree-init task synchronously so pane paths can await it.
        if isWorktreeInit {
            worktreeDetectionTask?.cancel()
            worktreeDetectionTask = task
        }
    }

    /// Refreshes branch and diff status for a specific repo, cancelling any
    /// in-flight branch + diff task on re-entry.
    ///
    /// PR fetches are not cancelled on re-entry: `markPending` dedupes
    /// concurrent fetches per (repo, branch) and the completion handler
    /// skips writes when the branch has moved. Each fetch is tracked by a
    /// per-call UUID so its completion removes only its own entry, even
    /// when a later refresh spawned a fresh fetch after an `evict`.
    private func refreshRepo(repoID: GitRepoID, directory: String) {
        guard !isTornDown else { return }
        inFlightTasks[repoID]?.cancel()

        let task = Task { [weak self] in
            async let branchResult = GitStatusService.currentBranch(directory: directory)
            async let diffResult = GitStatusService.diffStatus(directory: directory)

            let branch = await branchResult
            let diff = await diffResult

            guard !Task.isCancelled else { return }
            guard let self else { return }

            // Check PR cache. On miss, seed from the previously-rendered
            // status only when the branch name is unchanged — so the badge
            // keeps its old value through a TTL-expiry refetch, but a branch
            // switch doesn't render the prior branch's PR under the new name.
            var prStatus: PRStatus? = nil
            if let branchName = branch?.name {
                if self.repoStatuses[repoID]?.branchName == branchName {
                    prStatus = self.repoStatuses[repoID]?.prStatus
                }
                switch self.prCache.get(repoID: repoID, branch: branchName) {
                case .hit(let cached):
                    prStatus = cached
                case .miss:
                    self.launchPRFetchIfNeeded(
                        repoID: repoID,
                        branch: branchName,
                        directory: directory
                    )
                }
            }

            let status = GitRepoStatus(
                repoID: repoID,
                branchName: branch?.name,
                isDetachedHead: branch?.isDetached ?? false,
                diffSummary: diff.summary,
                changedFiles: diff.files,
                prStatus: prStatus,
                lastUpdated: Date()
            )

            // Skip the Observable write when nothing visible changed — avoids
            // sidebar re-renders on every FSEvents batch during noisy activity
            // like an active build.
            if self.repoStatuses[repoID] != status {
                self.repoStatuses[repoID] = status
            }
            self.inFlightTasks.removeValue(forKey: repoID)
        }

        inFlightTasks[repoID] = task
    }

    /// Launches a PR status fetch unless one is already in flight for this
    /// (repo, branch). The task keys itself by a per-call UUID so its
    /// completion removes only its own entry, surviving an evict that
    /// spawned a fresh fetch in parallel.
    private func launchPRFetchIfNeeded(repoID: GitRepoID, branch: String, directory: String) {
        guard let fetchGen = prCache.markPending(repoID: repoID, branch: branch) else { return }
        let taskID = UUID()
        let prTask = Task { [weak self] in
            defer {
                self?.prCache.clearPending(repoID: repoID, branch: branch, generation: fetchGen)
                self?.prFetchTasks[repoID]?.removeValue(forKey: taskID)
            }
            let fetched = await GitStatusService.fetchPRStatus(directory: directory, branch: branch)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            self.prCache.set(repoID: repoID, branch: branch, status: fetched, generation: fetchGen)
            // Skip the write if the branch moved (stale overwrite) or the PR
            // didn't change (avoid Observable churn on TTL-expiry refetches).
            if let current = self.repoStatuses[repoID],
               current.branchName == branch,
               current.prStatus != fetched {
                var updated = current
                updated.prStatus = fetched
                self.repoStatuses[repoID] = updated
            }
        }
        prFetchTasks[repoID, default: [:]][taskID] = prTask
    }

    // MARK: - Watcher Management

    private func startWatcher(repoID: GitRepoID, location: RepoLocation) {
        // Don't start a duplicate watcher if one already exists
        guard watchers[repoID] == nil else { return }

        let watchPaths = GitRepoWatcher.resolveWatchPaths(for: location)
        // Canonicalize once so `pathsAffectPRState` / `pathsAffectBranchGraph`
        // don't call `realpath(3)` on every FSEvents batch.
        let canonicalCommonDir = GitRepoWatcher.canonicalizedPath(location.commonDir)

        let watcher = GitRepoWatcher(watchPaths: watchPaths) { [weak self] paths in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.repoDirectories[repoID] != nil else { return }
                self.processFSEventBatch(
                    repoID: repoID,
                    paths: paths,
                    canonicalCommonDir: canonicalCommonDir
                )
                self.refreshScheduler.schedule(key: repoID)
            }
        }

        watchers[repoID] = watcher
    }

    /// Processes a single FSEvents batch for a repo. Evicts PR cache on remote-ref
    /// changes (existing behaviour) and sets `branchGraphDirty` on local-ref / HEAD
    /// changes. Extracted for testability — the production watcher calls this on
    /// the MainActor; tests call it directly without needing live FSEvents.
    ///
    /// - Note: Does NOT schedule a refresh; the caller (watcher or test) does that.
    func processFSEventBatch(repoID: GitRepoID, paths: [String], canonicalCommonDir: String) {
        // Existing PR-cache eviction path — unchanged.
        if GitRepoWatcher.pathsAffectPRState(paths, canonicalCommonDir: canonicalCommonDir) {
            prCache.evict(repoID: repoID)
        }
        // Branch-graph dirty flag — new.
        if GitRepoWatcher.pathsAffectBranchGraph(paths, canonicalCommonDir: canonicalCommonDir),
           !branchGraphDirty.contains(repoID) {
            branchGraphDirty.insert(repoID)
        }
    }

    private func stopWatcher(repoID: GitRepoID) {
        watchers[repoID]?.stop()
        watchers.removeValue(forKey: repoID)
    }
}
