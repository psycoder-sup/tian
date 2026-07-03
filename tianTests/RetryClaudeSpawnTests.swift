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
        let session = Session(customName: "s", workingDirectory: "/tmp")
        let pvm = try #require(session.claudePane)
        let paneID = pvm.splitTree.focusedPaneID
        let surfaceID = try #require(pvm.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceSpawnFailedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID]
        )
        try await Task.sleep(for: .milliseconds(10))
        #expect(pvm.paneState(for: paneID) == .spawnFailed)

        // Retry re-arms the surface. In the unit-test context the view has
        // no attached window, so `restartShell`'s `if surfaceView.window
        // != nil` branch does NOT invoke a real PTY spawn — this test
        // covers the state-machine transition only. The real spawn path
        // is exercised by `tianUITests/` end-to-end flows.
        pvm.restartShell(paneID: paneID)
        #expect(pvm.paneState(for: paneID) != .spawnFailed)

        // Claude "command" is still set (assigned by PaneSpawner at initial
        // pane creation; also restamped during restart) — carried via
        // TIAN_AUTOSTART_CMD, not as injected "claude\n" keystrokes.
        let view = pvm.surfaceView(for: paneID)
        #expect(view?.environmentVariables["TIAN_AUTOSTART_CMD"] == "claude")

        // A second spawn failure on the same pane returns it to
        // .spawnFailed. `restartShell` replaces the surface + view, so
        // the current surface id has changed — re-fetch it.
        let newSurfaceID = try #require(pvm.surface(for: paneID)?.id)
        NotificationCenter.default.post(
            name: GhosttyApp.surfaceSpawnFailedNotification,
            object: nil,
            userInfo: ["surfaceId": newSurfaceID]
        )
        try await Task.sleep(for: .milliseconds(10))
        #expect(pvm.paneState(for: paneID) == .spawnFailed)
    }

    // FR-08 — spawn failure keeps the pane alive (not cascaded into close).
    @Test func spawnFailureDoesNotClosePane() async throws {
        let session = Session(customName: "s", workingDirectory: "/tmp")
        let pvm = try #require(session.claudePane)
        let paneID = pvm.splitTree.focusedPaneID
        let surfaceID = try #require(pvm.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceSpawnFailedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID]
        )
        try await Task.sleep(for: .milliseconds(10))

        // Pane remains in the tree — only state flipped to .spawnFailed. The
        // Claude pane stays live (spawn failure never enters the empty state).
        #expect(pvm.paneState(for: paneID) == .spawnFailed)
        #expect(pvm.surface(for: paneID) != nil)
        #expect(session.hasLiveClaudePane)
    }
}
