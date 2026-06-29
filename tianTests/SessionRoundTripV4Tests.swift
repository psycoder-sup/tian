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

    // FR-24 — restored Claude panes re-seed the autostart command (run via
    // TIAN_AUTOSTART_CMD from the bundled .zshrc), not as injected keystrokes.
    @Test func restoredClaudePanesReinjectClaudeCommand() throws {
        let collection = WorkspaceCollection(workingDirectory: "/tmp")
        let snapshot = SessionSerializer.snapshot(from: collection)
        let data = try SessionSerializer.encode(snapshot)
        let decoded = try SessionRestorer.decode(from: data)
        let restored = SessionRestorer.buildWorkspaceCollection(from: decoded)
        let claudeTab = restored.workspaces[0].spaceCollection.activeSpace!.claudeSection.tabs[0]
        let paneID = claudeTab.paneViewModel.splitTree.focusedPaneID
        let view = claudeTab.paneViewModel.surfaceView(for: paneID)
        #expect(view?.environmentVariables["TIAN_AUTOSTART_CMD"] == "claude")
    }

    // Schema version bumped to 6 (v6 adds activeTab field).
    @Test func snapshotEmitsCurrentVersion() {
        #expect(SessionSerializer.currentVersion == 6)
    }

    // MARK: - parentSpaceID (orchestrator → implementer link)

    /// The orchestrator → implementer link survives snapshot → encode → decode →
    /// validate → build round-trip, both in the decoded state and the live model.
    @Test func roundTripPreservesParentSpaceID() throws {
        let collection = WorkspaceCollection(workingDirectory: "/tmp")
        let spaceColl = collection.activeWorkspace!.spaceCollection
        let parent = spaceColl.activeSpace!
        let child = spaceColl.createSpace(name: "impl", workingDirectory: "/tmp", focusOnCreate: false)
        child.parentSpaceID = parent.id

        let snapshot = SessionSerializer.snapshot(from: collection)
        let data = try SessionSerializer.encode(snapshot)
        let decoded = try SessionRestorer.decode(from: data)

        let restoredChild = decoded.workspaces[0].spaces.first { $0.id == child.id }
        #expect(restoredChild?.parentSpaceID == parent.id)

        // Validate (keeps an in-workspace parent) then build the live hierarchy.
        let validated = try SessionRestorer.validate(decoded)
        let built = SessionRestorer.buildWorkspaceCollection(from: validated)
        let liveChild = built.workspaces[0].spaceCollection.spaces.first { $0.id == child.id }
        #expect(liveChild?.parentSpaceID == parent.id)
    }

    /// Validation drops a dangling parent link (orchestrator no longer present)
    /// so the sidebar never renders a phantom child.
    @Test func validateDropsDanglingParentSpaceID() throws {
        let collection = WorkspaceCollection(workingDirectory: "/tmp")
        let spaceColl = collection.activeWorkspace!.spaceCollection
        let child = spaceColl.activeSpace!
        child.parentSpaceID = UUID() // points at a Space not in the workspace

        let snapshot = SessionSerializer.snapshot(from: collection)
        let data = try SessionSerializer.encode(snapshot)
        let decoded = try SessionRestorer.decode(from: data)
        let validated = try SessionRestorer.validate(decoded)

        let restored = validated.workspaces[0].spaces.first { $0.id == child.id }
        #expect(restored?.parentSpaceID == nil)
    }

    /// Older session JSON without the `parentSpaceID` key decodes as nil — the
    /// Optional + defaulted field means no migration or version bump is needed.
    @Test func oldFormatSpaceStateDecodesParentAsNil() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "legacy",
          "claudeSection": {"id":"\(UUID().uuidString)","kind":"claude","tabs":[]},
          "terminalSection": {"id":"\(UUID().uuidString)","kind":"terminal","tabs":[]},
          "terminalVisible": false,
          "dockPosition": "bottom",
          "splitRatio": 0.7,
          "focusedSectionKind": "claude"
        }
        """
        let decoded = try JSONDecoder().decode(SpaceState.self, from: Data(json.utf8))
        #expect(decoded.parentSpaceID == nil)
    }
}
