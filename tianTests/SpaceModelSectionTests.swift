import Testing
import Foundation
@testable import tian

@MainActor
struct SpaceModelSectionTests {
    @Test func newSpaceHasOneClaudeSection() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        #expect(space.claudeSection.kind == .claude)
        #expect(space.claudeSection.tabs.count == 1)
    }

    @Test func newSpaceStartsWithTerminalHidden() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        #expect(space.terminalVisible == false)
    }

    @Test func initialClaudePaneIsSeededWithClaudeCommand() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.claudeSection.tabs[0]
        let paneID = tab.paneViewModel.splitTree.focusedPaneID
        let view = tab.paneViewModel.surfaceView(for: paneID)
        #expect(view?.initialInput == "claude\n")
    }

    @Test func tabOperationsOnOneSectionDoNotAffectOther() {
        let space = makeSpaceWithBothSections()
        let claudeTabCountBefore = space.claudeSection.tabs.count
        space.terminalSection.createTab(workingDirectory: "/tmp")
        #expect(space.claudeSection.tabs.count == claudeTabCountBefore)
    }

    @Test func closingLastClaudeTabKeepsSpaceAliveWhenTerminalHasPanes() {
        let space = makeSpaceWithBothSections()
        let claudeTabID = space.claudeSection.tabs[0].id
        space.claudeSection.removeTab(id: claudeTabID)
        #expect(space.claudeSection.tabs.isEmpty)
        #expect(space.terminalSection.tabs.isEmpty == false)
        #expect(space.isEffectivelyEmpty == false)
    }

    @Test func closingLastClaudeTabDoesNotCloseSpaceEvenIfTerminalEmpty() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        var spaceClosed = false
        space.onSpaceClose = { spaceClosed = true }
        let claudeTabID = space.claudeSection.tabs[0].id
        space.claudeSection.removeTab(id: claudeTabID)
        #expect(spaceClosed == false)
        #expect(space.isEffectivelyEmpty == true)
    }

    @Test func explicitCloseRequestFromEmptyClaudeClosesSpace() async {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        var spaceClosed = false
        space.onSpaceClose = { spaceClosed = true }
        let claudeTabID = space.claudeSection.tabs[0].id
        space.claudeSection.removeTab(id: claudeTabID)
        await space.requestSpaceClose()
        #expect(spaceClosed == true)
    }

    @Test func closingLastTerminalTabAutoHidesSection() {
        let space = makeSpaceWithBothSections()
        space.terminalVisible = true
        let termTabID = space.terminalSection.tabs[0].id
        space.terminalSection.removeTab(id: termTabID)
        #expect(space.terminalVisible == false)
    }

    @Test func hideTerminalPreservesTabsAndPanes() {
        let space = makeSpaceWithBothSections()
        space.showTerminal()
        space.terminalSection.createTab(workingDirectory: "/tmp")
        let expectedTabIDs = space.terminalSection.tabs.map(\.id)
        space.hideTerminal()
        #expect(space.terminalSection.tabs.map(\.id) == expectedTabIDs)
        space.showTerminal()
        #expect(space.terminalSection.tabs.map(\.id) == expectedTabIDs)
    }

    @Test func resetTerminalSectionClearsAllTabs() {
        let space = makeSpaceWithBothSections()
        space.showTerminal()
        space.terminalSection.createTab(workingDirectory: "/tmp")
        space.resetTerminalSection()
        #expect(space.terminalSection.tabs.isEmpty)
    }

    @Test func defaultDockPositionIsRight() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        #expect(space.dockPosition == .right)
    }

    @Test func cycleFocusedSectionMovesFocusBetweenSections() {
        let space = makeSpaceWithBothSections()
        space.focusedSectionKind = .claude
        space.cycleFocusedSection()
        #expect(space.focusedSectionKind == .terminal)
    }

    @Test func cycleFocusedSectionNoOpWhenTargetEmpty() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.focusedSectionKind = .claude
        space.cycleFocusedSection()
        #expect(space.focusedSectionKind == .claude)
    }

    private func makeSpaceWithBothSections() -> SpaceModel {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()
        return space
    }
}
