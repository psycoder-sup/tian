import Foundation
import Observation

/// View-model for the Inspect panel's Diff tab. Owns its own scheduler
/// bucket (independent of `SpaceGitContext.refreshScheduler`) so dev-server
/// churn cannot induce `git diff HEAD` storms.
///
/// FR-T18 contract:
/// - Trailing debounce (≥500 ms) coalesces bursts of `scheduleRefresh`.
/// - At most one in-flight `unifiedDiff` call; a new refresh cancels the
///   prior task before issuing a new one.
///
/// FR-T11 contract:
/// - After a refresh, callers can prune their per-file collapse map by
///   wiring `onFilesRefreshed`. Files still present in the new diff
///   keep their collapse flag; files that disappear get pruned.
@MainActor @Observable
final class InspectDiffViewModel {
    private(set) var files: [GitFileDiff] = []
    private(set) var isLoadingInitial: Bool = false
    private(set) var lastDirectory: String?

    /// Coalescing trailing debounce window (FR-T18). 500 ms.
    static let debounce: Duration = .milliseconds(500)

    /// Diff producer. Tests inject a fake; production calls `unifiedDiff`.
    var diffService: (String) async -> [GitFileDiff]

    /// Invoked after each successful refresh with the set of file paths
    /// in the new diff. The caller prunes `InspectTabState.diffCollapse`
    /// accordingly.
    var onFilesRefreshed: ((Set<String>) -> Void)?

    private var inFlightTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let debounceWindow: Duration

    init(
        debounceWindow: Duration = InspectDiffViewModel.debounce,
        diffService: @escaping (String) async -> [GitFileDiff] = { dir in
            await GitStatusService.unifiedDiff(directory: dir)
        }
    ) {
        self.debounceWindow = debounceWindow
        self.diffService = diffService
    }

    /// Asks the view-model to refresh against `directory`. Coalesces calls
    /// inside the debounce window; cancels any in-flight diff before
    /// starting a new one. A `nil` directory clears state and cancels.
    func scheduleRefresh(directory: String?) {
        debounceTask?.cancel()
        debounceTask = nil

        guard let directory else {
            inFlightTask?.cancel()
            inFlightTask = nil
            files = []
            lastDirectory = nil
            isLoadingInitial = false
            return
        }

        let window = debounceWindow
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: window)
            if Task.isCancelled { return }
            guard let self else { return }
            await self.runRefresh(directory: directory)
        }
    }

    /// Tears down debounce + in-flight task. Called on space switch /
    /// workspace close.
    func teardown() {
        debounceTask?.cancel()
        inFlightTask?.cancel()
        debounceTask = nil
        inFlightTask = nil
    }

    // MARK: - Internals

    private func runRefresh(directory: String) async {
        // If the debounce task that led here was cancelled, don't spawn a
        // child task that would write stale state after a newer debounce fires.
        if Task.isCancelled { return }

        // Cancel any prior in-flight diff before issuing a new one.
        inFlightTask?.cancel()

        if files.isEmpty {
            isLoadingInitial = true
        }

        let service = diffService
        let task = Task { [weak self] in
            let result = await service(directory)
            // Drop the result on cancellation so a stale call can't clobber
            // a newer refresh's state.
            if Task.isCancelled { return }
            guard let self else { return }
            self.files = result
            self.lastDirectory = directory
            self.isLoadingInitial = false
            self.onFilesRefreshed?(Set(result.map { $0.path }))
        }
        inFlightTask = task
        await task.value
        // Clear the slot only if it still points at this task — a newer
        // refresh may have replaced it already.
        if inFlightTask == task {
            inFlightTask = nil
        }
    }
}
