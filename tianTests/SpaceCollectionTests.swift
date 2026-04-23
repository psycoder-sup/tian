import Testing
import Foundation
@testable import tian

@MainActor
struct TabModelTests {
    @Test func initCreatesOnePaneViewModel() {
        let tab = TabModel()
        #expect(tab.customName == nil)
        #expect(tab.displayName == "tian") // defaults to terminal title
        #expect(tab.paneViewModel.splitTree.leafCount == 1)
    }

    @Test func customNameOverridesDisplayName() {
        let tab = TabModel(customName: "My Tab")
        #expect(tab.customName == "My Tab")
        #expect(tab.displayName == "My Tab")
    }

    @Test func onEmptyFiredWhenLastPaneClosed() async {
        let tab = TabModel()
        var fired = false
        tab.onEmpty = { fired = true }

        let paneID = tab.paneViewModel.splitTree.focusedPaneID
        tab.paneViewModel.closePane(paneID: paneID)
        #expect(fired)
    }

    @Test func titleDelegatesFromPaneViewModel() {
        let tab = TabModel()
        #expect(tab.title == "tian")
        #expect(tab.displayName == "tian") // no customName, falls through to title
    }
}

@MainActor
struct SpaceModelTests {
    @Test func initWithOneTab() {
        let tab = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab)
        #expect(space.tabs.count == 1)
        #expect(space.activeTabID == tab.id)
        #expect(space.activeTab?.id == tab.id)
    }

    @Test func createTabAppendsAndActivates() {
        let tab = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab)
        space.createTab()
        #expect(space.tabs.count == 2)
        #expect(space.activeTabID == space.tabs[1].id)
    }

    @Test func removeTabActivatesNearest() {
        let tab1 = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab1)
        space.createTab()
        space.createTab()
        // 3 tabs, active is tab 3 (index 2)
        let tab3ID = space.activeTabID
        let tab2ID = space.tabs[1].id

        space.removeTab(id: tab3ID)
        #expect(space.tabs.count == 2)
        // Should activate tab 2 (prefer left)
        #expect(space.activeTabID == tab2ID)
    }

    @Test func removeFirstTabActivatesRight() {
        let tab1 = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab1)
        space.createTab()
        space.activateTab(id: tab1.id) // activate tab 1
        let tab2ID = space.tabs[1].id

        space.removeTab(id: tab1.id)
        #expect(space.tabs.count == 1)
        #expect(space.activeTabID == tab2ID)
    }

    @Test func removeLastTabFiresSectionOnEmpty() {
        // v4: Space no longer has `onEmpty`; the Terminal section's
        // `onEmpty` fires `SpaceModel.hideTerminal()` (auto-hide).
        let tab = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab)
        space.terminalVisible = true

        space.removeTab(id: tab.id)
        #expect(space.tabs.isEmpty)
        // hideTerminal ran via terminal section's onEmpty.
        #expect(space.terminalVisible == false)
    }

    @Test func nextTabWraps() {
        let tab1 = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab1)
        space.createTab()
        space.createTab()
        // active is tab 3 (last)
        space.nextTab()
        // should wrap to tab 1
        #expect(space.activeTabID == space.tabs[0].id)
    }

    @Test func previousTabWraps() {
        let tab1 = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab1)
        space.createTab()
        space.activateTab(id: tab1.id) // activate tab 1 (first)
        space.previousTab()
        // should wrap to last tab
        #expect(space.activeTabID == space.tabs[1].id)
    }

    @Test func goToTabByIndex() {
        let tab1 = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab1)
        space.createTab()
        space.createTab()
        space.activateTab(id: tab1.id)

        space.goToTab(index: 2)
        #expect(space.activeTabID == space.tabs[1].id)

        // Index 9 always goes to last
        space.goToTab(index: 9)
        #expect(space.activeTabID == space.tabs[2].id)
    }

    @Test func goToTabOutOfRangeDoesNothing() {
        let tab1 = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab1)
        let originalActive = space.activeTabID
        space.goToTab(index: 5)
        #expect(space.activeTabID == originalActive)
    }

    @Test func reorderTab() {
        let tab1 = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab1)
        space.createTab()
        space.createTab()
        let tab1ID = space.tabs[0].id
        let tab3ID = space.tabs[2].id

        space.reorderTab(from: 0, to: 2)
        #expect(space.tabs[2].id == tab1ID)
        #expect(space.tabs[0].id != tab1ID)
        // tab3 moved to index 1
        #expect(space.tabs[1].id == tab3ID)
    }

    @Test func closeOtherTabs() {
        let tab1 = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab1)
        space.createTab()
        space.createTab()

        space.closeOtherTabs(keepingID: tab1.id)
        #expect(space.tabs.count == 1)
        #expect(space.tabs[0].id == tab1.id)
        #expect(space.activeTabID == tab1.id)
    }

    @Test func closeTabsToRight() {
        let tab1 = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab1)
        space.createTab()
        space.createTab()
        space.createTab()

        space.closeTabsToRight(ofID: space.tabs[1].id)
        #expect(space.tabs.count == 2)
    }

    @Test func cascadingCloseFromPaneToTab() async {
        // v4: pane → tab → section cascade. Space no longer has `onEmpty`.
        let tab = TabModel()
        let space = SpaceModel(name: "default", initialTab: tab)
        space.terminalVisible = true

        let paneID = tab.paneViewModel.splitTree.focusedPaneID
        tab.paneViewModel.closePane(paneID: paneID)

        // Tab's onEmpty → SectionModel.removeTab → section empty → hideTerminal
        #expect(space.tabs.isEmpty)
        #expect(space.terminalVisible == false)
    }
}

