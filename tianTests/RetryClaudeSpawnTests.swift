import Testing
import Foundation
@testable import tian

@MainActor
struct RetryClaudeSpawnTests {

    // FR-08b — Retry on a spawn-failed Claude pane re-initialises the surface.
    // Drives state via the real `surfaceSpawnFailedNotification` code path
    // (PaneViewModel.installObservers) and invokes restartShell, which today
    // already handles `.spawnFailed` transitions.
    @Test func retryReInitiatesSpawnOnSpawnFailedPane() async throws {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.claudeSection.tabs[0]
        let paneID = try #require(tab.paneViewModel.splitTree.focusedPaneID)
        let surfaceID = try #require(tab.paneViewModel.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceSpawnFailedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID]
        )
        try await Task.sleep(for: .milliseconds(10))
        #expect(tab.paneViewModel.paneStates[paneID] == .spawnFailed)

        // Retry re-arms the surface. In the unit-test context the view has
        // no attached window, so `restartShell`'s `if surfaceView.window
        // != nil` branch does NOT invoke a real PTY spawn — this test
        // covers the state-machine transition only. The real spawn path
        // is exercised by `tianUITests/` end-to-end flows.
        tab.paneViewModel.restartShell(paneID: paneID)
        #expect(tab.paneViewModel.paneStates[paneID] != .spawnFailed)

        // Claude "command" is still set (assigned by SectionSpawner at
        // initial tab creation in Phase 1; also restamped during restart).
        let view = tab.paneViewModel.surfaceView(for: paneID)
        #expect(view?.initialInput == "claude\n")

        // A second spawn failure on the same pane returns it to
        // .spawnFailed. `restartShell` replaces the surface + view, so
        // the current surface id has changed — re-fetch it.
        let newSurfaceID = try #require(tab.paneViewModel.surface(for: paneID)?.id)
        NotificationCenter.default.post(
            name: GhosttyApp.surfaceSpawnFailedNotification,
            object: nil,
            userInfo: ["surfaceId": newSurfaceID]
        )
        try await Task.sleep(for: .milliseconds(10))
        #expect(tab.paneViewModel.paneStates[paneID] == .spawnFailed)
    }

    // FR-08 — spawn failure keeps the pane alive (not cascaded into close).
    @Test func spawnFailureDoesNotClosePane() async throws {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.claudeSection.tabs[0]
        let paneID = try #require(tab.paneViewModel.splitTree.focusedPaneID)
        let surfaceID = try #require(tab.paneViewModel.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceSpawnFailedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID]
        )
        try await Task.sleep(for: .milliseconds(10))

        // Pane remains in the tree — only state flipped to .spawnFailed.
        #expect(tab.paneViewModel.paneStates[paneID] == .spawnFailed)
        #expect(tab.paneViewModel.surface(for: paneID) != nil)
    }
}
