import Testing
import Foundation
@testable import tian

/// The lifecycle feed (`SubagentStart` / `SubagentStop` / teammate hooks) and its
/// interplay with the `background_tasks` snapshot feed. `BackgroundActivityStoreTests`
/// covers the snapshot feed on its own; this file covers the two together — who wins
/// a collision, who may evict whom, and what retires a lifecycle entry.
@MainActor
struct BackgroundActivityLifecycleTests {

    // MARK: - Helpers

    /// A lifecycle-sourced subagent, as `SubagentStart` would mint it.
    private func agent(_ id: String, label: String? = nil) -> BackgroundActivity {
        BackgroundActivity.lifecycle(id: id, kind: .agent, label: label ?? id, status: "running")
    }

    /// A lifecycle-sourced teammate, as an agent-team start hook would mint it.
    private func teammate(_ id: String, label: String? = nil) -> BackgroundActivity {
        BackgroundActivity.lifecycle(id: id, kind: .teammate, label: label ?? id, status: "running")
    }

    /// A snapshot-sourced entry, as `background_tasks` would decode it.
    private func task(_ id: String, kind: BackgroundActivity.Kind = .bash) -> BackgroundActivity {
        BackgroundActivity(id: id, kind: kind, label: id, status: "running")
    }

    /// An entry backdated by `age` seconds — staleness is asserted against explicit
    /// timestamps, never by sleeping.
    private func backdated(
        _ id: String,
        source: BackgroundActivity.Source,
        age: TimeInterval
    ) -> BackgroundActivity {
        BackgroundActivity(
            id: id,
            kind: source == .lifecycle ? .agent : .bash,
            label: id,
            status: "running",
            lastSeen: Date(timeIntervalSinceNow: -age),
            source: source
        )
    }

    // MARK: - BackgroundActivity: source & kind

    @Test func lifecycleFactoryStampsSource() {
        let activity = BackgroundActivity.lifecycle(id: "a1", kind: .agent, label: "explore")

        #expect(activity.source == .lifecycle)
        #expect(activity.kind == .agent)
        #expect(activity.label == "explore")
    }

    /// Defaulting to `.snapshot` is what keeps every pre-existing construction site
    /// (and the whole `background_tasks` path) meaning what it always meant.
    @Test func memberwiseInitDefaultsToSnapshotSource() {
        #expect(BackgroundActivity(id: "1", kind: .bash, label: "x", status: nil).source == .snapshot)
    }

    @Test func fromClaudeSnapshotStampsSnapshotSource() {
        let acts = BackgroundActivity.fromClaudeSnapshot(json: """
        [{"task_id": "a1", "type": "agent", "agent_type": "explorer"},
         {"task_id": "b2", "type": "bash", "command": "npm test"}]
        """)

        #expect(acts.count == 2)
        #expect(acts.allSatisfy { $0.source == .snapshot })
    }

    @Test func teammateKindHasItsOwnGlyph() {
        #expect(BackgroundActivity.Kind.teammate.systemName == "person.3.fill")
        #expect(BackgroundActivity.Kind.agent.systemName == "person.2.fill")
    }

    /// Equality still ignores `lastSeen` (freshness, not identity) but does compare
    /// `source` — the same id from the other feed is a different fact.
    @Test func equalityIgnoresLastSeenButComparesSource() {
        let now = BackgroundActivity(id: "1", kind: .agent, label: "a", status: nil, lastSeen: Date())
        let old = BackgroundActivity(id: "1", kind: .agent, label: "a", status: nil,
                                     lastSeen: Date(timeIntervalSinceNow: -500))
        #expect(now == old)
        #expect(now != BackgroundActivity.lifecycle(id: "1", kind: .agent, label: "a"))
    }

    // MARK: - begin / end

