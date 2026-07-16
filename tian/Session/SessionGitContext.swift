import Foundation
import Observation

/// Per-Session git repository context — a THIN ADAPTER over the app-global
/// `GitMonitor` (ADR 0005, wave 3).
///
/// This type no longer owns watchers, caches, a refresh scheduler, or the
/// git-shelling refresh loop. It keeps only the Session's own pane→repo /
/// pane→worktree-root mapping and the pinned-repo display order, detects repos
/// through `GitMonitor.shared.detect(...)` (cached + globally concurrency-capped),
/// SUBSCRIBES/UNSUBSCRIBES its panes to `GitMonitor.shared`, and PROXIES every
/// status read straight through to the monitor's `@Observable` state.
///
/// The public surface is unchanged so `Session` and the sidebar views are
/// untouched. The observable read properties (`repoStatuses`,
/// `statusByWorktreeRoot`, `branchGraphDirty`) are computed passthroughs that
/// touch `GitMonitor.shared`'s observable storage AT CALL TIME — never a stored
/// snapshot — so SwiftUI re-renders when the monitor updates.
///
/// Wave 3 does NOT feed the monitor real visible/busy signals yet (that's
/// wave 4); it relies on the monitor's default-open working-tree gate, so
/// runtime behaviour is preserved.
@MainActor @Observable
final class SessionGitContext {

    // MARK: - Observable Read State (proxied to GitMonitor.shared)

    /// This session's pinned repos mapped to their current status, read through
    /// from the app-global monitor. Filtered to `pinnedRepoOrder` so a session
    /// only ever sees its own repos even though the monitor is process-global.
    ///
    /// Computed (not stored) so the read touches `GitMonitor.shared.repoStatuses`
    /// — an `@Observable` property — on every access, keeping the sidebar's
    /// observation dependency live.
    var repoStatuses: [GitRepoID: GitRepoStatus] {
        let monitorStatuses = GitMonitor.shared.repoStatuses
        var result: [GitRepoID: GitRepoStatus] = [:]
        for repoID in pinnedRepoOrder {
            if let status = monitorStatuses[repoID] {
                result[repoID] = status
            }
        }
        return result
    }

    /// Set of this session's repos whose branch graph the monitor has flagged
    /// dirty. Intersected with `pinnedRepoOrder` so a sibling session's dirty
    /// repo never leaks into this one's Branch view. Reads the monitor's
    /// `@Observable` `branchGraphDirty` at call time.
    var branchGraphDirty: Set<GitRepoID> {
        GitMonitor.shared.branchGraphDirty.intersection(Set(pinnedRepoOrder))
    }

    /// Full git status (branch + diff + PR) per worktree root for the roots this
    /// session's panes live in, read through from the monitor. Lets the sidebar
    /// render each tab's own branch AND change/PR badges even when several tabs
    /// share one `GitRepoID` (e.g. sibling worktrees). Reads the monitor's
    /// `@Observable` `statusByWorktreeRoot` at call time.
    var statusByWorktreeRoot: [String: GitRepoStatus] {
        let monitorStatuses = GitMonitor.shared.statusByWorktreeRoot
        var result: [String: GitRepoStatus] = [:]
        for root in paneWorktreeRoot.values where result[root] == nil {
            if let status = monitorStatuses[root] {
                result[root] = status
            }
        }
        // Also surface the worktree-init subscription's root, which has no owning
        // pane — otherwise a freshly-created worktree session shows no status
        // until a pane maps to that root. Deduped against the pane roots above.
        if let root = worktreeInitSubscription?.worktreeRoot,
           result[root] == nil,
           let status = monitorStatuses[root] {
            result[root] = status
        }
        return result
    }

    // MARK: - Observable Mapping State (session-owned)

    /// Maps each pane ID to its detected repo (nil entry = not yet detected or not in a repo).
    private(set) var paneRepoAssignments: [UUID: GitRepoID] = [:]

    /// Ordered list of pinned repos for display. First is worktree-derived repo if applicable.
    private(set) var pinnedRepoOrder: [GitRepoID] = []

