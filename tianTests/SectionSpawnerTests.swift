import Testing
import Foundation
@testable import tian

@MainActor
struct SectionSpawnerTests {
    @Test func claudeSpawnerInjectsClaudeCommandAndEnv() {
        let view = TerminalSurfaceView()
        let env: [String: String] = ["TIAN_PANE_ID": "abc"]
        SectionSpawner.configure(view: view, kind: .claude, workingDirectory: "/tmp", environmentVariables: env)
        // Claude launches via TIAN_AUTOSTART_CMD (run by the bundled .zshrc),
        // not by injecting "claude\n" as keystrokes — so initialInput stays nil.
        #expect(view.initialInput == nil)
        #expect(view.environmentVariables["TIAN_AUTOSTART_CMD"] == "claude")
        #expect(view.initialWorkingDirectory == "/tmp")
        #expect(view.environmentVariables["TIAN_PANE_ID"] == "abc")
    }

    @Test func customClaudeCommandFlowsIntoAutostartEnv() {
        let original = TianSettings.shared.claudeCommand
        defer { TianSettings.shared.claudeCommand = original }

        TianSettings.shared.claudeCommand = "claude --chrome"
        let env = SectionSpawner.autostartEnvironment(kind: .claude, base: [:])
        #expect(env["TIAN_AUTOSTART_CMD"] == "claude --chrome")
    }

    @Test func launchBadgeIsNilForDefaultAndEmptyCommands() {
        #expect(ClaudeLaunchBadge.forCommand("claude") == nil)
        #expect(ClaudeLaunchBadge.forCommand("  claude  ") == nil)
        #expect(ClaudeLaunchBadge.forCommand("") == nil)
        #expect(ClaudeLaunchBadge.forCommand("   ") == nil)
    }

    @Test func launchBadgeMapsKnownAndUnknownVariants() {
        #expect(ClaudeLaunchBadge.forCommand("claude --chrome")?.symbol == "globe")
        #expect(ClaudeLaunchBadge.forCommand("headroom wrap claude")?.symbol == "rectangle.compress.vertical")
        #expect(ClaudeLaunchBadge.forCommand("some-other-wrapper claude")?.symbol == "wand.and.stars")
        // The full (trimmed) command is preserved for the tooltip / a11y label.
        #expect(ClaudeLaunchBadge.forCommand("  claude --chrome ")?.command == "claude --chrome")
    }

    @Test func customClaudeTabRecordsLaunchCommandForBadge() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.createTab(in: space.claudeSection, workingDirectory: "/tmp", customCommand: "claude --chrome")
        #expect(tab.launchCommand == "claude --chrome")
        #expect(tab.claudeLaunchBadge?.symbol == "globe")
    }

    @Test func terminalTabHasNoLaunchBadge() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()
        let tab = space.createTab(in: space.terminalSection, workingDirectory: "/tmp")
        #expect(tab.launchCommand == nil)
        #expect(tab.claudeLaunchBadge == nil)
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
        #expect(newView?.environmentVariables["TIAN_AUTOSTART_CMD"] == "claude")
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
