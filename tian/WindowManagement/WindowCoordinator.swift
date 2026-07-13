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
        refreshSystemMonitorActivity()
    }

    /// Keeps the shared SystemMonitor running only while at least one
    /// workspace window is visible on screen. Called on every occlusion
    /// change and on window close.
    func refreshSystemMonitorActivity() {
        let anyVisible = controllers.contains {
            $0.window?.occlusionState.contains(.visible) ?? false
        }
        if anyVisible {
            SystemMonitor.shared.start()
        } else {
            SystemMonitor.shared.stop()
        }
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

    /// Finds a pane by UUID across all windows, activates its workspace/session,
    /// focuses the pane, and brings the window to front.
    /// The `id` may be a pane UUID or a Ghostty surface UUID; both are tried.
    func focusPane(id paneID: UUID) {
        for controller in controllers {
            let collection = controller.workspaceCollection
            for workspace in collection.workspaces {
                for session in workspace.sessionCollection.sessions {
                    for pane in session.allPanes {
                        guard pane.splitTree.root.containsLeaf(paneID: paneID) else {
                            continue
                        }
                        activatePane(paneID, controller: controller, workspace: workspace, session: session, pane: pane)
                        return
                    }
                }
            }
        }
        for controller in controllers {
            let collection = controller.workspaceCollection
            for workspace in collection.workspaces {
                for session in workspace.sessionCollection.sessions {
                    for pane in session.allPanes {
                        guard let resolved = pane.paneID(forSurfaceID: paneID) else {
                            continue
                        }
                        activatePane(resolved, controller: controller, workspace: workspace, session: session, pane: pane)
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
        session: Session,
        pane: PaneViewModel
    ) {
        controller.workspaceCollection.activateWorkspace(id: workspace.id)
        workspace.sessionCollection.activateSession(id: session.id)
        // Reveal the region that holds this pane before focusing it — a terminal
        // pane is only interactable when its panel is visible.
        if pane.kind == .terminal {
            session.terminalVisible = true
        }
        session.focusedArea = pane.kind
        pane.focusPane(paneID: paneID)
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
