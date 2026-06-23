import Testing
import Foundation
@testable import tian

@MainActor
struct CustomLaunchCommandTests {
    /// Right-click "+" → preset / "Run Custom Claude" creates a Claude tab whose
    /// pane autostarts the custom command (via TIAN_AUTOSTART_CMD) and records it
    /// as the pane's restore-command override.
    @Test func createTabWithCustomCommandSeedsAutostartEnv() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.createTab(
            in: space.claudeSection,
            workingDirectory: "/tmp",
            customCommand: "claude --chrome"
        )
        let paneID = tab.paneViewModel.splitTree.focusedPaneID
        let view = tab.paneViewModel.surfaceView(for: paneID)
        #expect(view?.environmentVariables["TIAN_AUTOSTART_CMD"] == "claude --chrome")
        #expect(tab.paneViewModel.restoreCommand(for: paneID) == "claude --chrome")
    }

    /// Without a custom command the tab uses the default autostart command and
    /// records no per-pane override.
    @Test func createTabWithoutCustomCommandUsesDefault() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.createTab(in: space.claudeSection, workingDirectory: "/tmp")
        let paneID = tab.paneViewModel.splitTree.focusedPaneID
        let view = tab.paneViewModel.surfaceView(for: paneID)
        #expect(view?.environmentVariables["TIAN_AUTOSTART_CMD"] == TianSettings.shared.effectiveClaudeCommand)
        #expect(tab.paneViewModel.restoreCommand(for: paneID) == nil)
    }
}
