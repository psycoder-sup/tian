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

    @Test func traversesMultipleSessions() {
        let collection = WorkspaceCollection()
        let ws = collection.workspaces[0]
        ws.sessionCollection.createSession()
        ws.sessionCollection.createSession()

        let result = ProcessDetector.detectRunningProcesses(in: [collection])
        #expect(result.isEmpty)
    }

    @Test func traversesSessionTerminalPanels() {
        // A session's terminal panel adds panes the detector must walk.
        let collection = WorkspaceCollection()
        let session = collection.workspaces[0].sessionCollection.activeSession!
        session.showTerminal()

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
        let paneID = UUID()
        let info = RunningProcessInfo(
            workspaceName: "project",
            sessionName: "dev",
            paneID: paneID
        )
        #expect(info.workspaceName == "project")
        #expect(info.sessionName == "dev")
        #expect(info.paneID == paneID)
    }

    // MARK: - Scoped Checks (nil surfaces → no confirmation)

    @Test func needsConfirmationReturnsFalseForNilSurface() {
        let surface = GhosttyTerminalSurface()
        // surface.surface is nil without ghostty_app
        #expect(!ProcessDetector.needsConfirmation(surface: surface))
    }

    @Test func runningProcessCountInSinglePaneReturnsZeroForNilSurfaces() {
        let pane = PaneViewModel(workingDirectory: "/tmp", kind: .terminal)
        #expect(ProcessDetector.runningProcessCount(in: pane) == 0)
    }

    @Test func runningProcessCountInMultiplePanesReturnsZero() {
        let pane1 = PaneViewModel(workingDirectory: "/tmp", kind: .terminal)
        let pane2 = PaneViewModel(workingDirectory: "/tmp", kind: .claude)
        #expect(ProcessDetector.runningProcessCount(in: [pane1, pane2]) == 0)
    }

    @Test func runningProcessCountInEmptyPaneArrayReturnsZero() {
        let panes: [PaneViewModel] = []
        #expect(ProcessDetector.runningProcessCount(in: panes) == 0)
    }

    @Test func runningProcessCountInPaneWithSplitsReturnsZero() {
        let pane = PaneViewModel(workingDirectory: "/tmp", kind: .terminal)
        pane.splitPane(direction: .horizontal)
        // Two panes, both with nil surfaces
        #expect(pane.surfaces.count == 2)
        #expect(ProcessDetector.runningProcessCount(in: pane) == 0)
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
