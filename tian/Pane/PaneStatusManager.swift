import Foundation
import Observation
import OSLog

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
    private(set) var sessionStates: [UUID: ClaudeSessionState] = [:]

    init() {}

    func setStatus(paneID: UUID, label: String) {
        statuses[paneID] = PaneStatus(label: label, updatedAt: Date())
    }

    /// Clears both the free-form status label and session state for the pane.
    func clearStatus(paneID: UUID) {
        statuses.removeValue(forKey: paneID)
        sessionStates.removeValue(forKey: paneID)
    }

    func clearAll(for paneIDs: Set<UUID>) {
        for id in paneIDs {
            statuses.removeValue(forKey: id)
            sessionStates.removeValue(forKey: id)
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

    // MARK: - Session State

    func setSessionState(paneID: UUID, state: ClaudeSessionState) {
        let oldState = sessionStates[paneID]
        sessionStates[paneID] = state
        Log.ipc.debug("Session state changed for pane \(paneID): \(oldState?.rawValue ?? "nil") → \(state.rawValue)")
    }

    func clearSessionState(paneID: UUID) {
        sessionStates.removeValue(forKey: paneID)
    }

    func sessionState(for paneID: UUID) -> ClaudeSessionState? {
        sessionStates[paneID]
    }

    /// Returns all (paneID, state) pairs in the space with non-nil, non-inactive state,
    /// sorted by priority (highest first).
    func sessionStates(in space: SpaceModel) -> [(paneID: UUID, state: ClaudeSessionState)] {
        var result: [(paneID: UUID, state: ClaudeSessionState)] = []
        for tab in space.tabs {
            for paneID in tab.paneViewModel.splitTree.allLeaves() {
                guard let state = sessionStates[paneID],
                      state != .inactive else { continue }
                result.append((paneID: paneID, state: state))
            }
        }
        return result.sorted { $0.state > $1.state }
    }
}
