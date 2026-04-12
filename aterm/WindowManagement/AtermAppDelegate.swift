import AppKit
import UserNotifications

@MainActor
class AtermAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let workspaceManager = WorkspaceManager()
    let windowCoordinator = WindowCoordinator()
    private lazy var quitFlowCoordinator = QuitFlowCoordinator(windowCoordinator: windowCoordinator)
    private var ipcServer: IPCServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowCoordinator.workspaceManager = workspaceManager
        UNUserNotificationCenter.current().delegate = self

        let isUITesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")

        if !isUITesting, let result = SessionRestorer.loadState() {
            let state = result.state
            AppMetrics.shared.recordRestore(metrics: result.metrics)
            Log.persistence.info("Restoring session with \(state.workspaces.count) workspace(s)")
            // Currently single-window: all workspaces go into one WorkspaceCollection.
            // Multi-window support (one collection per window) is a future enhancement.
            let collection = SessionRestorer.buildWorkspaceCollection(from: state)
            let frame = state.workspaces.first?.windowFrame
            let isFullscreen = state.workspaces.first?.isFullscreen
            windowCoordinator.openRestoredWindow(
                collection: collection,
                frame: frame,
                isFullscreen: isFullscreen
            )
        } else if isUITesting {
            windowCoordinator.openWindow()
        } else {
            windowCoordinator.openEmptyWindow()
        }

        // Start IPC server
        let commandHandler = IPCCommandHandler(windowCoordinator: windowCoordinator)
        let server = IPCServer { request in
            await commandHandler.handle(request)
        }
        self.ipcServer = server
        server.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitFlowCoordinator.initiateQuit()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcServer?.stop()
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let paneIdStr = userInfo["paneId"] as? String,
              let paneId = UUID(uuidString: paneIdStr) else { return }
        await MainActor.run {
            windowCoordinator.focusPane(id: paneId)
        }
    }
}
