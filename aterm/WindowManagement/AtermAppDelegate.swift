import AppKit

@MainActor
class AtermAppDelegate: NSObject, NSApplicationDelegate {
    let workspaceManager = WorkspaceManager()
    let windowCoordinator = WindowCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        windowCoordinator.workspaceManager = workspaceManager
        windowCoordinator.openWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for collection in windowCoordinator.allWorkspaceCollections {
            for workspace in collection.workspaces {
                workspace.cleanup()
            }
        }
        return .terminateNow
    }
}
