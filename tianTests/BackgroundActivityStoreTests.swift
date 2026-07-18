import Testing
import Foundation
@testable import tian

@MainActor
struct BackgroundActivityStoreTests {

    // MARK: - fromClaudeSnapshot: happy path

    /// A representative `background_tasks` array: one subagent, one backgrounded
    /// bash command, one bare task keyed by `id` with only a description.
    @Test func fromClaudeSnapshotDecodesRepresentativeArray() {
        let json = """
        [
          {"task_id": "a1", "type": "agent", "agent_type": "code-implementer", "status": "running"},
          {"task_id": "b2", "type": "bash", "command": "npm test", "status": "running"},
          {"id": "c3", "description": "index the repo"}
        ]
        """
        let acts = BackgroundActivity.fromClaudeSnapshot(json: json)

        // Equality ignores `lastSeen` (freshness metadata), so a plain memberwise
        // comparison checks id/kind/label/status.
        #expect(acts.count == 3)
        #expect(acts[0] == BackgroundActivity(id: "a1", kind: .agent, label: "code-implementer", status: "running"))
        #expect(acts[1] == BackgroundActivity(id: "b2", kind: .bash, label: "npm test", status: "running"))
        #expect(acts[2] == BackgroundActivity(id: "c3", kind: .other, label: "index the repo", status: nil))
    }

    // MARK: - fromClaudeSnapshot: kind mapping

