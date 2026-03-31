import Testing
import Foundation
@testable import aterm

// MARK: - Workspace Tests

@MainActor
struct WorkspaceTests {
    @Test func initCreatesOneSpaceWithOneTab() {
        let ws = Workspace(name: "project")
        #expect(ws.spaces.count == 1)
        #expect(ws.spaces[0].tabs.count == 1)
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

    @Test func onEmptyFiredWhenLastSpaceClosed() {
        let ws = Workspace(name: "project")
        var fired = false
        ws.onEmpty = { fired = true }

        let space = ws.spaceCollection.spaces[0]
        let tab = space.tabs[0]
        let paneID = tab.paneViewModel.splitTree.focusedPaneID
        tab.paneViewModel.closePane(paneID: paneID)

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

// MARK: - WorkspaceManager Tests

@MainActor
struct WorkspaceManagerTests {
    // MARK: - Creation

    @Test func createWorkspaceAppendsAndActivates() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "project")
        #expect(ws != nil)
        #expect(manager.workspaces.count == 1)
        #expect(manager.activeWorkspaceID == ws?.id)
    }

    @Test func createMultipleWorkspaces() {
        let manager = WorkspaceManager()
        let ws1 = manager.createWorkspace(name: "first")
        let ws2 = manager.createWorkspace(name: "second")
        #expect(manager.workspaces.count == 2)
        #expect(manager.activeWorkspaceID == ws2?.id)
        #expect(manager.workspaces[0].id == ws1?.id)
        #expect(manager.workspaces[1].id == ws2?.id)
    }

    @Test func createWorkspaceRejectsEmptyName() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "")
        #expect(ws == nil)
        #expect(manager.workspaces.isEmpty)
    }

    @Test func createWorkspaceRejectsWhitespaceOnlyName() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "   \t\n  ")
        #expect(ws == nil)
        #expect(manager.workspaces.isEmpty)
    }

    @Test func createWorkspaceTrimsWhitespace() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "  my project  ")
        #expect(ws?.name == "my project")
    }

    @Test func createWorkspaceWithWorkingDirectory() {
        let manager = WorkspaceManager()
        let dir = URL(filePath: "/tmp/project")
        let ws = manager.createWorkspace(name: "project", workingDirectory: dir)
        #expect(ws?.defaultWorkingDirectory == dir)
    }

    // MARK: - Rename

    @Test func renameWorkspaceUpdatesName() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "old")!
        let result = manager.renameWorkspace(id: ws.id, newName: "new")
        #expect(result)
        #expect(ws.name == "new")
    }

    @Test func renameWorkspaceRejectsEmptyName() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "project")!
        let result = manager.renameWorkspace(id: ws.id, newName: "")
        #expect(!result)
        #expect(ws.name == "project")
    }

    @Test func renameWorkspaceTrimsWhitespace() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "old")!
        manager.renameWorkspace(id: ws.id, newName: "  new name  ")
        #expect(ws.name == "new name")
    }

    @Test func renameNonexistentWorkspaceReturnsFalse() {
        let manager = WorkspaceManager()
        let result = manager.renameWorkspace(id: UUID(), newName: "name")
        #expect(!result)
    }

    // MARK: - Delete

    @Test func deleteWorkspaceRemovesFromList() {
        let manager = WorkspaceManager()
        manager.createWorkspace(name: "first")
        let ws2 = manager.createWorkspace(name: "second")!
        manager.deleteWorkspace(id: ws2.id)
        #expect(manager.workspaces.count == 1)
        #expect(manager.workspaces[0].name == "first")
    }

    @Test func deleteWorkspaceActivatesNearest() {
        let manager = WorkspaceManager()
        manager.createWorkspace(name: "first")
        manager.createWorkspace(name: "second")
        let ws3 = manager.createWorkspace(name: "third")!
        let ws2ID = manager.workspaces[1].id

        manager.deleteWorkspace(id: ws3.id)
        #expect(manager.activeWorkspaceID == ws2ID)
    }

    @Test func deleteFirstWorkspaceActivatesRight() {
        let manager = WorkspaceManager()
        let ws1 = manager.createWorkspace(name: "first")!
        let ws2 = manager.createWorkspace(name: "second")!
        manager.switchToWorkspace(id: ws1.id)

        manager.deleteWorkspace(id: ws1.id)
        #expect(manager.activeWorkspaceID == ws2.id)
    }

    @Test func deleteLastWorkspaceSetsQuit() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "only")!
        manager.deleteWorkspace(id: ws.id)
        #expect(manager.workspaces.isEmpty)
        #expect(manager.shouldQuit)
    }

    @Test func deleteNonexistentWorkspaceIsNoOp() {
        let manager = WorkspaceManager()
        manager.createWorkspace(name: "test")
        manager.deleteWorkspace(id: UUID())
        #expect(manager.workspaces.count == 1)
    }

    // MARK: - Switch

    @Test func switchToWorkspaceChangesActiveID() {
        let manager = WorkspaceManager()
        let ws1 = manager.createWorkspace(name: "first")!
        manager.createWorkspace(name: "second")

        manager.switchToWorkspace(id: ws1.id)
        #expect(manager.activeWorkspaceID == ws1.id)
    }

    @Test func switchToNonexistentWorkspaceIsNoOp() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "test")!
        manager.switchToWorkspace(id: UUID())
        #expect(manager.activeWorkspaceID == ws.id)
    }

    // MARK: - Reorder

    @Test func reorderWorkspace() {
        let manager = WorkspaceManager()
        let ws1 = manager.createWorkspace(name: "first")!
        let ws2 = manager.createWorkspace(name: "second")!

        manager.reorderWorkspace(from: 0, to: 1)
        #expect(manager.workspaces[0].id == ws2.id)
        #expect(manager.workspaces[1].id == ws1.id)
    }

    @Test func reorderOutOfBoundsIsNoOp() {
        let manager = WorkspaceManager()
        manager.createWorkspace(name: "only")
        manager.reorderWorkspace(from: 0, to: 5)
        #expect(manager.workspaces.count == 1)
    }

    @Test func reorderSameIndexIsNoOp() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "only")!
        manager.reorderWorkspace(from: 0, to: 0)
        #expect(manager.workspaces[0].id == ws.id)
    }

    // MARK: - Default Working Directory

    @Test func setWorkspaceDefaultWorkingDirectory() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "test")!
        let dir = URL(filePath: "/tmp/project")
        manager.setDefaultWorkingDirectory(workspaceID: ws.id, directory: dir)
        #expect(ws.defaultWorkingDirectory == dir)
    }

    @Test func clearWorkspaceDefaultWorkingDirectory() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(
            name: "test",
            workingDirectory: URL(filePath: "/tmp")
        )!
        manager.setDefaultWorkingDirectory(workspaceID: ws.id, directory: nil)
        #expect(ws.defaultWorkingDirectory == nil)
    }

    @Test func setSpaceDefaultWorkingDirectory() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "test")!
        let space = ws.spaces[0]
        let dir = URL(filePath: "/tmp/space-dir")
        manager.setDefaultWorkingDirectory(spaceID: space.id, directory: dir)
        #expect(space.defaultWorkingDirectory == dir)
    }

    // MARK: - Cascading Close

    @Test func fullCascadeFromPaneToQuit() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "only")!
        let space = ws.spaceCollection.spaces[0]
        let tab = space.tabs[0]
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        tab.paneViewModel.closePane(paneID: paneID)

        #expect(space.tabs.isEmpty)
        #expect(ws.spaceCollection.spaces.isEmpty)
        #expect(manager.workspaces.isEmpty)
        #expect(manager.shouldQuit)
    }

    @Test func cascadeStopsWhenTabsRemain() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "test")!
        let space = ws.spaceCollection.spaces[0]
        space.createTab()
        let tab1 = space.tabs[0]
        let paneID = tab1.paneViewModel.splitTree.focusedPaneID

        tab1.paneViewModel.closePane(paneID: paneID)

        #expect(space.tabs.count == 1)
        #expect(manager.workspaces.count == 1)
        #expect(!manager.shouldQuit)
    }

    @Test func cascadeStopsWhenSpacesRemain() {
        let manager = WorkspaceManager()
        let ws = manager.createWorkspace(name: "test")!
        ws.spaceCollection.createSpace()
        let space1 = ws.spaceCollection.spaces[0]
        let tab = space1.tabs[0]
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        tab.paneViewModel.closePane(paneID: paneID)

        #expect(ws.spaceCollection.spaces.count == 1)
        #expect(manager.workspaces.count == 1)
        #expect(!manager.shouldQuit)
    }

    @Test func cascadeStopsWhenWorkspacesRemain() {
        let manager = WorkspaceManager()
        let ws1 = manager.createWorkspace(name: "first")!
        manager.createWorkspace(name: "second")
        let space = ws1.spaceCollection.spaces[0]
        let tab = space.tabs[0]
        let paneID = tab.paneViewModel.splitTree.focusedPaneID

        tab.paneViewModel.closePane(paneID: paneID)

        #expect(manager.workspaces.count == 1)
        #expect(!manager.shouldQuit)
    }
}
