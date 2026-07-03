import AppKit
import Testing
import CoreGraphics
import Foundation
@testable import tian

/// FR-19 — cross-area directional navigation between a Session's Claude pane
/// and its terminal panel. Fixtures build a real `Session` (Claude pane +
/// terminal panel) and drive `SessionSplitNavigation`, so the tests track the
/// same `SessionLayout` geometry the content view renders.
@MainActor
struct SessionSplitNavigationTests {

    private let container = CGSize(width: 800, height: 600)

    /// A session with a live Claude pane and a visible terminal panel docked
    /// as requested.
    private func makeSession(dock: DockPosition) -> Session {
        let session = Session(customName: "nav", workingDirectory: "/tmp")
        session.showTerminal()
        session.setDockPosition(dock)
        return session
    }

    private func navigator(_ session: Session) -> SessionSplitNavigation {
        SessionSplitNavigation(session: session, containerSize: container)
    }

    // MARK: - Cross-divider (right-docked)

    @Test func focusRightCrossesDividerIntoTerminal() {
        let session = makeSession(dock: .right)
        let claudeID = session.claudePaneID!
        let terminalID = session.terminalPanel!.splitTree.focusedPaneID

        let target = navigator(session).neighbor(from: claudeID, direction: .right)
        #expect(target?.paneID == terminalID)
        #expect(target?.kind == .terminal)
    }

    @Test func focusLeftFromTerminalFindsClaude() {
        let session = makeSession(dock: .right)
        let claudeID = session.claudePaneID!
        let terminalID = session.terminalPanel!.splitTree.focusedPaneID

        let target = navigator(session).neighbor(from: terminalID, direction: .left)
        #expect(target?.paneID == claudeID)
        #expect(target?.kind == .claude)
    }

    @Test func focusRightFromRightmostPaneIsNoOp() {
        let session = makeSession(dock: .right)
        let terminalID = session.terminalPanel!.splitTree.focusedPaneID
        #expect(navigator(session).neighbor(from: terminalID, direction: .right) == nil)
    }

    // MARK: - Cross-divider (bottom-docked)

    @Test func focusDownCrossesBottomDockedDividerIntoTerminal() {
        // New sessions dock the terminal at the bottom (Claude on top), so
        // from the Claude pane .down crosses the divider into Terminal.
        let session = makeSession(dock: .bottom)
        let claudeID = session.claudePaneID!
        let terminalID = session.terminalPanel!.splitTree.focusedPaneID

        let target = navigator(session).neighbor(from: claudeID, direction: .down)
        #expect(target?.paneID == terminalID)
        #expect(target?.kind == .terminal)
    }

    @Test func focusUpFromTerminalFindsClaude() {
        let session = makeSession(dock: .bottom)
        let claudeID = session.claudePaneID!
        let terminalID = session.terminalPanel!.splitTree.focusedPaneID

        let target = navigator(session).neighbor(from: terminalID, direction: .up)
        #expect(target?.paneID == claudeID)
        #expect(target?.kind == .claude)
    }

    // MARK: - Terminal hidden

    @Test func hiddenTerminalHasNoCrossAreaNeighbor() {
        // When the terminal panel is hidden the Claude pane fills the whole
        // container and there is nothing to cross into.
        let session = makeSession(dock: .bottom)
        session.hideTerminal()
        let claudeID = session.claudePaneID!

        #expect(navigator(session).neighbor(from: claudeID, direction: .down) == nil)
        #expect(navigator(session).neighbor(from: claudeID, direction: .right) == nil)
    }

    // MARK: - Empty-Claude

    @Test func emptyClaudeSessionHasNoNeighborFromTerminal() {
        // With no live Claude pane there is no frame to navigate into. A Claude
        // exit now closes the session, so this state is only ever transient —
        // build it directly with a nil Claude pane rather than via a mutator.
        let terminal = PaneViewModel(workingDirectory: "/tmp", kind: .terminal)
        let session = Session(
            customName: "nav",
            claudePane: nil,
            terminalPanel: terminal,
            terminalVisible: true,
            dockPosition: .bottom
        )
        let terminalID = session.terminalPanel!.splitTree.focusedPaneID

        #expect(session.hasLiveClaudePane == false)
        #expect(navigator(session).neighbor(from: terminalID, direction: .up) == nil)
    }
}
