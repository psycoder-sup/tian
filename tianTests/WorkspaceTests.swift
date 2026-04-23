import Testing
import Foundation
@testable import tian

// MARK: - Workspace Tests

@MainActor
struct WorkspaceTests {
    @Test func initCreatesOneSpaceWithOneTab() {
        // v4: new Spaces seed the Claude section with one Claude tab and
        // leave the Terminal section empty + hidden. Legacy `space.tabs`
        // aliases Terminal — so the assertion migrates to the v4 shape.
        let ws = Workspace(name: "project")
        #expect(ws.spaces.count == 1)
        #expect(ws.spaces[0].claudeSection.tabs.count == 1)
        #expect(ws.spaces[0].terminalSection.tabs.isEmpty)
        #expect(ws.name == "project")
    }

    @Test func initDefaultWorkingDirectoryIsNil() {
        let ws = Workspace(name: "project")
        #expect(ws.defaultWorkingDirectory == nil)
    }

    @Test func initWithWorkingDirectory() {
        let dir = URL(filePath: "/tmp/test-project")
        let ws = Workspace(name: "project", defaultWorkingDirectory: dir)
        #expect(ws.defaultWorkingDirectory == dir)
    }

    @Test func convenienceAccessorsDelegateToSpaceCollection() {
        let ws = Workspace(name: "project")
        #expect(ws.spaces.map(\.id) == ws.spaceCollection.spaces.map(\.id))
        #expect(ws.activeSpaceID == ws.spaceCollection.activeSpaceID)
        #expect(ws.activeSpace?.id == ws.spaceCollection.activeSpace?.id)
    }

    @Test func onEmptyFiredWhenLastSpaceExplicitlyClosed() async {
        // v4: ws.onEmpty fires when the last Space is removed. Space
        // removal now requires an explicit user close (requestSpaceClose),
        // not a pane-exit cascade.
        let ws = Workspace(name: "project")
        var fired = false
        ws.onEmpty = { fired = true }

        let space = ws.spaceCollection.spaces[0]
        await space.requestSpaceClose()

        #expect(fired)
    }

    @Test func snapshotProducesValidJSON() throws {
        let ws = Workspace(name: "my project")
        let data = try JSONEncoder().encode(ws.snapshot)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["name"] as? String == "my project")
        #expect(dict["id"] != nil)
        #expect(dict["createdAt"] != nil)
    }

    @Test func snapshotExcludesRuntimeState() throws {
        let ws = Workspace(name: "test")
        let data = try JSONEncoder().encode(ws.snapshot)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["spaceCollection"] == nil)
        #expect(dict["onEmpty"] == nil)
    }

    @Test func snapshotIncludesWorkingDirectory() throws {
        let dir = URL(filePath: "/Users/me/projects")
        let ws = Workspace(name: "test", defaultWorkingDirectory: dir)
        let data = try JSONEncoder().encode(ws.snapshot)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["defaultWorkingDirectory"] != nil)
    }

    @Test func snapshotOmitsNilWorkingDirectory() throws {
        let ws = Workspace(name: "test")
        let data = try JSONEncoder().encode(ws.snapshot)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(dict["defaultWorkingDirectory"] == nil)
    }

    @Test func snapshotRoundTrips() throws {
        let dir = URL(filePath: "/Users/me/projects")
        let ws = Workspace(name: "my project", defaultWorkingDirectory: dir)
        let data = try JSONEncoder().encode(ws.snapshot)
        let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: data)
        #expect(decoded.id == ws.id)
        #expect(decoded.name == "my project")
        #expect(decoded.defaultWorkingDirectory == dir)
    }

    @Test func restoreFromSnapshot() throws {
        let dir = URL(filePath: "/Users/me/projects")
        let ws = Workspace(name: "original", defaultWorkingDirectory: dir)
        let snap = ws.snapshot
        let restored = Workspace.from(snapshot: snap)
        #expect(restored.id == ws.id)
        #expect(restored.name == "original")
        #expect(restored.defaultWorkingDirectory == dir)
        #expect(restored.spaces.count == 1)
    }
}

// MARK: - WorkspaceCollection Tests

@MainActor
struct WorkspaceCollectionTests {
    // MARK: - Init

    @Test func initCreatesOneDefaultWorkspace() {
        let collection = WorkspaceCollection()
        #expect(collection.workspaces.count == 1)
        #expect(collection.workspaces[0].name == "default")
        #expect(collection.activeWorkspaceID == collection.workspaces[0].id)
    }

    // MARK: - Empty Collection

    @Test func emptyCollectionHasNoWorkspaces() {
        let collection = WorkspaceCollection.empty()
        #expect(collection.workspaces.isEmpty)
        #expect(collection.activeWorkspaceID == nil)
        #expect(collection.activeWorkspace == nil)
        #expect(collection.activeSpaceCollection == nil)
    }

