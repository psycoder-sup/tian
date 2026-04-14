import AppKit

@MainActor
final class WindowCoordinator {
    private var controllers: [WorkspaceWindowController] = []
    weak var workspaceManager: WorkspaceManager?

    func openWindow(initialWorkingDirectory: String? = nil) {
        openController(with: WorkspaceCollection(workingDirectory: initialWorkingDirectory))
    }

    func openEmptyWindow() {
        openController(with: WorkspaceCollection.empty())
    }

    private func openController(with collection: WorkspaceCollection) {
        guard let manager = workspaceManager else { return }
        let controller = WorkspaceWindowController(
            workspaceCollection: collection,
            workspaceManager: manager,
            windowCoordinator: self
        )
        controllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// Opens a window with a restored WorkspaceCollection, applying saved window geometry.
    func openRestoredWindow(
        collection: WorkspaceCollection,
        frame: WindowFrame?,
        isFullscreen: Bool?
    ) {
        guard let manager = workspaceManager else { return }

        let controller = WorkspaceWindowController(
            workspaceCollection: collection,
            workspaceManager: manager,
            windowCoordinator: self
        )
        controllers.append(controller)

        if let frame, frame.isOnScreen(screenFrames: NSScreen.screens.map(\.frame)) {
            controller.window?.setFrame(frame.cgRect, display: false)
        } else {
            controller.window?.center()
        }

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        if isFullscreen == true {
            controller.window?.toggleFullScreen(nil)
        }
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

    var allControllers: [WorkspaceWindowController] {
        controllers
    }

    var windowCount: Int { controllers.count }

    /// Finds a pane by UUID across all windows, activates its workspace/space/tab,
    /// focuses the pane, and brings the window to front.
    /// The `id` may be a pane UUID or a Ghostty surface UUID; both are tried.
    func focusPane(id paneID: UUID) {
        for controller in controllers {
            let collection = controller.workspaceCollection
            for workspace in collection.workspaces {
                for space in workspace.spaceCollection.spaces {
                    for tab in space.tabs {
                        guard tab.paneViewModel.splitTree.root.containsLeaf(paneID: paneID) else {
                            continue
                        }
                        activatePane(paneID, controller: controller, workspace: workspace, space: space, tab: tab)
                        return
                    }
                }
            }
        }
        for controller in controllers {
            let collection = controller.workspaceCollection
            for workspace in collection.workspaces {
                for space in workspace.spaceCollection.spaces {
                    for tab in space.tabs {
                        guard let resolved = tab.paneViewModel.paneID(forSurfaceID: paneID) else {
                            continue
                        }
                        activatePane(resolved, controller: controller, workspace: workspace, space: space, tab: tab)
                        return
                    }
                }
            }
        }
    }

    private func activatePane(
        _ paneID: UUID,
        controller: WorkspaceWindowController,
        workspace: Workspace,
        space: SpaceModel,
        tab: TabModel
    ) {
        controller.workspaceCollection.activateWorkspace(id: workspace.id)
        workspace.spaceCollection.activateSpace(id: space.id)
        space.activateTab(id: tab.id)
        tab.paneViewModel.focusPane(paneID: paneID)
        NSApp.activate()
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - WorkspaceProviding

extension WindowCoordinator: WorkspaceProviding {
    func activeWorkspaceForKeyWindow() -> Workspace? {
        controllerForKeyWindow()?.workspaceCollection.activeWorkspace
    }
}