    /// Maps each pane to its worktree root (`git rev-parse --show-toplevel`).
    /// Unlike `paneRepoAssignments` (keyed on the shared `--git-common-dir`), the
    /// worktree root is unique per branch, so panes in different worktrees of the
    /// same repo resolve to different roots.
    private(set) var paneWorktreeRoot: [UUID: String] = [:]

    // MARK: - Private Mapping State (session-owned)

    /// Directory last applied to each pane via `setPaneDirectory` (the Claude
    /// bridge). Kept separate from `paneDirectories` (which the OSC 7 path also
    /// writes) so an OSC 7 update to the same path can't suppress the bridge's
    /// forced full detect — see `setPaneDirectory`.
    private var paneBridgeDirectory: [UUID: String] = [:]

    /// The repo ID derived from worktreePath (if set). Always sorted first in pinnedRepoOrder.
    private var worktreeRepoID: GitRepoID?

    /// The retained worktree-init detection task. Pane-driven detection awaits
    /// this before deciding whether a pane may drive the shared repo's status,
    /// removing the restore-time parent-vs-worktree race.
    private var worktreeDetectionTask: Task<Void, Never>?

    /// Set to true by `teardown()`. Guards the detection tasks against a
    /// late-firing subscribe after the Session has been torn down (they resolve
    /// `detect` asynchronously and would otherwise re-subscribe to the monitor).
    private var isTornDown = false

    /// Last-known working directory per pane.
    private var paneDirectories: [UUID: String] = [:]

    /// Pane IDs currently known to this session — a pane is inserted the moment
    /// it drives detection and dropped by `paneRemoved`/`teardown`. Detached
    /// detection tasks re-check this AFTER their async `detect(...)` resolves so a
    /// pane removed mid-detection can't resurrect its mapping or leak a monitor
    /// subscription for a pane that no longer exists.
    private var livePanes: Set<UUID> = []

    /// Root working tree path per repo, used for same-repo prefix checks and the
    /// worktree parent-collision guard.
    private var repoRoots: [GitRepoID: String] = [:]

    // MARK: - Subscription State

    /// One live `GitMonitor` subscription — the token plus the (repoID, root) it
    /// resolves to, so a pane move can tell "same target, skip" from "different
    /// target, re-subscribe" without querying the monitor.
    private struct Subscription {
        let token: GitMonitor.SubscriptionToken
        let repoID: GitRepoID
        let worktreeRoot: String
    }

    /// Live monitor subscriptions keyed by pane. Replaced when a pane moves to a
    /// different repo/root; released on `paneRemoved`/`teardown`.
    private var paneSubscriptions: [UUID: Subscription] = [:]

    /// The subscription for the Session's OWN worktree (from `worktreePath`),
    /// which has no owning pane. Kept apart so pane GC can never release it.
    private var worktreeInitSubscription: Subscription?

    // MARK: - Activity State (working-tree gate feed, ADR 0005 change C)

    /// Latest visible/busy activity the view layer has reported for this session,
    /// forwarded to `GitMonitor` for every subscription this session holds and
    /// re-applied to any subscription created later. Defaults to visible (safe):
    /// before the first real `setActivity` report a fresh token rides the
    /// monitor's default-open working-tree gate so its diff is never frozen.
    private var latestVisible = true
    private var latestBusy = false

    // MARK: - Test Seams

    /// Number of live `GitMonitor` subscriptions this session holds (pane
    /// subscriptions plus the worktree-init one). Exposed for testing the
    /// adapter's subscribe/unsubscribe lifecycle.
    var activeSubscriptionCount: Int {
        paneSubscriptions.count + (worktreeInitSubscription != nil ? 1 : 0)
    }

    // MARK: - Init

    /// Creates a git context for a Session.
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

    /// Called when the Session's worktree path is set post-init.
    /// Triggers eager repo detection and marks the repo as the worktree repo for sort priority.
    func setWorktreePath(_ path: String) {
        detectAndRefresh(paneID: nil, directory: path, isWorktreeInit: true)
    }