    @Test func beginThenEndRemovesTheEntry() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, agent("a1"))
        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["a1"])

        manager.endActivity(paneID: pane, id: "a1")

        // Emptied → the pane's entry is gone entirely, not left as [].
        #expect(manager.backgroundActivities[pane] == nil)
    }

    @Test func endOfUnknownIdIsSilentNoOp() {
        let manager = PaneStatusManager()
        let pane = UUID()

        // Unknown pane entirely.
        manager.endActivity(paneID: pane, id: "ghost")
        #expect(manager.backgroundActivities.isEmpty)

        // Known pane, unknown id — the live entry is untouched.
        manager.beginActivity(paneID: pane, agent("a1"))
        manager.endActivity(paneID: pane, id: "ghost")
        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["a1"])
    }

    @Test func beginTwiceWithSameIdUpsertsInPlace() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, agent("a1", label: "first"))
        manager.beginActivity(paneID: pane, agent("a2", label: "second"))
        manager.beginActivity(paneID: pane, agent("a1", label: "relabelled"))

        let activities = manager.backgroundActivities[pane] ?? []
        #expect(activities.count == 2)                       // no double count
        #expect(activities.map(\.id) == ["a1", "a2"])        // original order preserved
        #expect(activities[0].label == "relabelled")         // updated in place
    }

    @Test func endByLabelRemovesFirstMatch() {
        let manager = PaneStatusManager()
        let pane = UUID()

        // Teammate events carry a name, not a stable id — hence the label fallback.
        manager.beginActivity(paneID: pane, BackgroundActivity.lifecycle(id: "t1", kind: .teammate, label: "ada"))
        manager.beginActivity(paneID: pane, BackgroundActivity.lifecycle(id: "t2", kind: .teammate, label: "grace"))

        manager.endActivity(paneID: pane, label: "ada")
        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["t2"])

        // Unknown label is a no-op, exactly like the id-keyed overload.
        manager.endActivity(paneID: pane, label: "nobody")
        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["t2"])
    }

    @Test func beginAndEndMirrorToOwnerPaneViewModel() throws {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .claude)
        let paneID = pvm.splitTree.focusedPaneID
        manager.registerPane(paneID, owner: pvm)

        manager.beginActivity(paneID: paneID, agent("a1"))
        #expect(try #require(pvm.paneBackgroundActivities[paneID]).map(\.id) == ["a1"])

        manager.endActivity(paneID: paneID, id: "a1")
        #expect(pvm.paneBackgroundActivities[paneID] == nil)
    }

    // MARK: - syncActivities (partial replace)

    @Test func syncPreservesLifecycleAndReplacesSnapshotEntries() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, agent("a1"))
        manager.syncActivities(paneID: pane, [task("old")])

        // A later snapshot replaces only its own kind of entry.
        manager.syncActivities(paneID: pane, [task("new")])

        let ids = Set((manager.backgroundActivities[pane] ?? []).map(\.id))
        #expect(ids == ["a1", "new"])   // "old" gone, the running subagent survives
    }

    @Test func syncDropsSnapshotDuplicateOfLiveLifecycleEntry() {
        let manager = PaneStatusManager()
        let pane = UUID()

        // A subagent gets backgrounded: it now shows up in *both* feeds under the
        // same id. Lifecycle wins; the duplicate is dropped, so it counts once.
        manager.beginActivity(paneID: pane, agent("a1"))
        manager.syncActivities(paneID: pane, [task("a1", kind: .agent), task("b2")])

        let activities = manager.backgroundActivities[pane] ?? []
        #expect(activities.map(\.id) == ["a1", "b2"])
        #expect(activities.filter { $0.id == "a1" }.count == 1)
        #expect(activities.first { $0.id == "a1" }?.source == .lifecycle)
    }

    @Test func emptySnapshotDoesNotEvictLifecycleEntries() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, agent("a1"))
        manager.syncActivities(paneID: pane, [])

        // A mid-turn snapshot never mentions foreground subagents — it must not
        // erase them.
        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["a1"])
    }

    /// Graceful degradation: on a Claude Code that never emits `SubagentStart`, the
    /// snapshot's `.agent` entries are the only agent signal and behave exactly as
    /// they did before the lifecycle feed existed.
    @Test func snapshotOnlyPaneStillTracksAgentsAsBefore() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.syncActivities(paneID: pane, [task("a1", kind: .agent), task("b2")])

        #expect(!manager.hasSeenLifecycleEvents(paneID: pane))
        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["a1", "b2"])

        // Whole-set replace still holds when no lifecycle entry exists to preserve.
        manager.syncActivities(paneID: pane, [task("c3", kind: .agent)])
        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["c3"])

        manager.syncActivities(paneID: pane, [])
        #expect(manager.backgroundActivities[pane] == nil)
    }

    @Test func hasSeenLifecycleEventsFlipsOnFirstBegin() {
        let manager = PaneStatusManager()
        let pane = UUID()

        #expect(!manager.hasSeenLifecycleEvents(paneID: pane))
        manager.beginActivity(paneID: pane, agent("a1"))
        #expect(manager.hasSeenLifecycleEvents(paneID: pane))

        // Ending the work doesn't un-learn that this CLI speaks lifecycle hooks…
        manager.endActivity(paneID: pane, id: "a1")
        #expect(manager.hasSeenLifecycleEvents(paneID: pane))

        // …but closing the pane leaves nothing behind.
        manager.clearStatus(paneID: pane)
        #expect(!manager.hasSeenLifecycleEvents(paneID: pane))
    }

    @Test func clearAllForgetsLifecycleMark() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, agent("a1"))
        manager.clearAll(for: [pane])

        #expect(!manager.hasSeenLifecycleEvents(paneID: pane))
        #expect(manager.backgroundActivities[pane] == nil)
    }

    // MARK: - reconcileActivities (Stop hook)

    @Test func reconcileDropsLifecycleAgentsAndKeepsTheSnapshot() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, agent("a1"))
        manager.beginActivity(paneID: pane, agent("a2"))
        manager.syncActivities(paneID: pane, [task("bg")])

        // Turn ended: the foreground agents are provably done, and anything still
        // running is in the Stop payload's own snapshot.
        manager.reconcileActivities(paneID: pane, [task("bg"), task("a2", kind: .agent)])

        let activities = manager.backgroundActivities[pane] ?? []
        #expect(activities.map(\.id) == ["bg", "a2"])
        #expect(activities.allSatisfy { $0.source == .snapshot })
    }

    /// A teammate is not turn-scoped — it keeps working across the main agent's turn
    /// boundaries, so `Stop` may not retire it (only `TeammateIdle` may). Subagents of
    /// that turn still die, and the snapshot still applies.
    @Test func reconcilePreservesTeammatesWhileDroppingAgents() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, agent("a1"))
        manager.beginActivity(paneID: pane, teammate("t1", label: "ada"))
        manager.syncActivities(paneID: pane, [task("old")])

        manager.reconcileActivities(paneID: pane, [task("bg")])

        let activities = manager.backgroundActivities[pane] ?? []
        // Surviving teammate keeps its position ahead of the snapshot, as in `syncActivities`.
        #expect(activities.map(\.id) == ["t1", "bg"])
        #expect(activities.first?.source == .lifecycle)
        #expect(activities.first?.kind == .teammate)
    }

    /// A teammate that also surfaces in the Stop payload's `background_tasks` must not
    /// be counted twice — same dedupe-by-id, lifecycle-wins rule as `syncActivities`.
    @Test func reconcileDoesNotDoubleCountATeammateAlsoInTheSnapshot() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, teammate("t1", label: "ada"))

        manager.reconcileActivities(paneID: pane, [task("t1", kind: .teammate), task("bg")])

        let activities = manager.backgroundActivities[pane] ?? []
        #expect(activities.map(\.id) == ["t1", "bg"])
        #expect(activities.filter { $0.id == "t1" }.count == 1)
        #expect(activities.first { $0.id == "t1" }?.source == .lifecycle)
    }

    @Test func reconcileWithEmptySnapshotClearsThePaneEntry() throws {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .claude)
        let paneID = pvm.splitTree.focusedPaneID
        manager.registerPane(paneID, owner: pvm)

        manager.beginActivity(paneID: paneID, agent("a1"))
        manager.syncActivities(paneID: paneID, [task("bg")])
        #expect(try #require(pvm.paneBackgroundActivities[paneID]).count == 2)

        manager.reconcileActivities(paneID: paneID, [])

        // Nothing outstanding → absent in both stores, not an empty array.
        #expect(manager.backgroundActivities[paneID] == nil)
        #expect(pvm.paneBackgroundActivities[paneID] == nil)
    }

    // MARK: - resetLifecycleActivities (new prompt / idle)

    @Test func resetDropsLifecycleAgentsAndKeepsTeammatesAndSnapshots() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, agent("a1"))
        manager.beginActivity(paneID: pane, teammate("t1", label: "ada"))
        manager.syncActivities(paneID: pane, [task("bg")])

        // A new prompt proves the previous (possibly ESC-cancelled) turn is over, so
        // its subagents are dead. A teammate outlives the turn (only `TeammateIdle`
        // retires it), and so does a backgrounded bash.
        manager.resetLifecycleActivities(paneID: pane)

        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["t1", "bg"])
    }

    @Test func resetClearsThePaneEntryWhenOnlyLifecycleEntriesExisted() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, agent("a1"))
        manager.resetLifecycleActivities(paneID: pane)

        #expect(manager.backgroundActivities[pane] == nil)
    }

    @Test func resetOnPaneWithNoLifecycleEntriesIsNoOp() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.syncActivities(paneID: pane, [task("bg")])
        manager.resetLifecycleActivities(paneID: pane)

        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["bg"])
    }

    // MARK: - clearActivities (SessionEnd hook)

    /// `SessionEnd` ends the Claude session while the pane lives on, so *everything*
    /// that session spawned goes — including the teammates that reconcile/reset now
    /// deliberately preserve, which is why this can't be a `reconcileActivities([])`.
    @Test func clearActivitiesRemovesEverySourceAndKind() throws {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .claude)
        let paneID = pvm.splitTree.focusedPaneID
        manager.registerPane(paneID, owner: pvm)

        manager.beginActivity(paneID: paneID, agent("a1"))
        manager.beginActivity(paneID: paneID, teammate("t1", label: "ada"))
        manager.syncActivities(paneID: paneID, [task("bg")])
        #expect(try #require(pvm.paneBackgroundActivities[paneID]).count == 3)

        manager.clearActivities(paneID: paneID)

        // The key is gone entirely, not left as [] — in both stores.
        #expect(manager.backgroundActivities[paneID] == nil)
        #expect(!manager.backgroundActivities.keys.contains(paneID))
        #expect(pvm.paneBackgroundActivities[paneID] == nil)
    }

    @Test func clearActivitiesOnUnknownPaneIsSilentNoOp() {
        let manager = PaneStatusManager()

        manager.clearActivities(paneID: UUID())

        #expect(manager.backgroundActivities.isEmpty)
    }

    // MARK: - Retired teammates (lying snapshots)

    /// The dead-teammate loop: Claude keeps re-listing an idle teammate as
    /// `"running"` in every turn-end `background_tasks`. Once `TeammateIdle`/
    /// `SubagentStop` ended it, the re-listing must not resurrect it — that
    /// resurrection is what pinned wakeup-loop sessions busy forever.
    @Test func reconcileDoesNotResurrectAnEndedTeammate() {
        let manager = PaneStatusManager()
        let pane = UUID()
        let snapshot = [task("t1", kind: .teammate)]

        manager.reconcileActivities(paneID: pane, snapshot)
        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["t1"])

        manager.endActivity(paneID: pane, id: "t1")        // TeammateIdle
        manager.reconcileActivities(paneID: pane, snapshot) // Claude lies again

        #expect(manager.backgroundActivities[pane] == nil)
    }

    @Test func syncDoesNotResurrectAnEndedTeammate() {
        let manager = PaneStatusManager()
        let pane = UUID()
        let snapshot = [task("t1", kind: .teammate)]

        manager.syncActivities(paneID: pane, snapshot)
        manager.endActivity(paneID: pane, id: "t1")
        manager.syncActivities(paneID: pane, snapshot)

        #expect(manager.backgroundActivities[pane] == nil)
    }

    /// Retirement is teammate-scoped: an ended id whose snapshot entry is a bash
    /// task keeps the whole-set-replace semantics and comes back on re-sync.
    @Test func endedBashTaskIsStillReplacedBySnapshots() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.endActivity(paneID: pane, id: "b1")
        manager.syncActivities(paneID: pane, [task("b1")])

        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["b1"])
    }

    /// The label-fallback end (a teammate event with no id) retires the *entry's*
    /// id, so the roster re-listing is blocked the same as an id-keyed end.
    @Test func endByLabelRetiresTheEndedEntryId() {
        let manager = PaneStatusManager()
        let pane = UUID()
        let snapshot = [task("t9", kind: .teammate)]   // task() labels with the id

        manager.reconcileActivities(paneID: pane, snapshot)
        manager.endActivity(paneID: pane, label: "t9")
        manager.reconcileActivities(paneID: pane, snapshot)

        #expect(manager.backgroundActivities[pane] == nil)
    }

    /// A fresh lifecycle begin un-retires the id — a new start is proof the worker
    /// is alive again, so later snapshots may report it once more.
    @Test func freshBeginUnretiresTheId() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.endActivity(paneID: pane, id: "t1")            // event-retired
        manager.beginActivity(paneID: pane, agent("t1"))       // re-spawned
        // Reconcile drops the lifecycle agent entry, then admits the snapshot's
        // teammate entry — which only works if the id was un-retired.
        manager.reconcileActivities(paneID: pane, [task("t1", kind: .teammate)])

        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["t1"])
        #expect(manager.backgroundActivities[pane]?.first?.source == .snapshot)
    }

    /// A re-listed teammate ages from *first sight*: the merge keeps the original
    /// `lastSeen` instead of the fresh decode stamp, so the (long) teammate TTL is
    /// a hard cap rather than a sliding window Claude re-arms every turn-end.
    @Test func relistedTeammateKeepsItsOriginalLastSeen() {
        let manager = PaneStatusManager()
        let pane = UUID()

        var first = task("t1", kind: .teammate)
        first.lastSeen = Date(timeIntervalSinceNow: -500)
        manager.reconcileActivities(paneID: pane, [first])

        manager.reconcileActivities(paneID: pane, [task("t1", kind: .teammate)])

        let merged = manager.backgroundActivities[pane]?.first
        #expect(merged.map { $0.lastSeen.timeIntervalSinceNow < -400 } == true)
    }

    /// Bash/task snapshot entries keep the old behavior: every re-sync refreshes
    /// them, because for genuinely running background work the snapshot *is* the
    /// liveness feed.
    @Test func relistedBashIsRefreshed() {
        let manager = PaneStatusManager()
        let pane = UUID()

        var first = task("b1")
        first.lastSeen = Date(timeIntervalSinceNow: -100)
        manager.syncActivities(paneID: pane, [first])

        manager.syncActivities(paneID: pane, [task("b1")])

        let merged = manager.backgroundActivities[pane]?.first
        #expect(merged.map { $0.lastSeen.timeIntervalSinceNow > -5 } == true)
    }

    /// TTL expiry is itself a retirement: once a snapshot teammate ages out and the
    /// sweep drops it, the next lying re-list may not floor the session for another
    /// full TTL — that would be an endless busy/idle oscillation.
    @Test func pruneRetiresStaleSnapshotTeammates() {
        let manager = PaneStatusManager()
        let pane = UUID()

        var old = task("t1", kind: .teammate)
        old.lastSeen = Date(timeIntervalSinceNow: -(BackgroundActivity.lifecycleStalenessTTL + 1))
        manager.reconcileActivities(paneID: pane, [old])

        manager.pruneStaleActivities()
        #expect(manager.backgroundActivities[pane] == nil)

        manager.reconcileActivities(paneID: pane, [task("t1", kind: .teammate)])
        #expect(manager.backgroundActivities[pane] == nil)
    }

    /// The turn-scoped resets (`UserPromptSubmit`, idle) must NOT forget
    /// retirements — the next prompt's turn-end snapshot still lies.
    @Test func resetLifecycleKeepsRetirements() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.endActivity(paneID: pane, id: "t1")
        manager.resetLifecycleActivities(paneID: pane)
        manager.reconcileActivities(paneID: pane, [task("t1", kind: .teammate)])

        #expect(manager.backgroundActivities[pane] == nil)
    }

    /// `SessionEnd` ends the id space along with the session: the next Claude
    /// session in this pane mints fresh ids and must start unfiltered.
    @Test func clearActivitiesForgetsRetirements() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.endActivity(paneID: pane, id: "t1")
        manager.clearActivities(paneID: pane)
        manager.reconcileActivities(paneID: pane, [task("t1", kind: .teammate)])

        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["t1"])
    }

    /// End-to-end shape of the released-attention regression: with only a retired
    /// (re-listed) teammate left, an ended attention owner falls to `.idle`, not to
    /// a phantom `.busy`.
    @Test func attentionReleaseFallsToIdleWhenOnlyRetiredTeammatesRemain() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.reconcileActivities(paneID: pane, [task("t1", kind: .teammate)])
        manager.setSessionState(paneID: pane, state: .needsAttention, origin: .agent("a1"))
        manager.endActivity(paneID: pane, id: "t1")        // TeammateIdle
        manager.reconcileActivities(paneID: pane, [task("t1", kind: .teammate)])
        manager.endActivity(paneID: pane, id: "a1")        // attention owner dies

        #expect(manager.sessionState(for: pane) == .idle)
    }

    // MARK: - Source-aware staleness

    /// 200s past `lastSeen`: a snapshot entry (180s TTL) is stale, a lifecycle entry
    /// (900s hard backstop) is not — a real foreground agent can grind for minutes
    /// with no hook to refresh it, and under-counting a live agent is the worse bug.
    @Test func stalenessUsesThePerSourceTTL() {
        #expect(backdated("s", source: .snapshot, age: 200).isStale)
        #expect(!backdated("l", source: .lifecycle, age: 200).isStale)

        // Past its own backstop, a lifecycle entry does eventually age out.
        #expect(backdated("l", source: .lifecycle, age: 1000).isStale)

        #expect(BackgroundActivity.stalenessTTL == 180)
        #expect(BackgroundActivity.lifecycleStalenessTTL == 900)
    }

    @Test func pruneDropsStaleSnapshotEntryAndKeepsAgedLifecycleEntry() {
        let manager = PaneStatusManager()
        let pane = UUID()

        manager.beginActivity(paneID: pane, backdated("l1", source: .lifecycle, age: 200))
        manager.syncActivities(paneID: pane, [backdated("s1", source: .snapshot, age: 200)])

        manager.pruneStaleActivities()

        #expect(manager.backgroundActivities[pane]?.map(\.id) == ["l1"])
    }

    @Test func pruneRemovesThePaneEntryWhenEverythingAgesOut() throws {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .claude)
        let paneID = pvm.splitTree.focusedPaneID
        manager.registerPane(paneID, owner: pvm)

        manager.beginActivity(paneID: paneID, backdated("l1", source: .lifecycle, age: 1000))
        manager.syncActivities(paneID: paneID, [backdated("s1", source: .snapshot, age: 1000)])

        manager.pruneStaleActivities()

        #expect(manager.backgroundActivities[paneID] == nil)
        #expect(pvm.paneBackgroundActivities[paneID] == nil)
    }
}