    @Test func emptyCollectionCreateWorkspaceActivates() {
        let collection = WorkspaceCollection.empty()
        let ws = collection.createWorkspace(name: "first", workingDirectory: "/tmp/proj")
        #expect(ws != nil)
        #expect(collection.workspaces.count == 1)
        #expect(collection.activeWorkspaceID == ws?.id)
        #expect(collection.activeWorkspace?.id == ws?.id)
    }

    // MARK: - Creation

    @Test func createWorkspaceStoresWorkingDirectory() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "first", workingDirectory: "/tmp/proj")
        #expect(ws?.defaultWorkingDirectory?.path == "/tmp/proj")
    }

    @Test func createWorkspaceAppendsAndActivates() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "project")
        #expect(ws != nil)
        #expect(collection.workspaces.count == 2)
        #expect(collection.activeWorkspaceID == ws?.id)
    }

    @Test func createMultipleWorkspaces() {
        let collection = WorkspaceCollection()
        let ws2 = collection.createWorkspace(name: "second")
        let ws3 = collection.createWorkspace(name: "third")
        #expect(collection.workspaces.count == 3)
        #expect(collection.activeWorkspaceID == ws3?.id)
        #expect(collection.workspaces[1].id == ws2?.id)
        #expect(collection.workspaces[2].id == ws3?.id)
    }

    @Test func createWorkspaceRejectsEmptyName() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "")
        #expect(ws == nil)
        #expect(collection.workspaces.count == 1)
    }

    @Test func createWorkspaceRejectsWhitespaceOnlyName() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "   \t\n  ")
        #expect(ws == nil)
        #expect(collection.workspaces.count == 1)
    }

    @Test func createWorkspaceTrimsWhitespace() {
        let collection = WorkspaceCollection()
        let ws = collection.createWorkspace(name: "  my project  ")
        #expect(ws?.name == "my project")
    }

    // MARK: - Rename

    @Test func renameWorkspaceUpdatesName() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        let result = collection.renameWorkspace(id: ws.id, newName: "new")
        #expect(result)
        #expect(ws.name == "new")
    }

    @Test func renameWorkspaceRejectsEmptyName() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        let result = collection.renameWorkspace(id: ws.id, newName: "")
        #expect(!result)
        #expect(ws.name == "default")
    }

    @Test func renameWorkspaceTrimsWhitespace() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        collection.renameWorkspace(id: ws.id, newName: "  new name  ")
        #expect(ws.name == "new name")
    }

    @Test func renameNonexistentWorkspaceReturnsFalse() {
        let collection = WorkspaceCollection()
        let result = collection.renameWorkspace(id: UUID(), newName: "name")
        #expect(!result)
    }

    // MARK: - Remove

    @Test func removeWorkspaceRemovesFromList() {
        let collection = WorkspaceCollection()
        let ws2 = collection.createWorkspace(name: "second")!
        collection.removeWorkspace(id: ws2.id)
        #expect(collection.workspaces.count == 1)
        #expect(collection.workspaces[0].name == "default")
    }

    @Test func removeWorkspaceActivatesNearest() {
        let collection = WorkspaceCollection()
        collection.createWorkspace(name: "second")
        let ws3 = collection.createWorkspace(name: "third")!
        let ws2ID = collection.workspaces[1].id

        collection.removeWorkspace(id: ws3.id)
        #expect(collection.activeWorkspaceID == ws2ID)
    }

    @Test func removeFirstWorkspaceActivatesRight() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        let ws2 = collection.createWorkspace(name: "second")!
        collection.activateWorkspace(id: ws1.id)

        collection.removeWorkspace(id: ws1.id)
        #expect(collection.activeWorkspaceID == ws2.id)
    }

    @Test func removeLastWorkspaceCallsOnEmpty() {
        let collection = WorkspaceCollection()
        var emptyCalled = false
        collection.onEmpty = { emptyCalled = true }
        let ws = collection.workspaces[0]

        collection.removeWorkspace(id: ws.id)
        #expect(collection.workspaces.isEmpty)
        #expect(emptyCalled)
    }

    @Test func removeLastWorkspaceEmptiesCollectionWhenNoCallback() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]

        collection.removeWorkspace(id: ws.id)
        #expect(collection.workspaces.isEmpty)
        #expect(collection.activeWorkspaceID == nil)
        #expect(collection.activeWorkspace == nil)
    }

    @Test func removeNonexistentWorkspaceIsNoOp() {
        let collection = WorkspaceCollection()
        collection.removeWorkspace(id: UUID())
        #expect(collection.workspaces.count == 1)
    }

    // MARK: - Activate

    @Test func activateWorkspaceChangesActiveID() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        collection.createWorkspace(name: "second")

        collection.activateWorkspace(id: ws1.id)
        #expect(collection.activeWorkspaceID == ws1.id)
    }

    @Test func activateNonexistentWorkspaceIsNoOp() {
        let collection = WorkspaceCollection()
        let originalID = collection.activeWorkspaceID
        collection.activateWorkspace(id: UUID())
        #expect(collection.activeWorkspaceID == originalID)
    }

    // MARK: - Navigation

    @Test func nextWorkspaceWraps() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        collection.createWorkspace(name: "second")

        collection.activateWorkspace(id: ws1.id)
        collection.nextWorkspace()
        #expect(collection.activeWorkspaceID == collection.workspaces[1].id)

        collection.nextWorkspace()
        #expect(collection.activeWorkspaceID == ws1.id)
    }

    @Test func previousWorkspaceWraps() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        collection.createWorkspace(name: "second")

        collection.activateWorkspace(id: ws1.id)
        collection.previousWorkspace()
        #expect(collection.activeWorkspaceID == collection.workspaces[1].id)
    }

    // MARK: - Reorder

    @Test func reorderWorkspace() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        let ws2 = collection.createWorkspace(name: "second")!

        collection.reorderWorkspace(from: 0, to: 1)
        #expect(collection.workspaces[0].id == ws2.id)
        #expect(collection.workspaces[1].id == ws1.id)
    }

    @Test func reorderOutOfBoundsIsNoOp() {
        let collection = WorkspaceCollection()
        collection.reorderWorkspace(from: 0, to: 5)
        #expect(collection.workspaces.count == 1)
    }

    @Test func reorderSameIndexIsNoOp() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        collection.reorderWorkspace(from: 0, to: 0)
        #expect(collection.workspaces[0].id == ws.id)
    }

    // MARK: - Computed Properties

    @Test func activeWorkspaceReturnsCorrectWorkspace() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        #expect(collection.activeWorkspace?.id == ws.id)
    }

    @Test func activeSpaceCollectionReturnsCorrectCollection() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        #expect(collection.activeSpaceCollection === ws.spaceCollection)
    }

    // MARK: - Cascading Close

    @Test func explicitCloseCascadesFromSpaceToOnEmpty() async {
        // v4: closing the last pane no longer cascades to Space close.
        // Explicit `requestSpaceClose` fires onSpaceClose → removeSpace,
        // which in turn cascades upward to the workspace collection
        // when the last workspace's last space goes away.
        let collection = WorkspaceCollection()
        var emptyCalled = false
        collection.onEmpty = { emptyCalled = true }
        let ws = collection.workspaces[0]
        let space = ws.spaceCollection.spaces[0]

        await space.requestSpaceClose()

        #expect(ws.spaceCollection.spaces.isEmpty)
        #expect(collection.workspaces.isEmpty)
        #expect(emptyCalled)
    }

    @Test func cascadeStopsWhenTabsRemain() {
        // v4: fresh Space has 0 Terminal tabs; seed 2 Terminal tabs so
        // closing one leaves a Terminal tab behind.
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        let space = ws.spaceCollection.spaces[0]
        space.createTab()  // 1 Terminal tab
        space.createTab()  // 2 Terminal tabs
        let tab1 = space.tabs[0]
        let paneID = tab1.paneViewModel.splitTree.focusedPaneID

        tab1.paneViewModel.closePane(paneID: paneID)

        // Closing tab1's only pane removes that tab; 1 Terminal tab remains
        // and the Space stays alive regardless of Claude section content.
        #expect(space.tabs.count == 1)
        #expect(collection.workspaces.count == 1)
    }

    @Test func cascadeStopsWhenSpacesRemain() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        ws.spaceCollection.createSpace()
        let space1 = ws.spaceCollection.spaces[0]
        space1.createTab()  // v4: seed a Terminal tab so the test has one to close
        let tab = space1.tabs[0]
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        tab.paneViewModel.closePane(paneID: paneID)

        // v4: Space stays alive when Terminal auto-hides.
        #expect(ws.spaceCollection.spaces.count == 2)
        #expect(collection.workspaces.count == 1)
    }

    @Test func cascadeStopsWhenWorkspacesRemain() {
        let collection = WorkspaceCollection()
        let ws1 = collection.workspaces[0]
        collection.createWorkspace(name: "second")
        let space = ws1.spaceCollection.spaces[0]
        space.createTab()  // v4: seed a Terminal tab so the test has one to close
        let tab = space.tabs[0]
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        tab.paneViewModel.closePane(paneID: paneID)

        // v4: closing the pane auto-hides Terminal; neither the Space nor
        // the owning Workspace are removed.
        #expect(collection.workspaces.count == 2)
    }
}
