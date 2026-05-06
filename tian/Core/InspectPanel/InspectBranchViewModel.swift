import Foundation
import Observation

/// Object that exposes the `branchGraphDirty` set and lets the Branch
/// view-model clear a repo's entry after a successful refetch. `SpaceGitContext`
/// is the production conformer; tests can substitute a fake.
///
/// Note: Plan §3 typed `scheduleRefresh(in:)` directly as `SpaceGitContext?`.
/// We narrow it to this protocol so tests can drive the dirty-flag handshake
/// without having to construct a real `SpaceGitContext` (which depends on
/// repo discovery, FSEvents, `RefreshScheduler`, etc.). Production wiring is
/// unchanged — `SpaceGitContext` already exposes both members.
@MainActor
protocol BranchGraphDirtyHost: AnyObject {
    var branchGraphDirty: Set<GitRepoID> { get }
    func clearBranchGraphDirty(repoID: GitRepoID)
}

extension SpaceGitContext: BranchGraphDirtyHost {}

/// View-model for the Inspect panel's Branch tab. Owns its own in-flight
/// `Task` and coordinates with `SpaceGitContext.branchGraphDirty` (FR-T28).
///
/// Unlike the Diff tab, refresh is NOT debounced on file events. It is driven
/// by:
/// - explicit `scheduleRefresh` calls (tab activation, space switch),
/// - `branchGraphDirty` transitions signalled by the host.
///
/// Loading state (FR-T26): `isLoadingInitial` is set true only when the
/// view-model has no graph yet. Subsequent refreshes keep the prior graph
/// visible while the new one fetches.
@MainActor @Observable
final class InspectBranchViewModel {
    private(set) var graph: GitCommitGraph?
    private(set) var isLoadingInitial: Bool = false
    private(set) var lastDirectory: String?

    /// Graph producer. Tests inject a fake; production calls `commitGraph`.
    var graphService: (String) async -> GitCommitGraph? = { dir in
        await GitStatusService.commitGraph(directory: dir)
    }

    private var inFlightTask: Task<Void, Never>?

    init() {}

    /// Asks the view-model to refresh against `directory`. Cancels any
    /// in-flight fetch before starting a new one. A `nil` directory clears
    /// state and cancels.
    ///
    /// On non-cancelled completion, if both `repoID` and `host` are non-nil,
    /// the dirty flag is cleared. Per FR-T28, "dirty" means "the graph needs
    /// a refetch" — once we've finished fetching (even if the result is
    /// `nil` because the directory is no longer a repo), there is nothing
    /// further to do, so we clear the flag on any non-cancelled completion.
    func scheduleRefresh(directory: String?, repoID: GitRepoID?, in host: BranchGraphDirtyHost?) {
        inFlightTask?.cancel()

        guard let directory else {
            inFlightTask = nil
            graph = nil
            lastDirectory = nil
            isLoadingInitial = false
            return
        }

        if graph == nil {
            isLoadingInitial = true
        }

        let service = graphService
        let task = Task { [weak self, weak host] in
            let result = await service(directory)
            if Task.isCancelled { return }
            guard let self else { return }
            self.graph = result
            self.lastDirectory = directory
            self.isLoadingInitial = false
            if let repoID, let host {
                host.clearBranchGraphDirty(repoID: repoID)
            }
        }
        inFlightTask = task
    }

    /// Tears down the in-flight task. Called on space switch / workspace close.
    func teardown() {
        inFlightTask?.cancel()
        inFlightTask = nil
    }
}
