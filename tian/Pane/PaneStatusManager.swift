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
    /// The lifecycle-seen mark goes too — a closed pane must leave nothing behind
    /// for a pane id to inherit.
    func clearStatus(paneID: UUID) {
        statuses.removeValue(forKey: paneID)
        sessionStates.removeValue(forKey: paneID)
        lastPrompts.removeValue(forKey: paneID)
        backgroundActivities.removeValue(forKey: paneID)
        lifecycleSeen.remove(paneID)
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
            lifecycleSeen.remove(id)
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

    /// Panes that have ever produced a lifecycle event (`beginActivity`).
    ///
    /// Pure graceful-degradation bookkeeping: Claude Code versions before the
    /// `SubagentStart` hook never emit one, so for those panes the snapshot's
    /// `.agent` entries stay the only agent signal there is and must keep working
    /// exactly as they did. Nothing in the write paths *needs* this flag (a pane
    /// with no lifecycle events simply has no `.lifecycle` entries to preserve or
    /// drop) — it exists so callers can tell "no subagents running" apart from
    /// "this CLI can't tell us about subagents".
    private var lifecycleSeen: Set<UUID> = []

    /// Records the start of a subagent or teammate reported by a lifecycle hook.
    ///
    /// This is the feed that fixes the stuck badge: `background_tasks` only ever
    /// mentions *backgrounded* work, so a foreground subagent was previously
    /// invisible on the way in and un-removable on the way out. A lifecycle entry
    /// is owned by its start/stop pair — snapshots may not evict it.
    ///
    /// Upsert by id: a repeated start for the same id (hook replay, a refreshed
    /// label) updates in place and keeps the entry's position, so the badge doesn't
    /// double-count and the list doesn't reshuffle.
    func beginActivity(paneID: UUID, _ activity: BackgroundActivity) {
        lifecycleSeen.insert(paneID)

        var activities = backgroundActivities[paneID] ?? []
        if let index = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[index] = activity
        } else {
            activities.append(activity)
        }
        write(paneID: paneID, activities)
    }

    /// Ends the lifecycle activity with this id — the authoritative removal that a
    /// TTL sweep used to have to guess at.
    ///
    /// Silent when the id is unknown: hooks race (a stop can land after a
    /// turn-end reconcile already cleared the entry), older CLIs emit stops for
    /// starts they never sent, and a snapshot may have dropped the entry first.
    /// None of that is an error — "gone" is the desired state either way.
    func endActivity(paneID: UUID, id: String) {
        guard var activities = backgroundActivities[paneID] else { return }
        let before = activities.count
        activities.removeAll { $0.id == id }
        guard activities.count != before else { return }
        write(paneID: paneID, activities)
    }

    /// Ends the first activity carrying this label — the fallback for teammate
    /// events, which identify the teammate by name and carry no stable id.
    /// Same silent no-op contract as the id-keyed overload.
    func endActivity(paneID: UUID, label: String) {
        guard var activities = backgroundActivities[paneID] else { return }
        guard let index = activities.firstIndex(where: { $0.label == label }) else { return }
        activities.remove(at: index)
        write(paneID: paneID, activities)
    }

    /// Whether this pane has ever reported a lifecycle event, i.e. whether the
    /// Claude Code driving it speaks `SubagentStart`. False means we're on the
    /// snapshot-only fallback path and must not infer anything from the *absence*
    /// of lifecycle entries.
    func hasSeenLifecycleEvents(paneID: UUID) -> Bool {
        lifecycleSeen.contains(paneID)
    }

    /// Applies Claude's `background_tasks` snapshot — a *partial* replace, not a
    /// whole-set one.
    ///
    /// The two feeds own disjoint ground truth: the snapshot is authoritative for
    /// backgrounded bash/tasks, the lifecycle hooks for subagents and teammates. So
    /// a snapshot replaces only the `.snapshot`-sourced entries and leaves every
    /// `.lifecycle` entry standing — otherwise a mid-turn snapshot (which never
    /// mentions foreground subagents) would silently erase the running agents.
    ///
    /// Collisions go to lifecycle: once a subagent gets backgrounded it shows up in
    /// *both* feeds under the same id, and counting it twice is exactly the badge
    /// inflation this whole change exists to kill.
    ///
    /// An emptied pane loses its dictionary entry entirely, so "no outstanding
    /// work" reads as absent rather than as an empty array.
    func syncActivities(paneID: UUID, _ snapshot: [BackgroundActivity]) {
        let existing = backgroundActivities[paneID] ?? []
        let live = existing.filter { $0.source == .lifecycle }
        let liveIDs = Set(live.map(\.id))
        write(paneID: paneID, live + snapshot.filter { !liveIDs.contains($0.id) })
    }

    /// The authoritative turn-end reconcile, driven by the `Stop` hook.
    ///
    /// Only *subagents* are turn-scoped: Claude finishing its turn is proof that no
    /// foreground `.agent` of that turn is still alive, so every `.lifecycle`+`.agent`
    /// entry is dropped. A subagent that genuinely kept running in the background
    /// isn't lost by this — it appears in the `Stop` payload's own `background_tasks`,
    /// so it survives as a snapshot entry, which is the feed that truthfully owns it.
    ///
    /// Teammates are *not* turn-scoped. An agent-team teammate keeps working across
    /// the main agent's turn boundaries, so `Stop` says nothing about it; retiring it
    /// here would make the team badge vanish under a still-running team and would
    /// leave the `TeammateIdle` hook — which exists precisely to retire teammates —
    /// with nothing to retire. So `.lifecycle`+`.teammate` entries survive, kept in
    /// their existing order ahead of the snapshot exactly as `syncActivities` orders
    /// `live + snapshot`, and are deduped against it the same way: a teammate whose id
    /// also shows up in the snapshot counts once, and lifecycle wins.
    func reconcileActivities(paneID: UUID, _ snapshot: [BackgroundActivity]) {
        let existing = backgroundActivities[paneID] ?? []
        let live = existing.filter { $0.source == .lifecycle && $0.kind == .teammate }
        let liveIDs = Set(live.map(\.id))
        write(paneID: paneID, live + snapshot.filter { !liveIDs.contains($0.id) })
    }

    /// Drops the pane's `.lifecycle`+`.agent` entries, keeping teammates and snapshots.
    ///
    /// Called on `UserPromptSubmit` and on the idle notification — the two moments
    /// that prove the previous turn is over even when no `Stop` hook ever fired.
    /// That gap is the actual stuck-badge bug: ESC-cancelling a turn kills its
    /// subagents *without* a `Stop`, so nothing would otherwise retire them until the
    /// TTL. Only subagents are turn-scoped, though: a teammate outlives the turn that
    /// spawned it (only `TeammateIdle`, session end or the TTL backstop retires one),
    /// and so does a backgrounded bash command — which is why teammate and snapshot
    /// entries both stay.
    func resetLifecycleActivities(paneID: UUID) {
        guard let activities = backgroundActivities[paneID] else { return }
        let kept = activities.filter { !($0.source == .lifecycle && $0.kind == .agent) }
        guard kept.count != activities.count else { return }
        write(paneID: paneID, kept)
    }

    /// Wipes every background activity for the pane, whatever its source or kind.
    ///
    /// The guaranteed-teardown op behind the `SessionEnd` hook: a `/clear` (or an
    /// exiting CLI) ends the Claude *session* while the pane lives on, so everything
    /// that session spawned — subagents, teammates, backgrounded bash — is provably
    /// gone. It has to be its own operation rather than a `reconcileActivities([])`,
    /// because reconcile now deliberately preserves teammates across turn ends and so
    /// can no longer express "nothing survives".
    ///
    /// Distinct from `clearStatus(paneID:)`, which is the broader pane-close teardown
    /// (status label, session state, last prompt, lifecycle mark) — here the pane
    /// itself is still very much alive.
    func clearActivities(paneID: UUID) {
        guard backgroundActivities[paneID] != nil else { return }
        write(paneID: paneID, [])
    }

    /// Single write path for the pane's activity list: stores (or, when empty,
    /// removes) and mirrors the same to the owning PVM via the pane registry,
    /// exactly like `setSessionState` / `setStatus`.
    private func write(paneID: UUID, _ activities: [BackgroundActivity]) {
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

    /// Drops background activities aged past their own TTL from every pane,
    /// mirroring the removal to each owning PVM (same dual-write as
    /// `syncActivities`). This is what actually lifts the `.busy` floor once Claude
    /// stops syncing: `background_tasks` only arrives on Stop/SubagentStop, so a
    /// session that ends/orphans/idles never sends a shrinking snapshot, and
    /// without this timer the stale entry would linger until an incidental
    /// re-render happened to re-read `isStale`. A pane whose activities all age
    /// out has its entry removed entirely, matching `syncActivities([])`.
    ///
    /// `isStale` picks the TTL per entry, so lifecycle entries — which events, not
    /// the clock, are supposed to retire — only get swept by the long hard backstop
    /// that covers a CLI killed before it could send its stop hook.
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