    /// Called when a pane's working directory changes (OSC 7).
    func paneWorkingDirectoryChanged(paneID: UUID, newDirectory: String) {
        livePanes.insert(paneID)
        paneDirectories[paneID] = newDirectory

        // Skip re-detection if this pane is already assigned to a repo and the
        // new directory is within the same repo root: a `cd` inside the repo
        // can't change the branch/worktree, so just poke the monitor to refresh
        // rather than re-shelling `detectRepo`.
        if let existingRepoID = paneRepoAssignments[paneID],
           let repoRoot = repoRoots[existingRepoID],
           pathIsWithin(newDirectory, repoRoot) {
            GitMonitor.shared.refreshBranchAndRefs(repoID: existingRepoID)
            GitMonitor.shared.refreshWorkingTree(repoID: existingRepoID)
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
            guard !self.isTornDown else { return }

            let repo = await GitMonitor.shared.detect(directory: newDirectory)
            guard !self.isTornDown else { return }

            // If the pane was removed while `detect` was in flight, bail without
            // resurrecting its mapping or leaking a monitor subscription.
            guard self.livePanes.contains(paneID) else { return }

            if let repo {
                let newRepoID = GitRepoID(path: repo.commonDir)

                // Read current assignment AFTER await to avoid stale capture
                // (rapid calls could have reassigned pane to an intermediate repo)
                let previousRepoID = self.paneRepoAssignments[paneID]

                // Update pane assignment + worktree root.
                self.paneRepoAssignments[paneID] = newRepoID
                self.paneWorktreeRoot[paneID] = repo.workingTree

                if self.repoRoots[newRepoID] == nil {
                    self.repoRoots[newRepoID] = repo.workingTree
                }

                // Add new repo if not already pinned
                if !self.pinnedRepoOrder.contains(newRepoID) {
                    self.pinnedRepoOrder.append(newRepoID)
                    self.sortPinnedRepoOrder()
                    Log.git.debug("Pinned new repo: \(newRepoID.path)")
                }

                // (Re)subscribe this pane to its (possibly new) repo/root. The
                // monitor's first-subscriber-wins keeps a worktree authoritative
                // over a colliding parent pane, so no special collision handling
                // is needed here beyond the mapping above.
                self.subscribePane(paneID, location: repo, worktreeRoot: repo.workingTree)

                // Garbage collect previous repo if pane moved to a different repo
                if let previousRepoID, newRepoID != previousRepoID {
                    let stillReferenced = self.paneRepoAssignments.values.contains(previousRepoID)
                    if !stillReferenced {
                        self.unpinRepo(previousRepoID)
                    }
                }
            }
            // If repo is nil (non-git dir), do NOT update pane assignment or
            // release the subscription. The pane keeps its previous repo
            // association (sticky pinning FR-020.3).
        }
    }

    /// Called when a new pane is created or restored with a known working directory.
    func paneAdded(paneID: UUID, workingDirectory: String?) {
        guard let wd = workingDirectory, !wd.isEmpty, wd != "~" else { return }
        livePanes.insert(paneID)
        paneDirectories[paneID] = wd
        detectAndRefresh(paneID: paneID, directory: wd)
    }

    /// Applies a pane's working directory reported out-of-band — e.g. a Claude
    /// `CwdChanged` / `EnterWorktree` hook — rather than via the shell's OSC 7.
    ///
    /// Unlike `paneWorkingDirectoryChanged`, this always runs a full detect (via
    /// `detectAndRefresh`) instead of the same-repo fast path. That matters
    /// because Claude's default worktrees live at `.claude/worktrees/<name>`,
    /// physically nested inside the main working tree: the fast path's
    /// path-prefix check would treat such a directory as "still the main repo"
    /// and never update `paneWorktreeRoot`, so the tab's branch would stay wrong.
    /// A full detect resolves the worktree's own root.
    func setPaneDirectory(paneID: UUID, directory: String) {
        guard !directory.isEmpty else { return }
        // Dedupe repeated CwdChanged for the same dir so a busy `cd` loop
        // doesn't spawn a git pipeline per event. Key on the bridge's own
        // history, NOT `paneDirectories`: the OSC 7 fast path writes
        // `paneDirectories` without updating `paneWorktreeRoot`, so deduping
        // against it would let an OSC 7 event to a nested worktree silently
        // suppress the very full detect this method exists to force.
        guard paneBridgeDirectory[paneID] != directory else { return }
        livePanes.insert(paneID)
        paneBridgeDirectory[paneID] = directory
        paneDirectories[paneID] = directory
        detectAndRefresh(paneID: paneID, directory: directory)
    }