@MainActor
struct SpaceCollectionTests {
    @Test func initWithDefaultSpace() {
        // v4: Default Space seeds one Claude tab; Terminal section is empty.
        let collection = SpaceCollection()
        #expect(collection.spaces.count == 1)
        #expect(collection.spaces[0].name == "default")
        #expect(collection.spaces[0].claudeSection.tabs.count == 1)
        #expect(collection.spaces[0].terminalSection.tabs.isEmpty)
        #expect(!collection.shouldQuit)
    }

    @Test func createSpaceAppendsAndActivates() {
        let collection = SpaceCollection()
        collection.createSpace()
        #expect(collection.spaces.count == 2)
        #expect(collection.activeSpaceID == collection.spaces[1].id)
        #expect(collection.spaces[1].name == "Space 2")
    }

    @Test func removeSpaceActivatesNearest() {
        let collection = SpaceCollection()
        collection.createSpace()
        collection.createSpace()
        // active = Space 3 (index 2)
        let space3ID = collection.activeSpaceID
        let space2ID = collection.spaces[1].id

        collection.removeSpace(id: space3ID)
        #expect(collection.spaces.count == 2)
        #expect(collection.activeSpaceID == space2ID)
    }

    @Test func removeLastSpaceSetsQuit() {
        let collection = SpaceCollection()
        let spaceID = collection.spaces[0].id
        collection.removeSpace(id: spaceID)
        #expect(collection.spaces.isEmpty)
        #expect(collection.shouldQuit)
    }

    @Test func nextSpaceWraps() {
        let collection = SpaceCollection()
        collection.createSpace()
        // active = space 2 (last)
        collection.nextSpace()
        #expect(collection.activeSpaceID == collection.spaces[0].id)
    }

    @Test func previousSpaceWraps() {
        let collection = SpaceCollection()
        collection.createSpace()
        collection.activateSpace(id: collection.spaces[0].id)
        collection.previousSpace()
        #expect(collection.activeSpaceID == collection.spaces[1].id)
    }

    @Test func reorderSpace() {
        let collection = SpaceCollection()
        collection.createSpace()
        let space1ID = collection.spaces[0].id
        let space2ID = collection.spaces[1].id

        collection.reorderSpace(from: 0, to: 1)
        #expect(collection.spaces[0].id == space2ID)
        #expect(collection.spaces[1].id == space1ID)
    }

