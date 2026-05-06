import Testing
import Foundation
@testable import tian

@MainActor
struct SessionRoundTripV4Tests {

    // FR-23 — round-trip preserves section visibility, dock, ratio, tabs, panes.
    @Test func roundTripPreservesSectionVisibilityAndRatio() throws {
        let collection = WorkspaceCollection(workingDirectory: "/tmp")
        let space = collection.activeWorkspace!.spaceCollection.activeSpace!
        space.showTerminal()
        space.setDockPosition(.bottom)
        space.setSplitRatio(0.6)
        space.focusedSectionKind = .terminal   // simulate user focused Terminal at quit
        space.hideTerminal()  // preserve layout

        let snapshot = SessionSerializer.snapshot(from: collection)
        let data = try SessionSerializer.encode(snapshot)
        let decoded = try SessionRestorer.decode(from: data)

        let restored = decoded.workspaces[0].spaces[0]
        #expect(restored.terminalVisible == false)
        #expect(restored.dockPosition == .bottom)
        #expect(abs(restored.splitRatio - 0.6) < 0.0001)
        #expect(restored.terminalSection.tabs.count >= 1)
        #expect(restored.focusedSectionKind == .terminal)
    }

    // FR-24 — restored Claude panes re-inject `claude\n` initial input.
    @Test func restoredClaudePanesReinjectClaudeCommand() throws {
        let collection = WorkspaceCollection(workingDirectory: "/tmp")
        let snapshot = SessionSerializer.snapshot(from: collection)
        let data = try SessionSerializer.encode(snapshot)
        let decoded = try SessionRestorer.decode(from: data)
        let restored = SessionRestorer.buildWorkspaceCollection(from: decoded)
        let claudeTab = restored.workspaces[0].spaceCollection.activeSpace!.claudeSection.tabs[0]
        let paneID = claudeTab.paneViewModel.splitTree.focusedPaneID
        let view = claudeTab.paneViewModel.surfaceView(for: paneID)
        #expect(view?.initialInput == "claude\n")
    }

    // Schema version bumped to 6 (v6 adds activeTab field).
    @Test func snapshotEmitsCurrentVersion() {
        #expect(SessionSerializer.currentVersion == 6)
    }
}
