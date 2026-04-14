import Testing
import Foundation
@testable import tian

@MainActor
struct ProcessDetectorTests {

    // MARK: - Empty / No Surfaces

    @Test func emptyCollectionsReturnsNoProcesses() {
        let result = ProcessDetector.detectRunningProcesses(in: [])
        #expect(result.isEmpty)
    }

    @Test func emptyCollectionsNeedsNoConfirmation() {
        #expect(!ProcessDetector.needsConfirmation(in: []))
    }

    @Test func singleCollectionWithNilSurfacesReturnsEmpty() {
        // Surfaces created without ghostty_app have surface == nil,
        // so ghostty_surface_needs_confirm_quit is never called.
        let collection = WorkspaceCollection()
        let result = ProcessDetector.detectRunningProcesses(in: [collection])
        #expect(result.isEmpty)
    }

    @Test func needsConfirmationReturnsFalseForNilSurfaces() {
        let collection = WorkspaceCollection()
        #expect(!ProcessDetector.needsConfirmation(in: [collection]))
    }

    // MARK: - Hierarchy Traversal

    @Test func traversesMultipleWorkspaces() {
        let collection = WorkspaceCollection()
        collection.createWorkspace(name: "second")

        // With nil surfaces, all should be skipped
        let result = ProcessDetector.detectRunningProcesses(in: [collection])
        #expect(result.isEmpty)
    }

    @Test func traversesMultipleSpaces() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        ws.spaceCollection.createSpace()

        let result = ProcessDetector.detectRunningProcesses(in: [collection])
        #expect(result.isEmpty)
    }

    @Test func traversesMultipleTabs() {
        let collection = WorkspaceCollection()
        let space = collection.workspaces[0].spaceCollection.activeSpace!
        space.createTab()
        space.createTab()

        let result = ProcessDetector.detectRunningProcesses(in: [collection])
        #expect(result.isEmpty)
    }

    @Test func traversesMultipleCollections() {
        let c1 = WorkspaceCollection()
        let c2 = WorkspaceCollection()

        let result = ProcessDetector.detectRunningProcesses(in: [c1, c2])
        #expect(result.isEmpty)
    }

    // MARK: - RunningProcessInfo Structure

    @Test func runningProcessInfoCapturesNames() {
        let info = RunningProcessInfo(
            workspaceName: "project",
            spaceName: "dev",
            tabName: "Tab 1",
            paneID: UUID()
        )
        #expect(info.workspaceName == "project")
        #expect(info.spaceName == "dev")
        #expect(info.tabName == "Tab 1")
    }

    // MARK: - Scoped Checks (nil surfaces → no confirmation)

    @Test func needsConfirmationReturnsFalseForNilSurface() {
        let surface = GhosttyTerminalSurface()
        // surface.surface is nil without ghostty_app
        #expect(!ProcessDetector.needsConfirmation(surface: surface))
    }

    @Test func runningProcessCountInSingleTabReturnsZeroForNilSurfaces() {
        let tab = TabModel()
        #expect(ProcessDetector.runningProcessCount(in: tab) == 0)
    }

    @Test func runningProcessCountInMultipleTabsReturnsZero() {
        let tab1 = TabModel()
        let tab2 = TabModel()
        #expect(ProcessDetector.runningProcessCount(in: [tab1, tab2]) == 0)
    }

    @Test func runningProcessCountInEmptyTabArrayReturnsZero() {
        let tabs: [TabModel] = []
        #expect(ProcessDetector.runningProcessCount(in: tabs) == 0)
    }

    @Test func runningProcessCountInTabWithSplitsReturnsZero() {
        let tab = TabModel()
        tab.paneViewModel.splitPane(direction: .horizontal)
        // Two panes, both with nil surfaces
        #expect(tab.paneViewModel.surfaces.count == 2)
        #expect(ProcessDetector.runningProcessCount(in: tab) == 0)
    }
}

// MARK: - Snapshot Window Geometry Tests

@MainActor
struct SessionSnapshotWindowGeometryTests {
    @Test func snapshotCapturesWindowFrame() {
        let collection = WorkspaceCollection()
        let frame = WindowFrame(x: 100, y: 200, width: 800, height: 600)

        let snapshot = SessionSerializer.snapshot(
            from: collection,
            windowFrame: frame,
            isFullscreen: false
        )

        #expect(snapshot.workspaces[0].windowFrame == frame)
        #expect(snapshot.workspaces[0].isFullscreen == false)
    }

    @Test func snapshotCapturesFullscreen() {
        let collection = WorkspaceCollection()

        let snapshot = SessionSerializer.snapshot(
            from: collection,
            windowFrame: nil,
            isFullscreen: true
        )

        #expect(snapshot.workspaces[0].windowFrame == nil)
        #expect(snapshot.workspaces[0].isFullscreen == true)
    }

    @Test func snapshotDefaultsToNilGeometry() {
        let collection = WorkspaceCollection()

        let snapshot = SessionSerializer.snapshot(from: collection)

        #expect(snapshot.workspaces[0].windowFrame == nil)
        #expect(snapshot.workspaces[0].isFullscreen == nil)
    }
}