    @Test func explicitSpaceCloseCascadesToQuit() async {
        // v4: cascading close from pane no longer auto-closes the Space;
        // the user must explicitly close via `requestSpaceClose`.
        let collection = SpaceCollection()
        let space = collection.spaces[0]
        await space.requestSpaceClose()

        #expect(collection.spaces.isEmpty)
        #expect(collection.shouldQuit)
    }

    @Test func terminalPaneCloseDoesNotCloseSpaceInV4() async {
        // v4: closing the last Terminal pane auto-hides the section but
        // leaves the Space alive. The Claude section remains populated.
        let collection = SpaceCollection()
        let space = collection.spaces[0]
        space.showTerminal() // ensure a terminal tab exists

        #expect(space.terminalSection.tabs.count == 1)
        let tab = space.terminalSection.tabs[0]
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        tab.paneViewModel.closePane(paneID: paneID)

        #expect(space.terminalSection.tabs.isEmpty)
        #expect(space.terminalVisible == false)
        #expect(collection.spaces.count == 1)
        #expect(!collection.shouldQuit)
    }
}

// MARK: - Stress Tests

@MainActor
struct StressTests {

    // MARK: - Many Tabs

    @Test func createAndSwitchManyTabs() {
        let collection = SpaceCollection()
        let space = collection.spaces[0]

        // Create 50 tabs
        for _ in 1..<50 {
            space.createTab()
        }
        #expect(space.tabs.count == 50)

        // Rapid switching: cycle through all tabs forward
        for i in 1...9 {
            space.goToTab(index: i)
            #expect(space.activeTab != nil)
        }

        // Rapid next/previous cycling
        for _ in 0..<100 {
            space.nextTab()
        }
        #expect(space.activeTab != nil)

        for _ in 0..<100 {
            space.previousTab()
        }
        #expect(space.activeTab != nil)
    }

    @Test func closeAllTabsFromMiddle() {
        // v4: removing tabs from the Terminal section no longer triggers
        // Space-level onEmpty; it auto-hides the section instead.
        let collection = SpaceCollection()
        let space = collection.spaces[0]
        space.showTerminal()

        for _ in 1..<20 {
            space.createTab()
        }
        #expect(space.tabs.count == 20)

        // Close tabs from the middle outward
        while space.tabs.count > 1 {
            let midIndex = space.tabs.count / 2
            let midID = space.tabs[midIndex].id
            space.removeTab(id: midID)
            #expect(space.activeTab != nil)
        }

        // Close the last tab — section auto-hides.
        let lastID = space.tabs[0].id
        space.removeTab(id: lastID)
        #expect(space.tabs.isEmpty)
        #expect(space.terminalVisible == false)
    }

    @Test func closeOtherTabsWithManyTabs() {
        let space = SpaceModel(name: "test", initialTab: TabModel())
        for _ in 1..<30 {
            space.createTab()
        }
        #expect(space.tabs.count == 30)

        let keepID = space.tabs[15].id
        space.closeOtherTabs(keepingID: keepID)
        #expect(space.tabs.count == 1)
        #expect(space.tabs[0].id == keepID)
        #expect(space.activeTabID == keepID)
    }

    // MARK: - Many Spaces

    @Test func createAndSwitchManySpaces() {
        let collection = SpaceCollection()

        // Create 20 spaces
        for _ in 1..<20 {
            collection.createSpace()
        }
        #expect(collection.spaces.count == 20)

        // Rapid switching
        for _ in 0..<50 {
            collection.nextSpace()
        }
        #expect(collection.activeSpace != nil)

        for _ in 0..<50 {
            collection.previousSpace()
        }
        #expect(collection.activeSpace != nil)
    }

    @Test func closeAllSpacesCascadesToQuit() {
        let collection = SpaceCollection()

        for _ in 1..<10 {
            collection.createSpace()
        }
        #expect(collection.spaces.count == 10)

        // Close spaces from the end via explicit removeSpace
        while !collection.spaces.isEmpty {
            let lastID = collection.spaces.last!.id
            collection.removeSpace(id: lastID)
        }
        #expect(collection.shouldQuit)
    }

    // MARK: - Many Spaces × Tabs

