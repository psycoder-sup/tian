import AppKit

@MainActor
final class WindowCoordinator {
    private var controllers: [WorkspaceWindowController] = []
    weak var workspaceManager: WorkspaceManager?

    func openWindow() {
        guard let manager = workspaceManager else { return }

        let collection = WorkspaceCollection()
        let controller = WorkspaceWindowController(
            workspaceCollection: collection,
            workspaceManager: manager,
            windowCoordinator: self
        )
        controllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func removeController(_ controller: WorkspaceWindowController) {
        controllers.removeAll(where: { $0 === controller })
    }

    func controllerForKeyWindow() -> WorkspaceWindowController? {
        let keyWindow = NSApplication.shared.keyWindow
        return controllers.first(where: { $0.window === keyWindow })
    }

    var allWorkspaceCollections: [WorkspaceCollection] {
        controllers.map(\.workspaceCollection)
    }

    var windowCount: Int { controllers.count }
}
