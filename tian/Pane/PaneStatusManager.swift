import Foundation
import Observation
import OSLog

struct PaneStatus {
    let label: String
    /// Monotonic write sequence. Strictly increases with every `setStatus`
    /// call, so `latestStatus` has a total order even when two writes land
    /// inside the same `Date()` tick (which `Date()` does not guarantee).
    let sequence: UInt64
}

/// Manages ephemeral status indicators for panes (e.g., "Thinking...").
/// Status is not persisted across app restarts.
@MainActor @Observable
final class PaneStatusManager {
    static let shared = PaneStatusManager()

    private(set) var statuses: [UUID: PaneStatus] = [:]
    private(set) var sessionStates: [UUID: ClaudeSessionState] = [:]

    private var nextSequence: UInt64 = 0

    init() {}

    func setStatus(paneID: UUID, label: String) {
        nextSequence += 1
        let status = PaneStatus(label: label, sequence: nextSequence)
        statuses[paneID] = status
        owner(of: paneID)?.paneStatuses[paneID] = status   // dual-write
    }

    /// Clears both the free-form status label and session state for the pane.
    func clearStatus(paneID: UUID) {
        statuses.removeValue(forKey: paneID)
        sessionStates.removeValue(forKey: paneID)
        if let pvm = owner(of: paneID) {
            pvm.paneStatuses.removeValue(forKey: paneID)
            pvm.sessionStates.removeValue(forKey: paneID)
        }
    }

    func clearAll(for paneIDs: Set<UUID>) {
        for id in paneIDs {
            statuses.removeValue(forKey: id)
            sessionStates.removeValue(forKey: id)
            if let pvm = owner(of: id) {
                pvm.paneStatuses.removeValue(forKey: id)
                pvm.sessionStates.removeValue(forKey: id)
            }
        }
    }

    /// Returns the most recently updated status among all panes in all tabs of the space.
    func latestStatus(in space: SpaceModel) -> PaneStatus? {
        var latest: PaneStatus?
        for tab in space.allTabs {
            for paneID in tab.paneViewModel.splitTree.allLeaves() {
                guard let status = statuses[paneID] else { continue }
                if latest == nil || status.sequence > latest!.sequence {
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
        owner(of: paneID)?.sessionStates[paneID] = state   // dual-write
        Log.ipc.debug("Session state changed for pane \(paneID): \(oldState?.rawValue ?? "nil") → \(state.rawValue)")
    }

    func clearSessionState(paneID: UUID) {
        sessionStates.removeValue(forKey: paneID)
        owner(of: paneID)?.sessionStates.removeValue(forKey: paneID)
    }

    func sessionState(for paneID: UUID) -> ClaudeSessionState? {
        sessionStates[paneID]
    }

    /// Whether any pane under this tab is currently in the given state.
    func hasSessionState(_ state: ClaudeSessionState, in tab: TabModel) -> Bool {
        for paneID in tab.paneViewModel.splitTree.allLeaves() {
            if sessionStates[paneID] == state { return true }
        }
        return false
    }

    /// Returns all (paneID, state) pairs in the space with non-nil, non-inactive state,
    /// sorted by priority (highest first).
    func sessionStates(in space: SpaceModel) -> [(paneID: UUID, state: ClaudeSessionState)] {
        var result: [(paneID: UUID, state: ClaudeSessionState)] = []
        for tab in space.allTabs {
            for paneID in tab.paneViewModel.splitTree.allLeaves() {
                guard let state = sessionStates[paneID],
                      state != .inactive else { continue }
                result.append((paneID: paneID, state: state))
            }
        }
        return result.sorted { $0.state > $1.state }
    }

    // MARK: - Pane Registry

    private var ownersByPane: [UUID: WeakBox<PaneViewModel>] = [:]

    /// Register a pane → its owning PVM so writes can mirror per-pane.
    func registerPane(_ paneID: UUID, owner: PaneViewModel) {
        ownersByPane[paneID] = WeakBox(owner)
    }

    /// Unregister a pane (e.g., on close or PVM deinit).
    func unregisterPane(_ paneID: UUID) {
        ownersByPane.removeValue(forKey: paneID)
    }

    private func owner(of paneID: UUID) -> PaneViewModel? {
        ownersByPane[paneID]?.value
    }
}

private final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
