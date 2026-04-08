import Testing
import Foundation
@testable import aterm

@MainActor
struct PaneStatusManagerTests {

    // MARK: - setStatus (FR-21)

    @Test func setStatusStoresLabel() {
        let manager = PaneStatusManager()
        let paneID = UUID()

        manager.setStatus(paneID: paneID, label: "Thinking...")

        #expect(manager.statuses[paneID]?.label == "Thinking...")
        #expect(manager.statuses[paneID]?.updatedAt != nil)
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

        let tab = TabModel()
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        // Clean up any prior state
        shared.clearStatus(paneID: paneID)

        shared.setStatus(paneID: paneID, label: "Running")
        #expect(shared.statuses[paneID]?.label == "Running")

        tab.paneViewModel.closePane(paneID: paneID)

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

    @Test func latestStatusReturnsMostRecentInSpace() {
        let manager = PaneStatusManager()
        let tab1 = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab1)
        let tab2 = space.createTab()

        let pane1 = tab1.paneViewModel.splitTree.focusedPaneID
        let pane2 = tab2.paneViewModel.splitTree.focusedPaneID

        manager.setStatus(paneID: pane1, label: "Older")
        manager.setStatus(paneID: pane2, label: "Newer")

        let latest = manager.latestStatus(in: space)
        #expect(latest?.label == "Newer")
    }

    @Test func latestStatusReturnsNilWhenEmpty() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)

        #expect(manager.latestStatus(in: space) == nil)
    }

    @Test func latestStatusIgnoresPanesOutsideSpace() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)

        manager.setStatus(paneID: UUID(), label: "Outside")

        #expect(manager.latestStatus(in: space) == nil)
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

    @Test func sessionStatesInSpaceReturnsSortedNonInactive() {
        let manager = PaneStatusManager()
        let tab1 = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab1)
        let tab2 = space.createTab()

        let pane1 = tab1.paneViewModel.splitTree.focusedPaneID
        let pane2 = tab2.paneViewModel.splitTree.focusedPaneID

        manager.setSessionState(paneID: pane1, state: .idle)
        manager.setSessionState(paneID: pane2, state: .busy)

        let result = manager.sessionStates(in: space)

        #expect(result.count == 2)
        #expect(result[0].state == .busy)
        #expect(result[1].state == .idle)
    }

    @Test func sessionStatesInSpaceExcludesInactive() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        manager.setSessionState(paneID: paneID, state: .inactive)

        let result = manager.sessionStates(in: space)
        #expect(result.isEmpty)
    }

    @Test func sessionStatesInSpaceExcludesPanesOutsideSpace() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)

        manager.setSessionState(paneID: UUID(), state: .busy)

        let result = manager.sessionStates(in: space)
        #expect(result.isEmpty)
    }

    @Test func sessionStatesInSpaceReturnsEmptyWhenNone() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)

        let result = manager.sessionStates(in: space)
        #expect(result.isEmpty)
    }
}
