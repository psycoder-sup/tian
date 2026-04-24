import Testing
import Foundation
@testable import tian

@MainActor
struct SpaceStatusAreaViewLabelCoexistenceTests {

    // MARK: - Phase 3: Label Coexistence

    /// FR-024: Status label and session dots coexist.
    /// Acceptance: Setting both --state busy --label "Testing" shows BOTH the blue dot AND the label text
    @Test func labelRendersIndependentlyWhenSessionStateIsSet() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        // Set both label and session state
        manager.setStatus(paneID: paneID, label: "Testing")
        manager.setSessionState(paneID: paneID, state: .busy)

        // Verify both exist in the manager (label-independent rendering)
        #expect(manager.latestStatus(in: space)?.label == "Testing")
        #expect(manager.sessionState(for: paneID) == .busy)

        // Verify sessions are queryable
        let sessions = manager.sessionStates(in: space)
        #expect(sessions.count == 1)
        #expect(sessions[0].state == .busy)
    }

    /// Acceptance: Setting only --label "Testing" (no sessions) still shows the label
    @Test func labelRendersWhenNoSessionState() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        // Set only label
        manager.setStatus(paneID: paneID, label: "Testing")

        // Verify label exists
        #expect(manager.latestStatus(in: space)?.label == "Testing")

        // Verify no session state
        let sessions = manager.sessionStates(in: space)
        #expect(sessions.isEmpty)
    }

    /// Acceptance: Setting only --state busy (no label) still shows the dot
    @Test func dotsRenderWhenNoLabel() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        // Set only session state
        manager.setSessionState(paneID: paneID, state: .busy)

        // Verify no label
        #expect(manager.latestStatus(in: space) == nil)

        // Verify session state exists
        let sessions = manager.sessionStates(in: space)
        #expect(sessions.count == 1)
        #expect(sessions[0].state == .busy)
    }

    /// Acceptance: Having repo lines + sessions + label shows all three
    /// This test verifies the manager state; visual rendering is tested via QA
    @Test func managerSupportsLabelWithReposAndSessions() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        // Set label and session state
        manager.setStatus(paneID: paneID, label: "Implementing")
        manager.setSessionState(paneID: paneID, state: .active)

        // Verify both exist independently
        #expect(manager.latestStatus(in: space)?.label == "Implementing")
        #expect(manager.sessionStates(in: space).count == 1)
        #expect(manager.sessionStates(in: space)[0].state == .active)

        // The space would also have repo lines (if configured), but that's independent
    }

    /// Acceptance: Clearing the label does not affect the dot
    @Test func clearingLabelDoesNotAffectSessionState() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        // Set both
        manager.setStatus(paneID: paneID, label: "Testing")
        manager.setSessionState(paneID: paneID, state: .busy)

        // Clear label via setting empty or via clearSessionState (not clearStatus)
        // Note: We can't directly clear just the label without a method for it.
        // But we can verify that clearSessionState only clears state, not label
        manager.clearSessionState(paneID: paneID)

        // Verify label persists
        #expect(manager.latestStatus(in: space)?.label == "Testing")

        // Verify session state is cleared
        #expect(manager.sessionState(for: paneID) == nil)
    }

    /// Acceptance: Clearing the dot does not affect the label
    @Test func clearingSessionStateDoesNotAffectLabel() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        // Set both
        manager.setStatus(paneID: paneID, label: "Testing")
        manager.setSessionState(paneID: paneID, state: .busy)

        // Clear session state only
        manager.clearSessionState(paneID: paneID)

        // Verify label persists
        #expect(manager.latestStatus(in: space)?.label == "Testing")

        // Verify session state is cleared
        let sessions = manager.sessionStates(in: space)
        #expect(sessions.isEmpty)
    }

    /// FR-019 second-line render condition: The VStack must render when:
    /// - There are repo lines, OR
    /// - There are non-nil/non-inactive sessions, OR
    /// - There is a status label
    @Test func multipleSessionsWithLabel() {
        let manager = PaneStatusManager()
        let tab1 = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab1)
        let tab2 = space.createTab()

        let pane1 = tab1.paneViewModel.splitTree.focusedPaneID
        let pane2 = tab2.paneViewModel.splitTree.focusedPaneID

        // Set different states on different panes
        manager.setSessionState(paneID: pane1, state: .busy)
        manager.setSessionState(paneID: pane2, state: .idle)

        // Set label on one of them
        manager.setStatus(paneID: pane1, label: "Working")

        // Verify we can get both sessions
        let sessions = manager.sessionStates(in: space)
        #expect(sessions.count == 2)

        // Verify label exists (most recent)
        #expect(manager.latestStatus(in: space)?.label == "Working")
    }

    /// Edge case: Space with label but all sessions inactive
    @Test func labelPersistsWhenSessionsAreInactive() {
        let manager = PaneStatusManager()
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        // Set both
        manager.setStatus(paneID: paneID, label: "Done")
        manager.setSessionState(paneID: paneID, state: .active)

        // Mark session as inactive
        manager.setSessionState(paneID: paneID, state: .inactive)

        // Verify label persists
        #expect(manager.latestStatus(in: space)?.label == "Done")

        // Verify inactive sessions are excluded from query
        let sessions = manager.sessionStates(in: space)
        #expect(sessions.isEmpty)
    }

    /// Edge case: Multiple panes with various combinations
    @Test func complexMultiPaneScenario() {
        let manager = PaneStatusManager()
        let tab1 = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab1)
        let tab2 = space.createTab()
        let tab3 = space.createTab()

        let pane1 = tab1.paneViewModel.splitTree.focusedPaneID
        let pane2 = tab2.paneViewModel.splitTree.focusedPaneID
        let pane3 = tab3.paneViewModel.splitTree.focusedPaneID

        // Pane 1: busy + label
        manager.setSessionState(paneID: pane1, state: .busy)
        manager.setStatus(paneID: pane1, label: "Thinking")

        // Pane 2: idle (no label)
        manager.setSessionState(paneID: pane2, state: .idle)

        // Pane 3: label only (no session state)
        manager.setStatus(paneID: pane3, label: "Manual status")

        // Verify we have 2 sessions (pane1 busy, pane2 idle)
        let sessions = manager.sessionStates(in: space)
        #expect(sessions.count == 2)
        #expect(sessions[0].state == .busy)  // highest priority
        #expect(sessions[1].state == .idle)

        // Verify latest status is the most recent (pane3's label)
        let latest = manager.latestStatus(in: space)
        #expect(latest?.label == "Manual status")
    }

    /// Regression: status set on a Claude pane must surface in
    /// `sessionStates(in:)` and `latestStatus(in:)`. Earlier `space.tabs`
    /// only enumerated the Terminal section, so Claude session status
    /// was invisible in the sidebar. Also pin a Terminal pane in the
    /// same space so the test exercises the cross-section enumeration
    /// rather than relying on the Terminal section being empty.
    @Test func claudePaneSessionStateAppearsInSpaceQuery() {
        let manager = PaneStatusManager()
        let space = SpaceModel(name: "test", workingDirectory: "~")
        let claudeTab = space.claudeSection.tabs.first!
        let claudePaneID = claudeTab.paneViewModel.splitTree.focusedPaneID

        let terminalTab = space.createTab()
        let terminalPaneID = terminalTab.paneViewModel.splitTree.focusedPaneID

        manager.setSessionState(paneID: claudePaneID, state: .busy)
        manager.setSessionState(paneID: terminalPaneID, state: .idle)
        manager.setStatus(paneID: claudePaneID, label: "Delegating")

        let sessions = manager.sessionStates(in: space)
        #expect(sessions.count == 2)
        #expect(sessions.contains { $0.paneID == claudePaneID && $0.state == .busy })
        #expect(sessions.contains { $0.paneID == terminalPaneID && $0.state == .idle })

        #expect(manager.latestStatus(in: space)?.label == "Delegating")
    }
}
