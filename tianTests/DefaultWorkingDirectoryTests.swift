import Testing
import Foundation
@testable import tian

@MainActor
struct DefaultWorkingDirectoryTests {
    // MARK: - Workspace Default Propagation

    @Test func workspaceDefaultPropagatedToSpaceCollection() {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        #expect(ws.spaceCollection.workspaceDefaultDirectory == dir)
    }

    @Test func workspaceDefaultPropagatedToInitialSpace() {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        #expect(ws.spaces[0].workspaceDefaultDirectory == dir)
    }

    @Test func setDefaultWorkingDirectoryPropagatesToAllSpaces() {
        let ws = Workspace(name: "test")
        ws.spaceCollection.createSpace()
        ws.spaceCollection.createSpace()
        #expect(ws.spaces.count == 3)

        let dir = URL(filePath: "/tmp/new-project")
        ws.setDefaultWorkingDirectory(dir)

        #expect(ws.defaultWorkingDirectory == dir)
        #expect(ws.spaceCollection.workspaceDefaultDirectory == dir)
        for space in ws.spaces {
            #expect(space.workspaceDefaultDirectory == dir)
        }
    }

    @Test func clearDefaultWorkingDirectoryPropagatesToAllSpaces() {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        ws.spaceCollection.createSpace()

        ws.setDefaultWorkingDirectory(nil)

        #expect(ws.defaultWorkingDirectory == nil)
        #expect(ws.spaceCollection.workspaceDefaultDirectory == nil)
        for space in ws.spaces {
            #expect(space.workspaceDefaultDirectory == nil)
        }
    }

    @Test func newSpaceInheritsWorkspaceDefault() {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        ws.spaceCollection.createSpace()
        let newSpace = ws.spaces.last!
        #expect(newSpace.workspaceDefaultDirectory == dir)
    }

    // MARK: - SpaceCollection resolveWorkingDirectory

    @Test func resolveWorkingDirectoryUsesWorkspaceDefault() {
        let collection = SpaceCollection()
        collection.workspaceDefaultDirectory = URL(filePath: "/tmp/workspace")
        // No active surface, so sourcePaneDirectory will be nil
        // Should fall through to workspace default
        let wd = collection.resolveWorkingDirectory()
        #expect(wd == "/tmp/workspace")
    }

    @Test func resolveWorkingDirectoryUsesSpaceDefault() {
        let collection = SpaceCollection()
        collection.workspaceDefaultDirectory = URL(filePath: "/tmp/workspace")
        collection.activeSpace?.defaultWorkingDirectory = URL(filePath: "/tmp/space")
        let wd = collection.resolveWorkingDirectory()
        #expect(wd == "/tmp/space")
    }

    @Test func resolveWorkingDirectorySpaceOverridesWorkspace() {
        let collection = SpaceCollection()
        collection.workspaceDefaultDirectory = URL(filePath: "/tmp/workspace")
        collection.activeSpace?.defaultWorkingDirectory = URL(filePath: "/tmp/space")
        let wd = collection.resolveWorkingDirectory()
        #expect(wd == "/tmp/space")
    }

    // MARK: - PaneViewModel directoryFallback

    @Test func paneViewModelUsesDirectoryFallback() {
        let pvm = PaneViewModel()
        pvm.directoryFallback = { "/tmp/fallback" }
        // PaneViewModel doesn't expose resolveWorkingDirectory directly,
        // but we can verify the property is set
        #expect(pvm.directoryFallback != nil)
        #expect(pvm.directoryFallback?() == "/tmp/fallback")
    }

    // MARK: - SpaceModel Directory Fallback Wiring

    @Test func spaceModelWiresDirectoryFallbackToInitialTab() {
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        space.defaultWorkingDirectory = URL(filePath: "/tmp/space")
        space.workspaceDefaultDirectory = URL(filePath: "/tmp/workspace")
        // The fallback closure should resolve to space default
        let fallback = tab.paneViewModel.directoryFallback?()
        #expect(fallback == "/tmp/space")
    }

    @Test func spaceModelWiresDirectoryFallbackToNewTabs() {
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        space.defaultWorkingDirectory = URL(filePath: "/tmp/space")
        space.workspaceDefaultDirectory = URL(filePath: "/tmp/workspace")

        space.createTab()
        let newTab = space.tabs.last!
        let fallback = newTab.paneViewModel.directoryFallback?()
        #expect(fallback == "/tmp/space")
    }

    @Test func spaceModelFallbackReturnsNilWhenNoDefaultsSet() {
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        // No defaults set
        let fallback = tab.paneViewModel.directoryFallback?()
        #expect(fallback == nil)
    }

    @Test func spaceModelFallbackUsesWorkspaceDefaultWhenNoSpaceDefault() {
        let tab = TabModel()
        let space = SpaceModel(name: "test", initialTab: tab)
        space.workspaceDefaultDirectory = URL(filePath: "/tmp/workspace")
        let fallback = tab.paneViewModel.directoryFallback?()
        #expect(fallback == "/tmp/workspace")
    }

    // MARK: - End-to-End Hierarchy

    @Test func endToEndWorkspaceToSpaceToTab() {
        let dir = URL(filePath: "/tmp/project")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)

        // The initial tab should have a fallback that resolves to workspace default
        let space = ws.spaces[0]
        // v4: fresh Space has 0 Terminal tabs; the seeded Claude tab
        // carries the directory fallback.
        let tab = space.claudeSection.tabs[0]
        let fallback = tab.paneViewModel.directoryFallback?()
        #expect(fallback == "/tmp/project")
    }

    @Test func endToEndSpaceDefaultOverridesWorkspace() {
        let wsDir = URL(filePath: "/tmp/workspace")
        let ws = Workspace(name: "test", defaultWorkingDirectory: wsDir)
        let space = ws.spaces[0]
        space.defaultWorkingDirectory = URL(filePath: "/tmp/space-override")

        // v4: fresh Space has 0 Terminal tabs; use the seeded Claude tab.
        let tab = space.claudeSection.tabs[0]
        let fallback = tab.paneViewModel.directoryFallback?()
        #expect(fallback == "/tmp/space-override")
    }
}