    /// Called when a pane is closed. Releases the pane's monitor subscription,
    /// cleans up assignments, and garbage-collects orphaned repos.
    func paneRemoved(paneID: UUID) {
        livePanes.remove(paneID)
        paneDirectories.removeValue(forKey: paneID)
        paneBridgeDirectory.removeValue(forKey: paneID)
        paneWorktreeRoot.removeValue(forKey: paneID)

        // Release this pane's subscription (if any) BEFORE the assignment guard
        // so a pane that had `cd`'d to a non-git dir (its assignment cleared but
        // its subscription still live) can't leak a token. The monitor's
        // refcount GC reclaims the repo once no session references it.
        if let sub = paneSubscriptions.removeValue(forKey: paneID) {
            GitMonitor.shared.unsubscribe(sub.token)
        }

        guard let repoID = paneRepoAssignments.removeValue(forKey: paneID) else { return }

        let stillReferenced = paneRepoAssignments.values.contains(repoID)
        if !stillReferenced {
            unpinRepo(repoID)
        }
    }

    /// Reports this session's current visibility/busy activity to `GitMonitor`
    /// for EVERY subscription it holds (per-pane tokens + the worktree-init one).
    /// The monitor ORs the signal across a repo's subscribers to gate the
    /// expensive working-tree watcher (ADR 0005, change C): a background, idle
    /// session's gate closes; the same session while Claude is busy keeps it open.
    ///
    /// The view layer calls this on first appearance and whenever the inputs
    /// change (window visibility, session activeness, aggregate Claude state).
    /// The latest values are stored so a subscription created afterwards inherits
    /// them (see `applyLatestActivity`) instead of riding the default-open gate.
    func setActivity(visible: Bool, busy: Bool) {
        latestVisible = visible
        latestBusy = busy
        for sub in paneSubscriptions.values {
            GitMonitor.shared.setSubscriberActivity(sub.token, visible: visible, busy: busy)
        }
        if let sub = worktreeInitSubscription {
            GitMonitor.shared.setSubscriberActivity(sub.token, visible: visible, busy: busy)
        }
    }

    /// Manually triggers a git status refresh for all pinned repos, forwarding to
    /// the monitor.
    func refresh() {
        for repoID in pinnedRepoOrder {
            GitMonitor.shared.refreshBranchAndRefs(repoID: repoID)
            GitMonitor.shared.refreshWorkingTree(repoID: repoID)
        }
    }

    /// Requests a PR-status refresh for every pinned repo. Used by the
    /// `git.refresh` IPC so callers (e.g. a Claude PostToolUse hook after
    /// `gh pr create`) can update the badge without waiting for the poll cadence.
    ///
    /// Forwards to the monitor's on-demand `refreshPR`, which evicts the PR cache
    /// + clears network-backoff + forces a refetch — so a PR created against an
    /// already-pushed branch (no local ref change the refs watcher would catch)
    /// is re-fetched here.
    func refreshPR() {
        for repoID in pinnedRepoOrder {
            GitMonitor.shared.refreshPR(repoID: repoID)
        }
    }

    /// Removes a repo from the monitor's `branchGraphDirty` set. Called by the
    /// Branch view-model after a successful branch-graph refetch.
    func clearBranchGraphDirty(repoID: GitRepoID) {
        GitMonitor.shared.clearBranchGraphDirty(repoID: repoID)
    }

    /// The full git status (branch + diff + PR) for the worktree the given pane
    /// lives in, or nil when the pane isn't in a git repo (or it hasn't resolved
    /// yet). Proxies `paneWorktreeRoot[paneID]` → the monitor's per-root status,
    /// so sibling worktrees sharing a `GitRepoID` stay distinguishable.
    func status(forPane paneID: UUID) -> GitRepoStatus? {
        guard let root = paneWorktreeRoot[paneID] else { return nil }
        return GitMonitor.shared.status(forWorktreeRoot: root)
    }

    /// Convenience: the branch name for the worktree the given pane lives in.
    func branch(forPane paneID: UUID) -> String? {
        status(forPane: paneID)?.branchName
    }

