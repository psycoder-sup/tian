import Sparkle
import SwiftUI

struct WorkspaceCommands: Commands {
    let windowCoordinator: WindowCoordinator
    let updater: SPUUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesView(updater: updater)
        }

        CommandGroup(after: .newItem) {
            Divider()

            Button("New Session…") {
                if let controller = windowCoordinator.controllerForKeyWindow() {
                    let collection = controller.workspaceCollection
                    var userInfo: [AnyHashable: Any] = [:]
                    if let id = collection.activeWorkspaceID {
                        userInfo[Notification.createSessionWorkspaceIDKey] = id
                    }
                    NotificationCenter.default.post(
                        name: .showCreateSessionInput,
                        object: collection,
                        userInfo: userInfo
                    )
                }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])

            Button("New Workspace") {
                if let controller = windowCoordinator.controllerForKeyWindow() {
                    WorkspaceCreationFlow.createWorkspace(in: controller.workspaceCollection)
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Close Workspace") {
                if let controller = windowCoordinator.controllerForKeyWindow(),
                   let id = controller.workspaceCollection.activeWorkspaceID {
                    controller.workspaceCollection.removeWorkspace(id: id)
                }
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])

            Divider()

            Button("Previous Session") {
                if let controller = windowCoordinator.controllerForKeyWindow() {
                    controller.workspaceCollection.previousSessionGlobal()
                }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .shift])

            Button("Next Session") {
                if let controller = windowCoordinator.controllerForKeyWindow() {
                    controller.workspaceCollection.nextSessionGlobal()
                }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .shift])

            Divider()

            Button("Toggle Debug Overlay") {
                if let controller = windowCoordinator.controllerForKeyWindow() {
                    NotificationCenter.default.post(
                        name: .toggleDebugOverlay,
                        object: controller.workspaceCollection
                    )
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}