    @Test func manySpacesWithManyTabs() {
        let collection = SpaceCollection()

        // 5 spaces, each with 10 tabs
        for _ in 1..<5 {
            collection.createSpace()
        }
        for space in collection.spaces {
            for _ in 1..<10 {
                space.createTab()
            }
        }
        #expect(collection.spaces.count == 5)
        for space in collection.spaces {
            #expect(space.tabs.count == 10)
        }

        // Switch spaces and tabs rapidly
        for _ in 0..<20 {
            collection.nextSpace()
            collection.activeSpace?.nextTab()
            collection.activeSpace?.nextTab()
            collection.activeSpace?.nextTab()
        }

        #expect(collection.activeSpace != nil)
        #expect(collection.activeSpace?.activeTab != nil)
    }

    @Test func cascadingCloseAcrossMultipleSpacesAndTabs() async {
        // v4: pane-level cascades auto-hide the Terminal section but do
        // NOT close the Space. Space closes require explicit user gesture.
        let collection = SpaceCollection()

        // 3 spaces, each with terminal visible + 5 terminal tabs
        for _ in 1..<3 {
            collection.createSpace()
        }
        for space in collection.spaces {
            space.showTerminal()
            for _ in 1..<5 {
                space.createTab()
            }
        }
        #expect(collection.spaces.count == 3)

        // Close all panes in all tabs of space 0 — terminal auto-hides
        let space0 = collection.spaces[0]
        while !space0.tabs.isEmpty {
            let tab = space0.tabs[0]
            let paneID = tab.paneViewModel.splitTree.focusedPaneID
            tab.paneViewModel.closePane(paneID: paneID)
        }
        #expect(space0.terminalVisible == false)
        #expect(collection.spaces.count == 3)

        // User explicitly closes each space
        while !collection.spaces.isEmpty {
            let space = collection.spaces[0]
            await space.requestSpaceClose()
        }
        #expect(collection.shouldQuit)
    }

    // MARK: - Reorder Stress

    @Test func reorderTabsRepeatedly() {
        let space = SpaceModel(name: "test", initialTab: TabModel())
        for _ in 1..<20 {
            space.createTab()
        }

        let originalIDs = space.tabs.map(\.id)

        // Shuffle by moving first to last repeatedly
        for _ in 0..<50 {
            space.reorderTab(from: 0, to: space.tabs.count - 1)
        }

        // All original tabs should still exist
        let currentIDs = Set(space.tabs.map(\.id))
        #expect(currentIDs == Set(originalIDs))
        #expect(space.tabs.count == 20)
    }

    @Test func reorderSpacesRepeatedly() {
        let collection = SpaceCollection()
        for _ in 1..<10 {
            collection.createSpace()
        }

        let originalIDs = collection.spaces.map(\.id)

        for _ in 0..<30 {
            collection.reorderSpace(from: 0, to: collection.spaces.count - 1)
        }

        let currentIDs = Set(collection.spaces.map(\.id))
        #expect(currentIDs == Set(originalIDs))
        #expect(collection.spaces.count == 10)
    }

    // MARK: - Interleaved Operations

    @Test func interleavedCreateSwitchClose() {
        // v4: Each new Space gets a Claude section (one Claude tab) and an
        // empty Terminal section. We drive Terminal tabs here to exercise
        // the legacy compat API (`space.createTab` → terminalSection).
        let collection = SpaceCollection()

        for i in 0..<20 {
            collection.createSpace()
            collection.activeSpace?.showTerminal()
            collection.activeSpace?.createTab()
            collection.nextSpace()
            collection.activeSpace?.nextTab()

            if i % 3 == 0, collection.spaces.count > 1 {
                let id = collection.spaces[0].id
                collection.removeSpace(id: id)
            }
        }

        #expect(!collection.spaces.isEmpty)
        #expect(collection.activeSpace != nil)
        #expect(!collection.shouldQuit)

        // Invariant: activeSpaceID references an existing space
        #expect(collection.spaces.contains(where: { $0.id == collection.activeSpaceID }))

        // Invariant: each space's Claude section is non-empty
        for space in collection.spaces {
            #expect(space.claudeSection.tabs.isEmpty == false)
        }
    }
}