    @Test func agentKindFromAgentTypeEvenWithoutTypeField() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"x","agent_type":"reviewer"}]"#)
        #expect(acts.count == 1)
        #expect(acts[0].kind == .agent)
        #expect(acts[0].label == "reviewer")
    }

    @Test func agentKindFromTypeContainingAgent() {
        // "subagent" contains "agent" → .agent, and with no agent_type the label
        // falls through to the description.
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"x","type":"subagent","description":"do work"}]"#)
        #expect(acts[0].kind == .agent)
        #expect(acts[0].label == "do work")
    }

    @Test func bashKindFromBashType() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"id":"b","type":"bash","command":"ls -la"}]"#)
        #expect(acts[0].kind == .bash)
        #expect(acts[0].label == "ls -la")
    }

    @Test func bashKindFromShellType() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"id":"s","kind":"shell","command":"echo hi"}]"#)
        #expect(acts[0].kind == .bash)
        #expect(acts[0].label == "echo hi")
    }

    @Test func otherKindWhenNoAgentOrBashHints() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"o","type":"web_search"}]"#)
        #expect(acts[0].kind == .other)
        // No agent_type/description/command → label falls back to the id.
        #expect(acts[0].label == "o")
    }

    @Test func teammateKindFromTeammateType() {
        // The shape Claude actually sends for team members in `background_tasks`.
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"id":"t1","type":"teammate","status":"running","description":"api work"}]"#)
        #expect(acts[0].kind == .teammate)
        #expect(acts[0].label == "api work")
    }

    /// Snapshot teammates get the long lifecycle TTL: their `lastSeen` is never
    /// re-stamped on re-sync (roster, not liveness), so the TTL acts as a hard cap
    /// from first sight and must be sized for a real teammate's working stretch.
    @Test func snapshotTeammateUsesTheLifecycleTTL() {
        let teammate = BackgroundActivity(id: "t", kind: .teammate, label: "t", status: "running")
        #expect(teammate.stalenessTTL == BackgroundActivity.lifecycleStalenessTTL)

        let bash = BackgroundActivity(id: "b", kind: .bash, label: "b", status: "running")
        #expect(bash.stalenessTTL == BackgroundActivity.stalenessTTL)
    }

    // MARK: - fromClaudeSnapshot: label priority

    @Test func labelPrefersDescriptionOverAgentTypeAndCommand() {
        // Description is the task-specific summary; the `.agent` glyph already
        // conveys the kind, so the label surfaces *what* the subagent is doing.
        // Kind still derives from `agent_type`.
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"p","agent_type":"AT","description":"D","command":"C"}]"#)
        #expect(acts[0].label == "D")
        #expect(acts[0].kind == .agent)
    }

    @Test func labelPrefersDescriptionOverCommandWhenNoAgentType() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"p","type":"bash","description":"D","command":"C"}]"#)
        #expect(acts[0].label == "D")
        #expect(acts[0].kind == .bash)
    }

    @Test func labelFallsBackToCommandThenId() {
        let onlyCommand = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"p","command":"C"}]"#)
        #expect(onlyCommand[0].label == "C")

        let nothing = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"only-id"}]"#)
        #expect(nothing[0].label == "only-id")
    }

    // MARK: - fromClaudeSnapshot: id resolution

    @Test func idPrefersTaskIdOverId() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"T","id":"I"}]"#)
        #expect(acts[0].id == "T")
    }

    @Test func idFallsBackToIdKey() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"id":"I","command":"x"}]"#)
        #expect(acts[0].id == "I")
    }

    @Test func numericIdIsCoercedToString() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":123,"command":"x"}]"#)
        #expect(acts.count == 1)
        #expect(acts[0].id == "123")
    }

    // MARK: - fromClaudeSnapshot: lenient / garbage

    @Test func garbageInputReturnsEmpty() {
        #expect(BackgroundActivity.fromClaudeSnapshot(json: "not json").isEmpty)
        #expect(BackgroundActivity.fromClaudeSnapshot(json: "").isEmpty)
        #expect(BackgroundActivity.fromClaudeSnapshot(json: "42").isEmpty)
        // A JSON object (not an array) is not a task list.
        #expect(BackgroundActivity.fromClaudeSnapshot(json: "{}").isEmpty)
        #expect(BackgroundActivity.fromClaudeSnapshot(json: "[]").isEmpty)
    }

    @Test func elementsWithoutUsableIdAreSkipped() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"foo":"bar"},{"task_id":"ok","command":"run"}]"#)
        #expect(acts.count == 1)
        #expect(acts[0].id == "ok")
    }

    @Test func emptyIdIsSkipped() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"","command":"x"}]"#)
        #expect(acts.isEmpty)
    }

    @Test func nonObjectElementsAreSkippedNotAborted() {
        // A mixed array must not throw away the valid object.
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[1, "x", {"task_id":"ok"}]"#)
        #expect(acts.count == 1)
        #expect(acts[0].id == "ok")
        #expect(acts[0].kind == .other)
        #expect(acts[0].label == "ok")
    }

    @Test func extraAndNestedKeysAreIgnored() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"e","type":"agent","agent_type":"AT","extra":"ignored","nested":{"a":1}}]"#)
        #expect(acts.count == 1)
        #expect(acts[0] == BackgroundActivity(id: "e", kind: .agent, label: "AT", status: nil))
    }

    // MARK: - fromClaudeSnapshot: lastSeen stamping

    @Test func fromClaudeSnapshotStampsLastSeenToNow() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: #"[{"task_id":"a","command":"x"}]"#)
        #expect(acts.count == 1)
        // Freshly decoded → seen "now" → not stale, timestamp ~= now.
        #expect(acts[0].isStale == false)
        #expect(abs(acts[0].lastSeen.timeIntervalSinceNow) < 5)
    }

    // MARK: - Kind.systemName

    @Test func kindSystemNameMapsEachCase() {
        #expect(BackgroundActivity.Kind.agent.systemName == "person.2.fill")
        #expect(BackgroundActivity.Kind.bash.systemName == "terminal")
        #expect(BackgroundActivity.Kind.other.systemName == "bolt.horizontal.circle")
    }

    // MARK: - Staleness

    @Test func isStaleReflectsLastSeenAgainstTTL() {
        let fresh = BackgroundActivity(id: "a", kind: .bash, label: "x", status: nil)
        #expect(fresh.isStale == false)

        let old = BackgroundActivity(
            id: "b", kind: .bash, label: "x", status: nil,
            lastSeen: Date(timeIntervalSinceNow: -(BackgroundActivity.stalenessTTL + 1))
        )
        #expect(old.isStale)
    }

    // MARK: - Codable conformance

    @Test func backgroundActivityRoundTripsThroughCodable() throws {
        let original = BackgroundActivity(id: "z", kind: .bash, label: "make", status: "running")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackgroundActivity.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - PaneStatusManager.syncActivities (sole writer, whole-set replace)

    @Test func syncActivitiesReplacesWholeSet() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.syncActivities(paneID: pane, [BackgroundActivity(id: "old", kind: .bash, label: "x", status: nil)])
        manager.syncActivities(paneID: pane, [
            BackgroundActivity(id: "1", kind: .agent, label: "a", status: nil),
            BackgroundActivity(id: "2", kind: .bash, label: "b", status: nil)
        ])

        // The second snapshot fully replaces the first — "old" is gone.
        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["1", "2"])
    }

    @Test func syncEmptyClearsPaneEntry() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.syncActivities(paneID: pane, [BackgroundActivity(id: "1", kind: .agent, label: "a", status: nil)])
        manager.syncActivities(paneID: pane, [])

        // Last-out clears the whole entry rather than leaving an empty array.
        #expect(manager.backgroundActivities[pane] == nil)
    }

    @Test func syncEmptyOnUnknownPaneIsNoOp() {
        let manager = PaneStatusManager()
        manager.syncActivities(paneID: UUID(), [])
        #expect(manager.backgroundActivities.isEmpty)
    }

    // MARK: - Per-PVM mirror (dual-write via pane registry)

    @Test func syncActivitiesMirrorsToOwnerPaneViewModel() throws {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .terminal)
        let paneID = pvm.splitTree.focusedPaneID
        manager.registerPane(paneID, owner: pvm)

        manager.syncActivities(paneID: paneID, [
            BackgroundActivity(id: "1", kind: .agent, label: "a", status: nil),
            BackgroundActivity(id: "2", kind: .bash, label: "b", status: nil)
        ])
        #expect(try #require(pvm.paneBackgroundActivities[paneID]).map(\.id) == ["1", "2"])

        // A syncing an empty set clears both the manager store and the mirror.
        manager.syncActivities(paneID: paneID, [])
        #expect(pvm.paneBackgroundActivities[paneID] == nil)
    }

    @Test func clearStatusClearsBackgroundActivitiesOnBothStores() {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .terminal)
        let paneID = pvm.splitTree.focusedPaneID
        manager.registerPane(paneID, owner: pvm)

        manager.syncActivities(paneID: paneID, [BackgroundActivity(id: "1", kind: .agent, label: "a", status: nil)])
        manager.clearStatus(paneID: paneID)

        #expect(manager.backgroundActivities[paneID] == nil)
        #expect(pvm.paneBackgroundActivities[paneID] == nil)
    }

    // MARK: - Staleness pruning (timer sweep)

    /// An activity last seen safely past `stalenessTTL` — the timer should drop it.
    private func aged(_ id: String) -> BackgroundActivity {
        BackgroundActivity(
            id: id, kind: .bash, label: "old", status: "running",
            lastSeen: Date(timeIntervalSinceNow: -(BackgroundActivity.stalenessTTL + 60))
        )
    }

    @Test func pruneDropsStaleKeepsFresh() {
        let manager = PaneStatusManager()
        let pane = UUID()
        manager.syncActivities(paneID: pane, [
            BackgroundActivity(id: "fresh", kind: .agent, label: "a", status: nil),
            aged("stale")
        ])

        manager.pruneStaleActivities()

        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["fresh"])
    }

    @Test func pruneRemovesPaneEntryWhenAllStale() {
        let manager = PaneStatusManager()
        let pane = UUID()
        manager.syncActivities(paneID: pane, [aged("s1"), aged("s2")])

        manager.pruneStaleActivities()

        // All aged out → the whole entry is dropped, matching syncActivities([]).
        #expect(manager.backgroundActivities[pane] == nil)
    }

    @Test func pruneIsNoOpWhenNothingStale() {
        let manager = PaneStatusManager()
        let pane = UUID()
        manager.syncActivities(paneID: pane, [BackgroundActivity(id: "1", kind: .agent, label: "a", status: nil)])

        manager.pruneStaleActivities()

        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["1"])
    }

    @Test func pruneMirrorsRemovalToOwnerPaneViewModel() throws {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .terminal)
        let paneID = pvm.splitTree.focusedPaneID
        manager.registerPane(paneID, owner: pvm)

        manager.syncActivities(paneID: paneID, [
            BackgroundActivity(id: "fresh", kind: .agent, label: "a", status: nil),
            aged("stale")
        ])
        manager.pruneStaleActivities()

        // Both the manager store and the per-PVM mirror drop the stale entry.
        #expect(manager.backgroundActivities[paneID]?.map(\.id) == ["fresh"])
        #expect(try #require(pvm.paneBackgroundActivities[paneID]).map(\.id) == ["fresh"])
    }

    // MARK: - Session idle-gate flooring

    /// A helper that seeds a session's Claude pane mirror directly (the same
    /// mirrors `aggregateClaudeState` reads), so the flooring is exercised without
    /// standing up the IPC path.
    private func seed(
        _ session: Session,
        state: ClaudeSessionState?,
        activities: [BackgroundActivity]
    ) throws {
        let pvm = try #require(session.claudePane)
        let paneID = pvm.splitTree.focusedPaneID
        if let state {
            pvm.sessionStates[paneID] = state
        }
        if !activities.isEmpty {
            pvm.paneBackgroundActivities[paneID] = activities
        }
    }

    private func makeSession() -> Session {
        Session(customName: "test", workingDirectory: "/tmp")
    }

    /// A fresh activity (`lastSeen` defaults to now) — floors the session busy.
    private let sampleActivity = BackgroundActivity(id: "bg", kind: .agent, label: "impl", status: "running")

    /// An activity last seen well past `stalenessTTL` — aged out of the aggregate.
    private var staleActivity: BackgroundActivity {
        BackgroundActivity(
            id: "old", kind: .bash, label: "lingering", status: "running",
            lastSeen: Date(timeIntervalSinceNow: -(BackgroundActivity.stalenessTTL + 60))
        )
    }

    @Test func idleWithBackgroundActivityFloorsToBusy() throws {
        let session = makeSession()
        try seed(session, state: .idle, activities: [sampleActivity])

        #expect(session.rawAggregateClaudeState == .idle)   // raw stays idle
        #expect(session.aggregateClaudeState == .busy)       // floored dot reads busy
    }

    @Test func activeWithBackgroundActivityFloorsToBusy() throws {
        let session = makeSession()
        try seed(session, state: .active, activities: [sampleActivity])
        #expect(session.aggregateClaudeState == .busy)
    }

    @Test func needsAttentionWithBackgroundActivityIsNotDowngraded() throws {
        let session = makeSession()
        try seed(session, state: .needsAttention, activities: [sampleActivity])
        #expect(session.aggregateClaudeState == .needsAttention)
    }

    @Test func failedWithBackgroundActivityIsNotDowngraded() throws {
        let session = makeSession()
        try seed(session, state: .failed, activities: [sampleActivity])
        #expect(session.aggregateClaudeState == .failed)
    }

    @Test func noBackgroundActivityReturnsRawState() throws {
        let session = makeSession()
        try seed(session, state: .idle, activities: [])
        // No outstanding work → the floor is inert, idle stays idle.
        #expect(session.backgroundActivities.isEmpty)
        #expect(session.hasBackgroundActivity == false)
        #expect(session.aggregateClaudeState == .idle)
    }

    @Test func backgroundActivityWithNoSessionStateFloorsToBusy() throws {
        let session = makeSession()
        try seed(session, state: nil, activities: [sampleActivity])
        // No pane has a session state, but background work is in flight.
        #expect(session.rawAggregateClaudeState == nil)
        #expect(session.aggregateClaudeState == .busy)
    }

    @Test func sessionBackgroundActivitiesAggregateAcrossPanes() throws {
        let session = makeSession()
        session.showTerminal()

        let claude = try #require(session.claudePane)
        let terminal = try #require(session.terminalPanel)
        let claudeID = claude.splitTree.focusedPaneID
        let terminalID = terminal.splitTree.focusedPaneID

        claude.paneBackgroundActivities[claudeID] = [BackgroundActivity(id: "1", kind: .agent, label: "a", status: nil)]
        terminal.paneBackgroundActivities[terminalID] = [BackgroundActivity(id: "2", kind: .bash, label: "b", status: nil)]

        #expect(session.backgroundActivities.map(\.id).sorted() == ["1", "2"])
        #expect(session.aggregateClaudeState == .busy)
    }

    // MARK: - Staleness TTL floor

    @Test func staleActivityExcludedFromAggregateAndDoesNotFloor() throws {
        let session = makeSession()
        try seed(session, state: .idle, activities: [staleActivity])

        // A background command that finished during a quiet idle session ages out:
        // it's filtered from the aggregate and no longer floors the dot busy.
        #expect(session.backgroundActivities.isEmpty)
        #expect(session.hasBackgroundActivity == false)
        #expect(session.aggregateClaudeState == .idle)
    }

    @Test func freshActivityFloorsWhileStaleSiblingIsExcluded() throws {
        let session = makeSession()
        try seed(session, state: .idle, activities: [staleActivity, sampleActivity])

        // Only the fresh activity survives the TTL filter, and it floors to busy.
        #expect(session.backgroundActivities.map(\.id) == ["bg"])
        #expect(session.hasBackgroundActivity)
        #expect(session.aggregateClaudeState == .busy)
    }
}
