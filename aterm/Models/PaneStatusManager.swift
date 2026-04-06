import Foundation
import Observation

struct PaneStatus {
    let label: String
    let updatedAt: Date
}

/// Manages ephemeral status indicators for panes (e.g., "Thinking...").
/// Status is not persisted across app restarts.
@MainActor @Observable
final class PaneStatusManager {
    static let shared = PaneStatusManager()

    private(set) var statuses: [UUID: PaneStatus] = [:]

    init() {}

    func setStatus(paneID: UUID, label: String) {
        statuses[paneID] = PaneStatus(label: label, updatedAt: Date())
    }

    func clearStatus(paneID: UUID) {
        statuses.removeValue(forKey: paneID)
    }

    func clearAll(for paneIDs: Set<UUID>) {
        for id in paneIDs {
            statuses.removeValue(forKey: id)
        }
    }

    /// Returns the most recently updated status among all panes in all tabs of the space.
    func latestStatus(in space: SpaceModel) -> PaneStatus? {
        var latest: PaneStatus?
        for tab in space.tabs {
            for paneID in tab.paneViewModel.splitTree.allLeaves() {
                guard let status = statuses[paneID] else { continue }
                if latest == nil || status.updatedAt > latest!.updatedAt {
                    latest = status
                }
            }
        }
        return latest
    }
}
