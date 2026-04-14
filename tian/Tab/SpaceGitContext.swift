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

    /// Maps each pane ID to its detected repo (nil entry = not yet detected or not in a repo).
    private(set) var paneRepoAssignments: [UUID: GitRepoID] = [:]

    /// Ordered list of pinned repos for display. First is worktree-derived repo if applicable.
    private(set) var pinnedRepoOrder: [GitRepoID] = []

    // MARK: - Private State

    /// The repo ID derived from worktreePath (if set). Always sorted first in pinnedRepoOrder.
    private var worktreeRepoID: GitRepoID?

    /// Tracks in-flight refresh tasks per repo for cancellation on rapid re-triggers.
    private var inFlightTasks: [GitRepoID: Task<Void, Never>] = [:]

    /// Last-known working directory per pane.
    private var paneDirectories: [UUID: String] = [:]

    /// A directory we know maps to a specific repo, used for branch refresh.
    private var repoDirectories: [GitRepoID: String] = [:]

    /// Root working tree path per repo, used for same-repo prefix checks.
    private var repoRoots: [GitRepoID: String] = [:]

    /// PR status cache with 60-second TTL.
    private let prCache = PRStatusCache()

    /// Tracks in-flight PR fetch tasks per repo for cancellation.
    private var prFetchTasks: [GitRepoID: Task<Void, Never>] = [:]

    /// Active FSEvents watchers per repo.
    private var watchers: [GitRepoID: GitRepoWatcher] = [:]

    /// Git repo info needed for watcher creation (gitDir, commonDir).
    private var repoInfo: [GitRepoID: (gitDir: String, commonDir: String)] = [:]

    // MARK: - Public Computed

    /// Number of active FSEvents watchers. Exposed for testing.
    var activeWatcherCount: Int { watchers.count }

    // MARK: - Init

    /// Creates a git context for a Space.
    /// - Parameter worktreePath: If non-nil, eagerly detects the repo from this path.
    init(worktreePath: URL?) {
        if let worktreePath {
            let path = worktreePath.path
            Task { [weak self] in
                await self?.detectAndRefresh(paneID: nil, directory: path, isWorktreeInit: true)
            }
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
           newDirectory == repoRoot || newDirectory.hasPrefix(repoRoot.hasSuffix("/") ? repoRoot : repoRoot + "/") {
            // Same repo — just refresh branch info without re-detecting
            refreshRepo(repoID: existingRepoID, directory: newDirectory)
            repoDirectories[existingRepoID] = newDirectory
            return
        }

        // Detect new repo — pane may be moving to a different repo or a non-git dir
        Task { [weak self] in
            guard let self else { return }

            let repo = await GitStatusService.detectRepo(directory: newDirectory)

            if let repo {
                let newRepoID = GitRepoID(path: repo.commonDir)

                // Read current assignment AFTER await to avoid stale capture
                // (rapid calls could have reassigned pane to an intermediate repo)
                let previousRepoID = self.paneRepoAssignments[paneID]

                // Update pane assignment
                self.paneRepoAssignments[paneID] = newRepoID
                self.repoDirectories[newRepoID] = newDirectory
                self.repoInfo[newRepoID] = (gitDir: repo.gitDir, commonDir: repo.commonDir)
                if self.repoRoots[newRepoID] == nil {
                    let commonDirURL = URL(filePath: repo.commonDir)
                    self.repoRoots[newRepoID] = commonDirURL.deletingLastPathComponent().path
                }

                // Add new repo if not already pinned
                if !self.pinnedRepoOrder.contains(newRepoID) {
                    self.pinnedRepoOrder.append(newRepoID)
                    self.sortPinnedRepoOrder()
                    self.startWatcher(repoID: newRepoID, gitDir: repo.gitDir, commonDir: repo.commonDir, workingDirectory: newDirectory)
                    Log.git.debug("Pinned new repo: \(newRepoID.path)")
                }

                self.refreshRepo(repoID: newRepoID, directory: newDirectory)

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
            refreshRepo(repoID: repoID, directory: directory)
        }
    }

    /// Cancels all in-flight tasks and clears state. Called on Space close.
    func teardown() {
        for task in inFlightTasks.values { task.cancel() }
        inFlightTasks.removeAll()
        for task in prFetchTasks.values { task.cancel() }
        prFetchTasks.removeAll()
        repoStatuses.removeAll()
        paneRepoAssignments.removeAll()
        pinnedRepoOrder.removeAll()
        paneDirectories.removeAll()
        repoDirectories.removeAll()
        repoRoots.removeAll()
        for watcher in watchers.values { watcher.stop() }
        watchers.removeAll()
        prCache.evictAll()
        repoInfo.removeAll()
    }

    // MARK: - Private

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
        inFlightTasks[repoID]?.cancel()
        inFlightTasks.removeValue(forKey: repoID)
        prFetchTasks[repoID]?.cancel()
        prFetchTasks.removeValue(forKey: repoID)
        repoStatuses.removeValue(forKey: repoID)
        repoDirectories.removeValue(forKey: repoID)
        repoRoots.removeValue(forKey: repoID)
        repoInfo.removeValue(forKey: repoID)
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
        Task { [weak self] in
            guard let self else { return }

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
            self.repoDirectories[repoID] = directory

            // Store repo root (parent of .git) for same-repo prefix checks
            if self.repoRoots[repoID] == nil {
                // commonDir is the .git dir; its parent is the working tree root
                let commonDirURL = URL(filePath: repo.commonDir)
                self.repoRoots[repoID] = commonDirURL.deletingLastPathComponent().path
            }

            // Add to pinned order if new
            if !self.pinnedRepoOrder.contains(repoID) {
                self.pinnedRepoOrder.append(repoID)
                self.sortPinnedRepoOrder()
                Log.git.debug("Pinned new repo: \(repoID.path)")
            }

            self.repoInfo[repoID] = (gitDir: repo.gitDir, commonDir: repo.commonDir)
            self.startWatcher(repoID: repoID, gitDir: repo.gitDir, commonDir: repo.commonDir, workingDirectory: directory)

            self.refreshRepo(repoID: repoID, directory: directory)
        }
    }

    /// Refreshes branch and diff status for a specific repo, with in-flight cancellation.
    private func refreshRepo(repoID: GitRepoID, directory: String) {
        inFlightTasks[repoID]?.cancel()
        prFetchTasks[repoID]?.cancel()

        let task = Task { [weak self] in
            async let branchResult = GitStatusService.currentBranch(directory: directory)
            async let diffResult = GitStatusService.diffStatus(directory: directory)

            let branch = await branchResult
            let diff = await diffResult

            guard !Task.isCancelled else { return }
            guard let self else { return }

            // Check PR cache
            var prStatus: PRStatus? = nil
            if let branchName = branch?.name {
                let cacheResult = self.prCache.get(repoID: repoID, branch: branchName)
                switch cacheResult {
                case .hit(let cached):
                    prStatus = cached
                case .miss:
                    if self.prCache.markPending(repoID: repoID, branch: branchName) {
                        let prTask = Task { [weak self] in
                            defer { self?.prCache.clearPending(repoID: repoID, branch: branchName) }
                            let fetched = await GitStatusService.fetchPRStatus(
                                directory: directory,
                                branch: branchName
                            )
                            guard !Task.isCancelled else { return }
                            guard let self else { return }
                            self.prCache.set(repoID: repoID, branch: branchName, status: fetched)
                            // Only update if branch still matches (avoid stale overwrite)
                            if let current = self.repoStatuses[repoID],
                               current.branchName == branchName {
                                var updated = current
                                updated.prStatus = fetched
                                self.repoStatuses[repoID] = updated
                            }
                            self.prFetchTasks.removeValue(forKey: repoID)
                        }
                        self.prFetchTasks[repoID] = prTask
                    }
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

            self.repoStatuses[repoID] = status
            self.inFlightTasks.removeValue(forKey: repoID)
        }

        inFlightTasks[repoID] = task
    }

    // MARK: - Watcher Management

    private func startWatcher(repoID: GitRepoID, gitDir: String, commonDir: String, workingDirectory: String) {
        // Don't start a duplicate watcher if one already exists
        guard watchers[repoID] == nil else { return }

        let watchPaths = GitRepoWatcher.resolveWatchPaths(
            gitDir: gitDir,
            commonDir: commonDir,
            workingDirectory: workingDirectory
        )

        let watcher = GitRepoWatcher(watchPaths: watchPaths) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let dir = self.repoDirectories[repoID] else { return }
                self.refreshRepo(repoID: repoID, directory: dir)
            }
        }

        watchers[repoID] = watcher
    }

    private func stopWatcher(repoID: GitRepoID) {
        watchers[repoID]?.stop()
        watchers.removeValue(forKey: repoID)
    }
}
