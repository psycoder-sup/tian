import Testing
import Foundation
@testable import tian

@MainActor
struct CustomLaunchCommandTests {
    /// A preset / "Run Custom Claude" starts the session's Claude pane so it
    /// autostarts the custom command (via TIAN_AUTOSTART_CMD) and records it as
    /// the pane's restore-command override.
    @Test func startClaudeWithCustomCommandSeedsAutostartEnv() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        session.startClaude(customCommand: "claude --chrome")

        let claude = try #require(session.claudePane)
        let paneID = claude.splitTree.focusedPaneID
        let view = claude.surfaceView(for: paneID)
        #expect(view?.environmentVariables["TIAN_AUTOSTART_CMD"] == "claude --chrome")
        #expect(claude.restoreCommand(for: paneID) == "claude --chrome")
    }

    /// Without a custom command the session's Claude pane uses the default
    /// autostart command and records no per-pane override.
    @Test func startClaudeWithoutCustomCommandUsesDefault() throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")

        let claude = try #require(session.claudePane)
        let paneID = claude.splitTree.focusedPaneID
        let view = claude.surfaceView(for: paneID)
        #expect(view?.environmentVariables["TIAN_AUTOSTART_CMD"] == TianSettings.shared.effectiveClaudeCommand)
        #expect(claude.restoreCommand(for: paneID) == nil)
    }
}
