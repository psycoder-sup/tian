import SwiftUI

struct WorkspaceCommands: Commands {
    let windowCoordinator: WindowCoordinator

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()

            Button("New Workspace") {
                if let controller = windowCoordinator.controllerForKeyWindow() {
                    controller.workspaceCollection.createWorkspace()
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Close Workspace") {
                if let controller = windowCoordinator.controllerForKeyWindow() {
                    controller.workspaceCollection.removeWorkspace(
                        id: controller.workspaceCollection.activeWorkspaceID
                    )
                }
            }
            .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }
}
