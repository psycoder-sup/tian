import Testing
import Foundation
@testable import tian

@MainActor
struct SectionSpawnerTests {
    @Test func claudeSpawnerInjectsClaudeCommandAndEnv() {
        let view = TerminalSurfaceView()
        let env: [String: String] = ["TIAN_PANE_ID": "abc"]
        SectionSpawner.configure(view: view, kind: .claude, workingDirectory: "/tmp", environmentVariables: env)
        #expect(view.initialInput == "claude\n")
        #expect(view.initialWorkingDirectory == "/tmp")
        #expect(view.environmentVariables["TIAN_PANE_ID"] == "abc")
    }

    @Test func terminalSpawnerLeavesInitialInputNil() {
        let view = TerminalSurfaceView()
        let env: [String: String] = ["TIAN_PANE_ID": "xyz"]
        SectionSpawner.configure(view: view, kind: .terminal, workingDirectory: "/tmp", environmentVariables: env)
        #expect(view.initialInput == nil)
        #expect(view.environmentVariables["TIAN_PANE_ID"] == "xyz")
    }

    @Test func splittingClaudePaneProducesClaudePane() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let claudeTab = space.claudeSection.tabs[0]
        let newID = claudeTab.paneViewModel.splitPane(direction: .horizontal)
        #expect(newID != nil)
        let newView = claudeTab.paneViewModel.surfaceView(for: newID!)
        #expect(newView?.initialInput == "claude\n")
    }

    @Test func claudeExitWithNonZeroCodeClosesPane() async throws {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.claudeSection.tabs[0]
        let paneID = try #require(tab.paneViewModel.splitTree.focusedPaneID)
        let surfaceID = try #require(tab.paneViewModel.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceExitedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID, "exitCode": UInt32(1)]
        )
        try await Task.sleep(for: .milliseconds(10))
        #expect(tab.paneViewModel.paneStates[paneID] == nil)
    }

    @Test func terminalExitWithNonZeroCodeKeepsPaneInExitedState() async throws {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()
        let tab = space.terminalSection.tabs[0]
        let paneID = try #require(tab.paneViewModel.splitTree.focusedPaneID)
        let surfaceID = try #require(tab.paneViewModel.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceExitedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID, "exitCode": UInt32(1)]
        )
        try await Task.sleep(for: .milliseconds(10))
        if case .exited(let code) = tab.paneViewModel.paneStates[paneID] {
            #expect(code == 1)
        } else {
            Issue.record("Expected .exited state")
        }
    }
}