    /// Releases every monitor subscription and clears state. Called on Session
    /// close. Idempotent — safe to call twice.
    func teardown() {
        isTornDown = true
        worktreeDetectionTask?.cancel()
        worktreeDetectionTask = nil

        // Release every subscription so the monitor's refcount GC can reclaim
        // repos no other session references.
        for sub in paneSubscriptions.values {
            GitMonitor.shared.unsubscribe(sub.token)
        }
        paneSubscriptions.removeAll()
        if let sub = worktreeInitSubscription {
            GitMonitor.shared.unsubscribe(sub.token)
        }
        worktreeInitSubscription = nil

        paneRepoAssignments.removeAll()
        pinnedRepoOrder.removeAll()
        paneWorktreeRoot.removeAll()
        paneBridgeDirectory.removeAll()
        paneDirectories.removeAll()
        livePanes.removeAll()
        repoRoots.removeAll()
        worktreeRepoID = nil
    }

    // MARK: - Private: Path Helpers

    /// True when `dir` is `root` itself or a descendant of `root`. Centralizes
    /// the path-prefix logic shared by the same-repo fast path and the worktree
    /// parent-collision guard.
    private func pathIsWithin(_ dir: String, _ root: String) -> Bool {
        if dir == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return dir.hasPrefix(prefix)
    }

    /// True when `repoID` is the Session's own worktree repo but `directory` is
    /// OUTSIDE the worktree working tree — i.e. a pane in the PARENT repo (which
    /// shares the worktree's GitRepoID). Such a pane is tracked for lifecycle but
    /// must not become the repo-level status driver. Anchored on
    /// `repoRoots[worktreeRepoID]`, the same git-derived path the same-repo fast
    /// path compares against.
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

    // MARK: - Private: Subscription Management

    /// Ensures `paneID` holds a live monitor subscription for
    /// `(location, worktreeRoot)`, replacing any prior subscription to a
    /// different repo/root. No-ops when the pane is already subscribed to the
    /// exact same target (avoids monitor refcount churn on repeated detects).
    private func subscribePane(_ paneID: UUID, location: RepoLocation, worktreeRoot: String) {
        let repoID = GitRepoID(path: location.commonDir)
        if let existing = paneSubscriptions[paneID] {
            if existing.repoID == repoID && existing.worktreeRoot == worktreeRoot {
                return
            }
            GitMonitor.shared.unsubscribe(existing.token)
        }
        let token = GitMonitor.shared.subscribe(location: location, worktreeRoot: worktreeRoot)
        paneSubscriptions[paneID] = Subscription(token: token, repoID: repoID, worktreeRoot: worktreeRoot)
        applyLatestActivity(to: token)
    }

    /// Ensures the worktree-init subscription (the Session's own `worktreePath`,
    /// with no owning pane) is live for `(location, worktreeRoot)`, replacing a
    /// prior one on a re-detect. Kept apart from `paneSubscriptions` so pane GC
    /// can never release it.
    private func subscribeWorktreeInit(location: RepoLocation, worktreeRoot: String) {
        let repoID = GitRepoID(path: location.commonDir)
        if let existing = worktreeInitSubscription {
            if existing.repoID == repoID && existing.worktreeRoot == worktreeRoot {
                return
            }
            GitMonitor.shared.unsubscribe(existing.token)
        }
        let token = GitMonitor.shared.subscribe(location: location, worktreeRoot: worktreeRoot)
        worktreeInitSubscription = Subscription(token: token, repoID: repoID, worktreeRoot: worktreeRoot)
        applyLatestActivity(to: token)
    }

    /// Pushes the latest reported visible/busy activity to a freshly created
    /// subscription. Without this a pane that subscribes while the session is
    /// already hidden+idle would ride the monitor's default-open gate (visible)
    /// until the next `setActivity` report, leaving the working-tree watcher
    /// running for a session nobody is looking at.
    private func applyLatestActivity(to token: GitMonitor.SubscriptionToken) {
        GitMonitor.shared.setSubscriberActivity(token, visible: latestVisible, busy: latestBusy)
    }

