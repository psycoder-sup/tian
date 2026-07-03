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
}
