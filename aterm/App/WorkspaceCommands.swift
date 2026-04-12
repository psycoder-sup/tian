import SwiftUI

struct WorkspaceCommands: Commands {
    let windowCoordinator: WindowCoordinator

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()

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

            Button("Previous Space") {
                if let controller = windowCoordinator.controllerForKeyWindow() {
                    controller.workspaceCollection.previousSpaceGlobal()
                }
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

            Button("Next Space") {
                if let controller = windowCoordinator.controllerForKeyWindow() {
                    controller.workspaceCollection.nextSpaceGlobal()
                }
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])

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