    /// Unpins a repo from this session's display and drops its local mapping.
    /// Subscription release is handled at the pane level (`subscribePane` on a
    /// move, `paneRemoved` on close), so this only cleans the session-owned
    /// display state; the monitor's refcount reclaims the watchers.
    private func unpinRepo(_ repoID: GitRepoID) {
        // Never GC the Session's own worktree repo — it's owned by the Session's
        // worktreePath (the worktree-init subscription), not by any pane, so pane
        // removal/move must not remove it. teardown() clears everything directly.
        guard repoID != worktreeRepoID else { return }

        repoRoots.removeValue(forKey: repoID)
        pinnedRepoOrder.removeAll { $0 == repoID }
        Log.git.debug("Unpinned orphaned repo: \(repoID.path)")
    }

    // MARK: - Private: Detection

    /// Detects the git repo for a directory (through the monitor's cached,
    /// concurrency-capped `detect`), records the session-owned mapping, and
    /// subscribes to `GitMonitor.shared` for the resolved repo/root.
    /// - Parameters:
    ///   - paneID: The pane that triggered detection (nil for worktree-path init).
    ///   - directory: The working directory to detect from.
    ///   - isWorktreeInit: If true, sets worktreeRepoID for sort priority and
    ///     subscribes as the Session's worktree (no owning pane).
    private func detectAndRefresh(paneID: UUID?, directory: String, isWorktreeInit: Bool = false) {
        let task = Task { [weak self] in
            guard let self else { return }

            // A pane-driven detection must not race the worktree-init detection:
            // both target the shared worktree/parent GitRepoID, and the
            // worktree's authoritative subscription must settle first. The
            // worktree-init task must not await itself; the await is a no-op for
            // non-worktree spaces (nil).
            if !isWorktreeInit {
                await self.worktreeDetectionTask?.value
            }
            guard !Task.isCancelled, !self.isTornDown else { return }

            let repo = await GitMonitor.shared.detect(directory: directory)
            guard !Task.isCancelled, !self.isTornDown else { return }

            // If the pane was removed while `detect` was in flight, bail without
            // resurrecting its mapping or leaking a monitor subscription. The
            // worktree-init path (paneID == nil) is unaffected.
            if let paneID, !self.livePanes.contains(paneID) { return }

            guard let repo else {
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
                // Key status by worktree root (unique per branch), not by the
                // shared GitRepoID, so sibling worktrees stay distinguishable.
                self.paneWorktreeRoot[paneID] = repo.workingTree
            }

            // For worktrees this resolves to the worktree's own root, not the
            // main repo — so the same-repo prefix check at
            // paneWorkingDirectoryChanged works for panes scoped to a linked
            // worktree.
            if self.repoRoots[repoID] == nil {
                self.repoRoots[repoID] = repo.workingTree
            }

            // Add to pinned order if new
            if !self.pinnedRepoOrder.contains(repoID) {
                self.pinnedRepoOrder.append(repoID)
                self.sortPinnedRepoOrder()
                Log.git.debug("Pinned new repo: \(repoID.path)")
            }

            // A worktree and its parent repo share one GitRepoID (keyed on
            // --git-common-dir). On restore, a claude pane persisted in the
            // PARENT repo is tracked for lifecycle/pinning but must NOT drive the
            // shared repo-level status — the monitor's first-subscriber-wins
            // keeps the worktree (subscribed first, during init) authoritative.
            let collidesWithParent = !isWorktreeInit
                && self.collidesWithParentWorktree(repoID: repoID, directory: directory)
            if collidesWithParent {
                Log.git.debug("Worktree space: parent-repo pane tracked but not driving repo-level status: \(directory)")
            }

            // Subscribe to the app-global monitor. The worktree-init subscribes
            // for the Session's worktree; a pane subscribes for its own worktree
            // root. A colliding parent pane still subscribes so it gets its own
            // per-root branch — it just isn't the repo-level driver.
            if isWorktreeInit {
                self.subscribeWorktreeInit(location: repo, worktreeRoot: repo.workingTree)
            } else if let paneID {
                self.subscribePane(paneID, location: repo, worktreeRoot: repo.workingTree)
            }
        }

        // Retain the worktree-init task synchronously so pane paths can await it.
        if isWorktreeInit {
            worktreeDetectionTask?.cancel()
            worktreeDetectionTask = task
        }
    }
}
