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
    private(set) var backgroundActivities: [UUID: [BackgroundActivity]] = [:]

    private var nextSequence: UInt64 = 0

    /// Repeating sweep that ages out stale background activities (see
    /// `startStalenessPruning`). `nil` until started at app launch.
    private var pruningTask: Task<Void, Never>?

    /// How often `pruneStaleActivities` runs. Well under `stalenessTTL` so an
    /// aged-out entry is dropped within one interval of crossing the threshold.
    private static let pruneInterval: Duration = .seconds(30)

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

    /// Clears the free-form status label, session state, last prompt, and any
    /// outstanding background activities for the pane (e.g. on pane close).
    func clearStatus(paneID: UUID) {
        statuses.removeValue(forKey: paneID)
        sessionStates.removeValue(forKey: paneID)
        lastPrompts.removeValue(forKey: paneID)
        backgroundActivities.removeValue(forKey: paneID)
        if let pvm = owner(of: paneID) {
            pvm.paneStatuses.removeValue(forKey: paneID)
            pvm.sessionStates.removeValue(forKey: paneID)
            pvm.paneLastPrompts.removeValue(forKey: paneID)
            pvm.paneBackgroundActivities.removeValue(forKey: paneID)
        }
    }

    func clearAll(for paneIDs: Set<UUID>) {
        for id in paneIDs {
            statuses.removeValue(forKey: id)
            sessionStates.removeValue(forKey: id)
            lastPrompts.removeValue(forKey: id)
            backgroundActivities.removeValue(forKey: id)
            if let pvm = owner(of: id) {
                pvm.paneStatuses.removeValue(forKey: id)
                pvm.sessionStates.removeValue(forKey: id)
                pvm.paneLastPrompts.removeValue(forKey: id)
                pvm.paneBackgroundActivities.removeValue(forKey: id)
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

    // MARK: - Background Activity

    /// Replaces the whole background-activity set for a pane from Claude's
    /// `background_tasks` snapshot — the sole writer of background activity.
    /// Mirrors to the owning PVM via the pane registry, exactly like
    /// `setSessionState` / `setStatus`. An empty array clears the pane's entry
    /// entirely, so a pane with no outstanding work reads as absent rather than an
    /// empty array.
    func syncActivities(paneID: UUID, _ activities: [BackgroundActivity]) {
        if activities.isEmpty {
            backgroundActivities.removeValue(forKey: paneID)
            owner(of: paneID)?.paneBackgroundActivities.removeValue(forKey: paneID)   // dual-write
        } else {
            backgroundActivities[paneID] = activities
            owner(of: paneID)?.paneBackgroundActivities[paneID] = activities   // dual-write
        }
    }

    /// Begins the periodic staleness sweep. Idempotent (a second call is a no-op)
    /// and started once from the app delegate at launch, mirroring
    /// `SystemMonitor.start()`.
    func startStalenessPruning() {
        guard pruningTask == nil else { return }
        pruningTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pruneInterval)
                guard !Task.isCancelled else { return }
                self?.pruneStaleActivities()
            }
        }
    }

    /// Drops background activities aged past `BackgroundActivity.stalenessTTL`
    /// from every pane, mirroring the removal to each owning PVM (same dual-write
    /// as `syncActivities`). This is what actually lifts the `.busy` floor once
    /// Claude stops syncing: `background_tasks` only arrives on Stop/SubagentStop,
    /// so a session that ends/orphans/idles never sends a shrinking snapshot, and
    /// without this timer the stale entry would linger until an incidental
    /// re-render happened to re-read `isStale`. A pane whose activities all age
    /// out has its entry removed entirely, matching `syncActivities([])`.
    func pruneStaleActivities() {
        for (paneID, activities) in backgroundActivities {
            let fresh = activities.filter { !$0.isStale }
            guard fresh.count != activities.count else { continue }   // nothing aged out
            if fresh.isEmpty {
                backgroundActivities.removeValue(forKey: paneID)
                owner(of: paneID)?.paneBackgroundActivities.removeValue(forKey: paneID)   // dual-write
            } else {
                backgroundActivities[paneID] = fresh
                owner(of: paneID)?.paneBackgroundActivities[paneID] = fresh   // dual-write
            }
        }
    }

    // MARK: - Pane Registry

    private var ownersByPane: [UUID: WeakBox<PaneViewModel>] = [:]

    /// Register a pane → its owning PVM so writes can mirror per-pane.
    func registerPane(_ paneID: UUID, owner: PaneViewModel) {
        ownersByPane[paneID] = WeakBox(owner)
    }

    /// The area (Claude vs terminal) of the pane owning the surface with this
    /// surface id, or nil when no registered pane owns it. Resolves surface id →
    /// owning pane (surface ids differ from leaf pane ids), then reports that
    /// pane's kind — lets notification routing tell a Claude surface apart from a
    /// terminal one (to suppress the raw OSC firehose for Claude panes in GhosttyApp).
    func paneKind(forSurfaceID surfaceID: UUID) -> PaneKind? {
        for box in ownersByPane.values {
            if let pvm = box.value, pvm.paneID(forSurfaceID: surfaceID) != nil {
                return pvm.kind
            }
        }
        return nil
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
