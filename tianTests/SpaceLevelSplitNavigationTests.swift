import AppKit
import Testing
import CoreGraphics
import Foundation
@testable import tian

@MainActor
struct SpaceLevelSplitNavigationTests {

    /// Build a frames dict via the real `SectionLayout` helper so the test
    /// tracks implementation constants (divider thickness, pixel minimums)
    /// rather than hardcoded magic numbers.
    private func makeFrames(
        claudeID: UUID,
        terminalID: UUID,
        container: CGSize,
        dock: DockPosition,
        ratio: Double
    ) -> [UUID: CGRect] {
        let layout = SectionLayout.computeFrames(
            containerSize: container,
            ratio: ratio,
            dock: dock,
            claudeMin: SectionDividerClamper.defaultClaudeMin,
            terminalMin: SectionDividerClamper.defaultTerminalMin,
            dividerThickness: SectionDividerView.thickness
        )
        return [claudeID: layout.claude, terminalID: layout.terminal]
    }

    // FR-19 (cross-section, right-docked)
    @Test func focusRightCrossesSectionDivider() {
        let claude = UUID()
        let terminal = UUID()
        let frames = makeFrames(
            claudeID: claude, terminalID: terminal,
            container: CGSize(width: 800, height: 600),
            dock: .right, ratio: 0.7
        )
        #expect(SplitNavigation.neighbor(of: claude, direction: .right, in: frames) == terminal)
    }

    @Test func focusLeftFromTerminalFindsClaude() {
        let claude = UUID()
        let terminal = UUID()
        let frames = makeFrames(
            claudeID: claude, terminalID: terminal,
            container: CGSize(width: 800, height: 600),
            dock: .right, ratio: 0.7
        )
        #expect(SplitNavigation.neighbor(of: terminal, direction: .left, in: frames) == claude)
    }

    @Test func focusRightFromRightmostPaneIsNoOp() {
        let claude = UUID()
        let terminal = UUID()
        let frames = makeFrames(
            claudeID: claude, terminalID: terminal,
            container: CGSize(width: 800, height: 600),
            dock: .right, ratio: 0.7
        )
        #expect(SplitNavigation.neighbor(of: terminal, direction: .right, in: frames) == nil)
    }

    @Test func focusDownCrossesBottomDockedDivider() {
        let claude = UUID()
        let terminal = UUID()
        let frames = makeFrames(
            claudeID: claude, terminalID: terminal,
            container: CGSize(width: 800, height: 600),
            dock: .bottom, ratio: 0.7
        )
        #expect(SplitNavigation.neighbor(of: claude, direction: .down, in: frames) == terminal)
    }

    // Integration: SpaceLevelSplitNavigation collects frames from both
    // sections' active tabs and finds a cross-section neighbor.
    @Test func spaceLevelNavigationFindsClaudePaneFromTerminalPane() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()
        let claudePaneID = space.claudeSection.tabs[0].paneViewModel.splitTree.focusedPaneID
        let terminalPaneID = space.terminalSection.tabs[0].paneViewModel.splitTree.focusedPaneID

        let layout = SpaceLevelSplitNavigation(
            space: space,
            containerSize: CGSize(width: 1000, height: 600)
        )

        // From terminal pane, .left should cross the divider into Claude.
        let result = layout.neighbor(
            from: terminalPaneID,
            in: .terminal,
            direction: .left
        )
        #expect(result?.paneID == claudePaneID)
        #expect(result?.sectionKind == .claude)
    }
}

@MainActor
struct KeyBindingRegistryPhase3Tests {

    // FR-09 — Ctrl+` dispatches `.toggleTerminalSection`.
    @Test func ctrlBacktickMapsToToggleTerminalSection() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero, modifierFlags: .control,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "`", charactersIgnoringModifiers: "`",
            isARepeat: false, keyCode: 50
        ))
        #expect(KeyBindingRegistry.shared.action(for: event) == .toggleTerminalSection)
    }

    // FR-20 key binding — Cmd+Shift+` dispatches `.cycleSectionFocus`.
    @Test func cmdShiftBacktickMapsToCycleSectionFocus() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "~", charactersIgnoringModifiers: "`",
            isARepeat: false, keyCode: 50
        ))
        #expect(KeyBindingRegistry.shared.action(for: event) == .cycleSectionFocus)
    }
}
