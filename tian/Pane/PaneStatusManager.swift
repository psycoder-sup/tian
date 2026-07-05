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
    private(set) var lastPrompts: [UUID: String] = [:]

    private var nextSequence: UInt64 = 0

    init() {}

    func setStatus(paneID: UUID, label: String) {
        nextSequence += 1
        let status = PaneStatus(label: label, sequence: nextSequence)
        statuses[paneID] = status
        owner(of: paneID)?.paneStatuses[paneID] = status   // dual-write
    }

    /// Records the latest user prompt typed into a pane's Claude session.
    /// Plain overwrite — no sequence counter, since the prompt is scoped to a
    /// single Claude pane rather than aggregated across panes.
    func setLastPrompt(paneID: UUID, text: String) {
        lastPrompts[paneID] = text
        owner(of: paneID)?.paneLastPrompts[paneID] = text   // dual-write
    }

    /// Clears the free-form status label, session state, and last prompt for the pane.
    func clearStatus(paneID: UUID) {
        statuses.removeValue(forKey: paneID)
        sessionStates.removeValue(forKey: paneID)
        lastPrompts.removeValue(forKey: paneID)
        if let pvm = owner(of: paneID) {
            pvm.paneStatuses.removeValue(forKey: paneID)
            pvm.sessionStates.removeValue(forKey: paneID)
            pvm.paneLastPrompts.removeValue(forKey: paneID)
        }
    }

    func clearAll(for paneIDs: Set<UUID>) {
        for id in paneIDs {
            statuses.removeValue(forKey: id)
            sessionStates.removeValue(forKey: id)
            lastPrompts.removeValue(forKey: id)
            if let pvm = owner(of: id) {
                pvm.paneStatuses.removeValue(forKey: id)
                pvm.sessionStates.removeValue(forKey: id)
                pvm.paneLastPrompts.removeValue(forKey: id)
            }
        }
    }

    /// Returns the most recently updated status among all panes in the session.
    func latestStatus(in session: Session) -> PaneStatus? {
        var latest: PaneStatus?
        for paneID in session.allPaneIDs {
            guard let status = statuses[paneID] else { continue }
            if latest == nil || status.sequence > latest!.sequence {
                latest = status
            }
        }
        return latest
    }

    // MARK: - Session State

    func setSessionState(paneID: UUID, state: ClaudeSessionState) {
        let oldState = sessionStates[paneID]
        // A clean turn-end must not silently downgrade a pending prompt or a
        // recorded failure (see ClaudeSessionState.canReplace).
        guard state.canReplace(oldState) else {
            Log.ipc.debug("Session state for pane \(paneID): \(state.rawValue) suppressed (current \(oldState?.rawValue ?? "nil") outranks it)")
            return
        }
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

    /// The highest-priority (needsAttention first) non-inactive session among
    /// the session's panes — both the winning pane and its state — or nil when no
    /// pane has an active session. Single source of truth for the sidebar row
    /// (dot + which pane drives its branch/status).
    func topSessionPane(in session: Session) -> (paneID: UUID, state: ClaudeSessionState)? {
        var top: (paneID: UUID, state: ClaudeSessionState)?
        for paneID in session.allPaneIDs {
            guard let state = sessionStates[paneID], state != .inactive else { continue }
            // `>` compares by priority (needsAttention is greatest).
            if top == nil || state > top!.state {
                top = (paneID, state)
            }
        }
        return top
    }

    /// The highest-priority non-inactive session state among the session's panes,
    /// or nil when no pane has an active session. Drives the single dot on the
    /// sidebar row.
    func aggregateSessionState(in session: Session) -> ClaudeSessionState? {
        topSessionPane(in: session)?.state
    }

    /// Whether any pane under this session is currently in the given state.
    func hasSessionState(_ state: ClaudeSessionState, in session: Session) -> Bool {
        session.allPaneIDs.contains { sessionStates[$0] == state }
    }

    /// Returns all (paneID, state) pairs in the session with non-nil, non-inactive
    /// state, sorted by priority (highest first).
    func sessionStates(in session: Session) -> [(paneID: UUID, state: ClaudeSessionState)] {
        var result: [(paneID: UUID, state: ClaudeSessionState)] = []
        for paneID in session.allPaneIDs {
            guard let state = sessionStates[paneID],
                  state != .inactive else { continue }
            result.append((paneID: paneID, state: state))
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
        guard let box = ownersByPane[paneID] else { return nil }
        if let value = box.value {
            return value
        }
        // The PVM was freed without calling unregisterPane (e.g. test scenarios).
        // Drop the dead entry to prevent registry bloat over a long session.
        ownersByPane.removeValue(forKey: paneID)
        return nil
    }
}

private final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
