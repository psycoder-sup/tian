import Testing
import Foundation
@testable import tian

@MainActor
struct PaneStatusManagerTests {

    // MARK: - Helpers

    /// A fresh session with a live Claude pane and no terminal panel.
    private func makeSession() -> Session {
        Session(customName: "test", workingDirectory: "/tmp")
    }

    /// A session with both a Claude pane and a terminal panel — two panes for
    /// exercising the cross-pane aggregators.
    private func makeSessionWithClaudeAndTerminal() -> Session {
        let session = Session(customName: "test", workingDirectory: "/tmp")
        session.showTerminal()
        return session
    }

    private func claudePaneID(_ session: Session) -> UUID {
        session.claudePane!.splitTree.focusedPaneID
    }

    private func terminalPaneID(_ session: Session) -> UUID {
        session.terminalPanel!.splitTree.focusedPaneID
    }

    // MARK: - setStatus (FR-21)

    @Test func setStatusStoresLabel() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setStatus(paneID: paneID, label: "Thinking...")

        #expect(manager.statuses[paneID]?.label == "Thinking...")
        #expect(manager.statuses[paneID]?.sequence != nil)
    }

    // MARK: - clearStatus (FR-22)

    @Test func clearStatusRemovesEntry() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setStatus(paneID: paneID, label: "Building")
        manager.clearStatus(paneID: paneID)

        #expect(manager.statuses[paneID] == nil)
        #expect(manager.statuses.isEmpty)
    }

    // MARK: - Independent statuses (FR-23)

    @Test func multiplePanesHaveIndependentStatuses() {
        let manager = PaneStatusManager()
        let paneA = UUID()
        let paneB = UUID()

        manager.setStatus(paneID: paneA, label: "Building")
        manager.setStatus(paneID: paneB, label: "Testing")

        #expect(manager.statuses.count == 2)
        #expect(manager.statuses[paneA]?.label == "Building")
        #expect(manager.statuses[paneB]?.label == "Testing")

        manager.clearStatus(paneID: paneA)
        #expect(manager.statuses[paneB]?.label == "Testing")
        #expect(manager.statuses.count == 1)
    }

    // MARK: - Pane close clears status (FR-24)

    @Test func closePaneClearsStatus() {
        let shared = PaneStatusManager.shared

        let pvm = PaneViewModel(kind: .terminal)
        let paneID = pvm.splitTree.focusedPaneID

        // Clean up any prior state
        shared.clearStatus(paneID: paneID)

        shared.setStatus(paneID: paneID, label: "Running")
        #expect(shared.statuses[paneID]?.label == "Running")

        pvm.closePane(paneID: paneID)

        #expect(shared.statuses[paneID] == nil)
    }

    // MARK: - setStatus replaces existing (FR-25)

    @Test func setStatusReplacesExisting() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setStatus(paneID: paneID, label: "First")
        manager.setStatus(paneID: paneID, label: "Second")

        #expect(manager.statuses[paneID]?.label == "Second")
        #expect(manager.statuses.count == 1)
    }

    // MARK: - clearAll

    @Test func clearAllRemovesBatch() {
        let manager = PaneStatusManager()
        let a = UUID(), b = UUID(), c = UUID()

        manager.setStatus(paneID: a, label: "A")
        manager.setStatus(paneID: b, label: "B")
        manager.setStatus(paneID: c, label: "C")

        manager.clearAll(for: [a, b])

        #expect(manager.statuses[a] == nil)
        #expect(manager.statuses[b] == nil)
        #expect(manager.statuses[c]?.label == "C")
    }

    @Test func clearAllWithEmptySetIsNoOp() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setStatus(paneID: paneID, label: "Keep")
        manager.clearAll(for: [])

        #expect(manager.statuses[paneID]?.label == "Keep")
    }

    // MARK: - latestStatus

    @Test func latestStatusReturnsMostRecentInSession() {
        let manager = PaneStatusManager()
        let session = makeSessionWithClaudeAndTerminal()

        let pane1 = claudePaneID(session)
        let pane2 = terminalPaneID(session)

        manager.setStatus(paneID: pane1, label: "Older")
        manager.setStatus(paneID: pane2, label: "Newer")

        let latest = manager.latestStatus(in: session)
        #expect(latest?.label == "Newer")
    }

    @Test func latestStatusReturnsNilWhenEmpty() {
        let manager = PaneStatusManager()
        let session = makeSession()

        #expect(manager.latestStatus(in: session) == nil)
    }

    @Test func latestStatusIgnoresPanesOutsideSession() {
        let manager = PaneStatusManager()
        let session = makeSession()

        manager.setStatus(paneID: UUID(), label: "Outside")

        #expect(manager.latestStatus(in: session) == nil)
    }

    // MARK: - Edge Cases

    @Test func emptyLabelIsAccepted() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setStatus(paneID: paneID, label: "")

        #expect(manager.statuses[paneID]?.label == "")
    }

    @Test func longLabelIsAccepted() {
        let manager = PaneStatusManager()
        let paneID = UUID()
        let longLabel = String(repeating: "x", count: 1000)

        manager.setStatus(paneID: paneID, label: longLabel)

        #expect(manager.statuses[paneID]?.label.count == 1000)
    }

    @Test func clearStatusOnNonexistentPaneIsNoOp() {
        let manager = PaneStatusManager()

        manager.clearStatus(paneID: UUID())

        #expect(manager.statuses.isEmpty)
    }

    // MARK: - setSessionState

    @Test func setSessionStateStoresState() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .busy)

        #expect(manager.sessionStates[paneID] == .busy)
    }

    @Test func setSessionStateDoesNotAffectStatuses() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .active)

        #expect(manager.statuses[paneID] == nil)
        #expect(manager.sessionStates[paneID] == .active)
    }

    @Test func setSessionStateReplacesExisting() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .idle)
        manager.setSessionState(paneID: paneID, state: .busy)

        #expect(manager.sessionStates[paneID] == .busy)
    }

    @Test func idleDoesNotDowngradeNeedsAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention)
        manager.setSessionState(paneID: paneID, state: .idle)

        // A clean turn-end must not erase a pending prompt.
        #expect(manager.sessionStates[paneID] == .needsAttention)
    }

    @Test func idleDoesNotDowngradeFailed() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        // Models the Stop/StopFailure ordering race: StopFailure then a trailing Stop.
        manager.setSessionState(paneID: paneID, state: .failed)
        manager.setSessionState(paneID: paneID, state: .idle)

        #expect(manager.sessionStates[paneID] == .failed)
    }

    @Test func busyClearsNeedsAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention)
        manager.setSessionState(paneID: paneID, state: .busy)

        // Claude resuming work resolves the attention.
        #expect(manager.sessionStates[paneID] == .busy)
    }

    @Test func failedSurfacesOverNeedsAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention)
        manager.setSessionState(paneID: paneID, state: .failed)

        // A turn that dies mid-permission is dead; surface the failure.
        #expect(manager.sessionStates[paneID] == .failed)
    }

    // MARK: - Attention ownership (subagent vs main thread)

    /// The bug this ownership tracking exists for: Claude Code fires a subagent's
    /// PostToolUse in the parent's process under the same pane id, so a background
    /// agent's `busy` used to bury the question the main thread is blocked on.
    @Test func subagentBusyDoesNotClearMainThreadNeedsAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .main)
        manager.setSessionState(paneID: paneID, state: .busy, origin: .agent("a911931f"))

        #expect(manager.sessionStates[paneID] == .needsAttention)
        #expect(manager.attentionOwners[paneID] == .main)
    }

    /// An empty `agent_id` is exactly what the main thread sends, so it must resolve
    /// to the same origin as an omitted one.
    @Test func emptyAgentIDIsTheMainThread() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: ClaudeEventOrigin(agentID: ""))
        manager.setSessionState(paneID: paneID, state: .busy, origin: ClaudeEventOrigin(agentID: nil))

        #expect(manager.sessionStates[paneID] == .busy)
    }

    @Test func mainThreadBusyClearsMainThreadNeedsAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .main)
        manager.setSessionState(paneID: paneID, state: .busy, origin: .main)

        // The user answered; the main thread's next tool call proves it.
        #expect(manager.sessionStates[paneID] == .busy)
        #expect(manager.attentionOwners[paneID] == nil)
    }

    /// A subagent's permission prompt is cleared by that same subagent proceeding.
    @Test func subagentBusyClearsItsOwnNeedsAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))
        manager.setSessionState(paneID: paneID, state: .busy, origin: .agent("a1"))

        #expect(manager.sessionStates[paneID] == .busy)
        #expect(manager.attentionOwners[paneID] == nil)
    }

    /// The mirror image of the bug: the parent kept working while a background
    /// agent's permission prompt waits — the prompt has to survive that.
    @Test func mainThreadBusyDoesNotClearSubagentNeedsAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))
        manager.setSessionState(paneID: paneID, state: .busy, origin: .main)

        #expect(manager.sessionStates[paneID] == .needsAttention)
        #expect(manager.attentionOwners[paneID] == .agent("a1"))
    }

    /// One subagent's traffic must not clear another's prompt either.
    @Test func otherSubagentBusyDoesNotClearSubagentNeedsAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))
        manager.setSessionState(paneID: paneID, state: .active, origin: .agent("a2"))

        #expect(manager.sessionStates[paneID] == .needsAttention)
        #expect(manager.attentionOwners[paneID] == .agent("a1"))
    }

    /// A newer question takes ownership from an older one.
    @Test func incomingNeedsAttentionRebindsTheOwner() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .main)
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))

        #expect(manager.attentionOwners[paneID] == .agent("a1"))

        // And now only the new owner may clear it.
        manager.setSessionState(paneID: paneID, state: .busy, origin: .main)
        #expect(manager.sessionStates[paneID] == .needsAttention)
    }

    /// Ownership is scoped to the prompt: `failed` and `inactive` end the turn (or
    /// the session) whoever reports them, and both drop the owner.
    @Test func failedFromAnyOriginClearsTheOwner() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .main)
        manager.setSessionState(paneID: paneID, state: .failed, origin: .agent("a1"))

        #expect(manager.sessionStates[paneID] == .failed)
        #expect(manager.attentionOwners[paneID] == nil)
    }

    @Test func sessionEndClearsTheOwner() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))
        manager.setSessionState(paneID: paneID, state: .inactive, origin: .main)

        #expect(manager.sessionStates[paneID] == .inactive)
        #expect(manager.attentionOwners[paneID] == nil)
    }

    /// A suppressed `idle` leaves both the prompt and its owner standing.
    @Test func idleStillCannotDowngradeNeedsAttentionAndKeepsTheOwner() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))
        manager.setSessionState(paneID: paneID, state: .idle, origin: .agent("a1"))

        #expect(manager.sessionStates[paneID] == .needsAttention)
        #expect(manager.attentionOwners[paneID] == .agent("a1"))
    }

    @Test func attentionOwnerMirrorsNothingToPaneViewModel() {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .claude)
        let paneID = pvm.splitTree.focusedPaneID

        manager.registerPane(paneID, owner: pvm)
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))
        #expect(pvm.sessionState(forPane: paneID) == .needsAttention)

        // Suppressed update: the mirror must not drift from the manager.
        manager.setSessionState(paneID: paneID, state: .busy, origin: .main)
        #expect(pvm.sessionState(forPane: paneID) == .needsAttention)
    }

    // MARK: - Attention released when its owner ends

    /// A subagent that dies (or finishes) after raising a permission prompt will
    /// never send the `busy` that would clear it — its stop hook has to, or the pane
    /// stays orange forever.
    @Test func activityEndReleasesAttentionOwnedByThatAgent() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.beginActivity(paneID: paneID, BackgroundActivity.lifecycle(id: "a1", kind: .agent, label: "explore", status: "running"))
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))

        manager.endActivity(paneID: paneID, id: "a1")

        // No other work outstanding → the pane falls back to idle.
        #expect(manager.sessionStates[paneID] == .idle)
        #expect(manager.attentionOwners[paneID] == nil)
    }

    @Test func activityEndFallsBackToBusyWhenOtherWorkRemains() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.beginActivity(paneID: paneID, BackgroundActivity.lifecycle(id: "a1", kind: .agent, label: "explore", status: "running"))
        manager.beginActivity(paneID: paneID, BackgroundActivity.lifecycle(id: "a2", kind: .agent, label: "review", status: "running"))
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))

        manager.endActivity(paneID: paneID, id: "a1")

        #expect(manager.sessionStates[paneID] == .busy)
        #expect(manager.attentionOwners[paneID] == nil)
    }

    /// An unrelated agent ending says nothing about someone else's prompt.
    @Test func activityEndLeavesAttentionOwnedByAnotherOrigin() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.beginActivity(paneID: paneID, BackgroundActivity.lifecycle(id: "a2", kind: .agent, label: "review", status: "running"))
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .main)

        manager.endActivity(paneID: paneID, id: "a2")

        #expect(manager.sessionStates[paneID] == .needsAttention)
        #expect(manager.attentionOwners[paneID] == .main)
    }

    /// The stop hook is proof the agent is gone even when its entry was already
    /// evicted (by a snapshot, a reconcile, or a duplicate stop).
    @Test func activityEndReleasesAttentionEvenWithNoTrackedActivity() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))

        manager.endActivity(paneID: paneID, id: "a1")

        #expect(manager.sessionStates[paneID] == .idle)
        #expect(manager.attentionOwners[paneID] == nil)
    }

    @Test func activityEndReleaseMirrorsToOwnerPaneViewModel() {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .claude)
        let paneID = pvm.splitTree.focusedPaneID

        manager.registerPane(paneID, owner: pvm)
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))
        manager.endActivity(paneID: paneID, id: "a1")

        #expect(pvm.sessionState(forPane: paneID) == .idle)
    }

    // MARK: - Attention ownership fails closed (restored panes)

    /// Session state is persisted, the owner map isn't — so a pane could come back
    /// from disk in `needsAttention` with nothing recorded. The default has to be
    /// `.main`, never "unowned".
    @Test func unknownAttentionOwnerFailsClosedToMain() {
        let manager = PaneStatusManager()

        #expect(manager.effectiveAttentionOwner(paneID: UUID()) == .main)
    }

    @Test func recordedAttentionOwnerWinsOverTheDefault() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))

        #expect(manager.effectiveAttentionOwner(paneID: paneID) == .agent("a1"))
    }

    /// The restore path (`PaneViewModel.fromState`) replays the persisted state with
    /// no origin — which must land as a main-thread-owned prompt, so a background
    /// subagent's `busy` can't bury a question that survived a relaunch.
    @Test func restoredNeedsAttentionRejectsSubagentBusy() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention)   // as restore does
        manager.setSessionState(paneID: paneID, state: .busy, origin: .agent("a1"))

        #expect(manager.sessionStates[paneID] == .needsAttention)
    }

    @Test func restoredNeedsAttentionAcceptsMainThreadBusy() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention)   // as restore does
        manager.setSessionState(paneID: paneID, state: .busy, origin: .main)

        #expect(manager.sessionStates[paneID] == .busy)
        #expect(manager.attentionOwners[paneID] == nil)
    }

    /// A subagent dying is proof about *its own* prompt only: an unknown owner is
    /// `.main`, never `.agent(_)`, so its stop hook must not release the prompt.
    @Test func subagentEndDoesNotReleaseAttentionWithUnknownOwner() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setSessionState(paneID: paneID, state: .needsAttention)   // as restore does
        manager.endActivity(paneID: paneID, id: "a1")

        #expect(manager.sessionStates[paneID] == .needsAttention)
        #expect(manager.effectiveAttentionOwner(paneID: paneID) == .main)
    }

    // MARK: - Attention release id spaces

    /// A teammate's id is a `teammate_id`, not an `agent_id` — different id spaces.
    /// Even when the two strings collide, ending the teammate must not release a
    /// prompt owned by the agent of the same name.
    @Test func teammateEndDoesNotReleaseAgentOwnedAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.beginActivity(paneID: paneID, BackgroundActivity.lifecycle(id: "a1", kind: .teammate, label: "ada", status: "running"))
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))

        manager.endActivity(paneID: paneID, label: "ada")

        #expect(manager.sessionStates[paneID] == .needsAttention)
        #expect(manager.attentionOwners[paneID] == .agent("a1"))
    }

    /// The label fallback still releases when the ended entry genuinely is an agent.
    @Test func agentEndByLabelReleasesItsOwnAttention() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.beginActivity(paneID: paneID, BackgroundActivity.lifecycle(id: "a1", kind: .agent, label: "explore", status: "running"))
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))

        manager.endActivity(paneID: paneID, label: "explore")

        #expect(manager.sessionStates[paneID] == .idle)
        #expect(manager.attentionOwners[paneID] == nil)
    }

    // MARK: - sessionStateDidChange (notifier seam)

    /// Every state write is published with its effective transition — the hook the
    /// notifier's owner (`IPCCommandHandler`) installs to drive the banners.
    @Test func sessionStateWritePublishesTransition() {
        let manager = PaneStatusManager()
        let paneID = UUID()
        var seen: [(UUID, ClaudeSessionState?, ClaudeSessionState)] = []
        manager.sessionStateDidChange = { seen.append(($0, $1, $2)) }

        manager.setSessionState(paneID: paneID, state: .busy)
        manager.setSessionState(paneID: paneID, state: .idle)

        #expect(seen.count == 2)
        #expect(seen[0].0 == paneID && seen[0].1 == nil && seen[0].2 == .busy)
        #expect(seen[1].1 == .busy && seen[1].2 == .idle)
    }

    /// A write the manager refuses (`canReplace`, or the attention owner) reports
    /// `old == new`, so the notifier sees a no-op rather than a phantom change.
    @Test func suppressedWritePublishesUnchangedState() {
        let manager = PaneStatusManager()
        let paneID = UUID()
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .main)

        var seen: [(ClaudeSessionState?, ClaudeSessionState)] = []
        manager.sessionStateDidChange = { seen.append(($1, $2)) }

        manager.setSessionState(paneID: paneID, state: .idle, origin: .main)              // canReplace refuses
        manager.setSessionState(paneID: paneID, state: .busy, origin: .agent("a1"))       // owner refuses

        #expect(seen.count == 2)
        #expect(seen.allSatisfy { $0.0 == .needsAttention && $0.1 == .needsAttention })
    }

    /// The bug this seam exists for: a released prompt used to be written straight
    /// into the dictionary, so the notifier never saw `needsAttention → idle` and no
    /// "Finished" banner fired for a turn that really had ended.
    @Test func attentionReleasePublishesTransition() {
        let manager = PaneStatusManager()
        let paneID = UUID()
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))

        var seen: [(ClaudeSessionState?, ClaudeSessionState)] = []
        manager.sessionStateDidChange = { seen.append(($1, $2)) }

        manager.endActivity(paneID: paneID, id: "a1")

        #expect(seen.count == 1)
        #expect(seen[0].0 == .needsAttention && seen[0].1 == .idle)
    }

    /// A release with other work still outstanding lands on `busy` — and publishes
    /// that, not `idle` (the notifier must not call the session done).
    @Test func attentionReleaseToBusyPublishesBusy() {
        let manager = PaneStatusManager()
        let paneID = UUID()
        manager.beginActivity(paneID: paneID, BackgroundActivity.lifecycle(id: "a1", kind: .agent, label: "explore", status: "running"))
        manager.beginActivity(paneID: paneID, BackgroundActivity.lifecycle(id: "a2", kind: .agent, label: "review", status: "running"))
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .agent("a1"))

        var seen: [(ClaudeSessionState?, ClaudeSessionState)] = []
        manager.sessionStateDidChange = { seen.append(($1, $2)) }

        manager.endActivity(paneID: paneID, id: "a1")

        #expect(seen.count == 1)
        #expect(seen[0].0 == .needsAttention && seen[0].1 == .busy)
    }

    /// An `endActivity` that releases nothing publishes nothing.
    @Test func unrelatedActivityEndPublishesNothing() {
        let manager = PaneStatusManager()
        let paneID = UUID()
        manager.setSessionState(paneID: paneID, state: .needsAttention, origin: .main)

        var count = 0
        manager.sessionStateDidChange = { _, _, _ in count += 1 }

        manager.endActivity(paneID: paneID, id: "a1")

        #expect(count == 0)
    }

    // MARK: - clearSessionState

    @Test func clearSessionStateClearsOnlySessionState() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setStatus(paneID: paneID, label: "Building")
        manager.setSessionState(paneID: paneID, state: .busy)
        manager.clearSessionState(paneID: paneID)

        #expect(manager.sessionStates[paneID] == nil)
        #expect(manager.statuses[paneID]?.label == "Building")
    }

    // MARK: - clearStatus clears both

    @Test func clearStatusClearsBothDictionaries() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setStatus(paneID: paneID, label: "Testing")
        manager.setSessionState(paneID: paneID, state: .active)
        manager.clearStatus(paneID: paneID)

        #expect(manager.statuses[paneID] == nil)
        #expect(manager.sessionStates[paneID] == nil)
    }

    // MARK: - clearAll clears both

    @Test func clearAllClearsBothDictionaries() {
        let manager = PaneStatusManager()
        let a = UUID(), b = UUID()

        manager.setStatus(paneID: a, label: "A")
        manager.setSessionState(paneID: a, state: .busy)
        manager.setStatus(paneID: b, label: "B")
        manager.setSessionState(paneID: b, state: .idle)

        manager.clearAll(for: [a])

        #expect(manager.statuses[a] == nil)
        #expect(manager.sessionStates[a] == nil)
        #expect(manager.statuses[b]?.label == "B")
        #expect(manager.sessionStates[b] == .idle)
    }

    // MARK: - sessionState(for:)

    @Test func sessionStateForReturnsNilWhenAbsent() {
        let manager = PaneStatusManager()
        #expect(manager.sessionState(for: UUID()) == nil)
    }

    @Test func sessionStateForReturnsStoredState() {
        let manager = PaneStatusManager()
        let paneID = UUID()
        manager.setSessionState(paneID: paneID, state: .needsAttention)
        #expect(manager.sessionState(for: paneID) == .needsAttention)
    }

    // MARK: - sessionStates(in:)

    @Test func sessionStatesInSessionReturnsSortedNonInactive() {
        let manager = PaneStatusManager()
        let session = makeSessionWithClaudeAndTerminal()

        let pane1 = claudePaneID(session)
        let pane2 = terminalPaneID(session)

        manager.setSessionState(paneID: pane1, state: .idle)
        manager.setSessionState(paneID: pane2, state: .busy)

        let result = manager.sessionStates(in: session)

        #expect(result.count == 2)
        #expect(result[0].state == .busy)
        #expect(result[1].state == .idle)
    }

    @Test func sessionStatesInSessionExcludesInactive() {
        let manager = PaneStatusManager()
        let session = makeSession()
        let paneID = claudePaneID(session)

        manager.setSessionState(paneID: paneID, state: .inactive)

        let result = manager.sessionStates(in: session)
        #expect(result.isEmpty)
    }

    @Test func sessionStatesInSessionExcludesPanesOutsideSession() {
        let manager = PaneStatusManager()
        let session = makeSession()

        manager.setSessionState(paneID: UUID(), state: .busy)

        let result = manager.sessionStates(in: session)
        #expect(result.isEmpty)
    }

    @Test func sessionStatesInSessionReturnsEmptyWhenNone() {
        let manager = PaneStatusManager()
        let session = makeSession()

        let result = manager.sessionStates(in: session)
        #expect(result.isEmpty)
    }

    // MARK: - aggregateSessionState(in:)

    @Test func aggregateSessionStateNilWhenNoSession() {
        let manager = PaneStatusManager()
        let session = makeSession()
        #expect(manager.aggregateSessionState(in: session) == nil)
    }

    @Test func aggregateSessionStateReturnsSinglePaneState() {
        let manager = PaneStatusManager()
        let session = makeSession()
        let paneID = claudePaneID(session)

        manager.setSessionState(paneID: paneID, state: .active)
        #expect(manager.aggregateSessionState(in: session) == .active)
    }

    @Test func aggregateSessionStateExcludesInactive() {
        let manager = PaneStatusManager()
        let session = makeSession()
        let paneID = claudePaneID(session)

        manager.setSessionState(paneID: paneID, state: .inactive)
        #expect(manager.aggregateSessionState(in: session) == nil)
    }

    /// A session with several panes rolls up to the highest-priority state
    /// (needsAttention > failed > busy > active > idle), which drives the single
    /// dot on the session's sidebar row.
    @Test func aggregateSessionStatePicksHighestPriorityAcrossPanes() {
        let manager = PaneStatusManager()
        let session = makeSessionWithClaudeAndTerminal()
        let pane1 = claudePaneID(session)
        let pane2 = terminalPaneID(session)

        manager.setSessionState(paneID: pane1, state: .idle)
        manager.setSessionState(paneID: pane2, state: .busy)
        #expect(manager.aggregateSessionState(in: session) == .busy)

        // A higher-priority state on any pane wins.
        manager.setSessionState(paneID: pane1, state: .needsAttention)
        #expect(manager.aggregateSessionState(in: session) == .needsAttention)
    }

    // MARK: - topSessionPane(in:)

    @Test func topSessionPaneReturnsWinningPaneAndState() {
        let manager = PaneStatusManager()
        let session = makeSessionWithClaudeAndTerminal()
        let pane1 = claudePaneID(session)
        let pane2 = terminalPaneID(session)

        manager.setSessionState(paneID: pane1, state: .idle)
        manager.setSessionState(paneID: pane2, state: .needsAttention)

        let top = manager.topSessionPane(in: session)
        #expect(top?.paneID == pane2)
        #expect(top?.state == .needsAttention)
    }

    @Test func topSessionPaneNilWhenNoActiveState() {
        let manager = PaneStatusManager()
        let session = makeSession()
        #expect(manager.topSessionPane(in: session) == nil)
    }

    // MARK: - hasSessionState(_:in:)

    @Test func hasSessionStateDetectsPresence() {
        let manager = PaneStatusManager()
        let session = makeSession()
        let paneID = claudePaneID(session)

        manager.setSessionState(paneID: paneID, state: .busy)
        #expect(manager.hasSessionState(.busy, in: session))
        #expect(!manager.hasSessionState(.needsAttention, in: session))
    }

    // MARK: - Per-PVM mirror (dual-write via pane registry)

    @Test func dualWritesMirrorToOwnerPaneViewModel() {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .terminal)
        let paneID = pvm.splitTree.focusedPaneID

        // Use the shared registry path: register, set, read from PVM.
        manager.registerPane(paneID, owner: pvm)

        manager.setSessionState(paneID: paneID, state: .busy)
        #expect(pvm.sessionState(forPane: paneID) == .busy)

        manager.clearSessionState(paneID: paneID)
        #expect(pvm.sessionState(forPane: paneID) == nil)

        manager.setStatus(paneID: paneID, label: "Hello")
        #expect(pvm.paneStatus(forPane: paneID)?.label == "Hello")

        manager.clearStatus(paneID: paneID)
        #expect(pvm.paneStatus(forPane: paneID) == nil)
    }

    @Test func unregisterStopsMirroring() {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .terminal)
        let paneID = pvm.splitTree.focusedPaneID

        manager.registerPane(paneID, owner: pvm)
        manager.unregisterPane(paneID)

        manager.setSessionState(paneID: paneID, state: .busy)

        #expect(manager.sessionState(for: paneID) == .busy)  // manager still has it
        #expect(pvm.sessionState(forPane: paneID) == nil)    // mirror NOT updated
    }

    // MARK: - setLastPrompt

    @Test func setLastPromptStoresText() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setLastPrompt(paneID: paneID, text: "fix the bug")

        #expect(manager.lastPrompts[paneID] == "fix the bug")
    }

    @Test func setLastPromptReplacesExisting() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setLastPrompt(paneID: paneID, text: "First")
        manager.setLastPrompt(paneID: paneID, text: "Second")

        #expect(manager.lastPrompts[paneID] == "Second")
        #expect(manager.lastPrompts.count == 1)
    }

    @Test func setLastPromptDoesNotAffectStatuses() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setLastPrompt(paneID: paneID, text: "prompt")

        #expect(manager.statuses[paneID] == nil)
        #expect(manager.sessionStates[paneID] == nil)
        #expect(manager.lastPrompts[paneID] == "prompt")
    }

    @Test func setLastPromptMirrorsToOwnerPaneViewModel() {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .terminal)
        let paneID = pvm.splitTree.focusedPaneID

        manager.registerPane(paneID, owner: pvm)

        manager.setLastPrompt(paneID: paneID, text: "run the tests")
        #expect(pvm.paneLastPrompts[paneID] == "run the tests")
    }

    // MARK: - clearStatus / clearAll clear the prompt

    @Test func clearStatusClearsLastPrompt() {
        let manager = PaneStatusManager()
        let pvm = PaneViewModel(kind: .terminal)
        let paneID = pvm.splitTree.focusedPaneID

        manager.registerPane(paneID, owner: pvm)
        manager.setLastPrompt(paneID: paneID, text: "prompt")
        manager.clearStatus(paneID: paneID)

        #expect(manager.lastPrompts[paneID] == nil)
        #expect(pvm.paneLastPrompts[paneID] == nil)
    }

    @Test func clearAllClearsLastPrompt() {
        let manager = PaneStatusManager()
        let pvmA = PaneViewModel(kind: .terminal)
        let pvmB = PaneViewModel(kind: .terminal)
        let a = pvmA.splitTree.focusedPaneID
        let b = pvmB.splitTree.focusedPaneID

        manager.registerPane(a, owner: pvmA)
        manager.registerPane(b, owner: pvmB)
        manager.setLastPrompt(paneID: a, text: "A")
        manager.setLastPrompt(paneID: b, text: "B")

        manager.clearAll(for: [a])

        #expect(manager.lastPrompts[a] == nil)
        #expect(pvmA.paneLastPrompts[a] == nil)
        #expect(manager.lastPrompts[b] == "B")
        #expect(pvmB.paneLastPrompts[b] == "B")
    }
}
