import AppKit
import SwiftUI

@MainActor
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator
    private weak var workspaceManager: WorkspaceManager?
    private weak var windowCoordinator: WindowCoordinator?
    private var eventMonitor: Any?

    init(
        workspaceCollection: WorkspaceCollection,
        workspaceManager: WorkspaceManager,
        windowCoordinator: WindowCoordinator
    ) {
        self.workspaceCollection = workspaceCollection
        self.worktreeOrchestrator = WorktreeOrchestrator(workspaceProvider: windowCoordinator)
        self.workspaceManager = workspaceManager
        self.windowCoordinator = windowCoordinator

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = workspaceCollection.activeWorkspace?.name ?? "aterm"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .terminalBackground
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()

        let contentView = WorkspaceWindowContent(
            workspaceCollection: workspaceCollection,
            worktreeOrchestrator: worktreeOrchestrator
        )
        let hostingView = NSHostingView(rootView: contentView)
        window.contentView = hostingView
        window.initialFirstResponder = hostingView

        super.init(window: window)
        window.delegate = self

        installTrafficLightAligner(window: window)
        observeActiveWorkspaceName()
        installKeyboardMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Traffic Lights

    private var trafficLightAligner: TrafficLightAligner?

    private func installTrafficLightAligner(window: NSWindow) {
        trafficLightAligner = TrafficLightAligner(window: window, targetHeight: 44)
    }

    // MARK: - Name Observation

    private func observeActiveWorkspaceName() {
        withObservationTracking {
            _ = workspaceCollection.activeWorkspaceID
            _ = workspaceCollection.activeWorkspace?.name
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let window = self.window else { return }
                window.title = self.workspaceCollection.activeWorkspace?.name ?? "aterm"
                self.observeActiveWorkspaceName()
            }
        }
    }

    // MARK: - Keyboard Monitor

    private func installKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            guard event.window === self.window else { return event }

            guard let action = KeyBindingRegistry.shared.action(for: event) else {
                return event
            }

            if let responder = event.window?.firstResponder, responder is NSText {
                switch action {
                case .toggleSidebar, .focusSidebar, .toggleDebugOverlay:
                    break
                default:
                    return event
                }
            }

            switch action {
            case .nextSpace:
                self.workspaceCollection.nextSpaceGlobal()
                return nil
            case .previousSpace:
                self.workspaceCollection.previousSpaceGlobal()
                return nil
            case .nextWorkspace:
                self.workspaceCollection.nextWorkspace()
                return nil
            case .previousWorkspace:
                self.workspaceCollection.previousWorkspace()
                return nil
            case .newWorkspace:
                WorkspaceCreationFlow.createWorkspace(in: self.workspaceCollection)
                return nil
            case .closeWorkspace:
                if let id = self.workspaceCollection.activeWorkspaceID {
                    self.workspaceCollection.removeWorkspace(id: id)
                }
                return nil
            case .toggleSidebar:
                self.handleSidebarToggle()
                return nil
            case .focusSidebar:
                NotificationCenter.default.post(
                    name: .focusSidebar,
                    object: self.workspaceCollection
                )
                return nil
            case .toggleDebugOverlay:
                NotificationCenter.default.post(
                    name: .toggleDebugOverlay,
                    object: self.workspaceCollection
                )
                return nil
            case .newWorktreeSpace:
                self.handleNewWorktreeSpace()
                return nil
            default:
                break
            }

            guard let collection = self.workspaceCollection.activeSpaceCollection else { return event }

            switch action {
            case .newTab:
                guard let space = collection.activeSpace else { return event }
                let wd = collection.resolveWorkingDirectory()
                space.createTab(workingDirectory: wd)
            case .nextTab:
                collection.activeSpace?.nextTab()
            case .previousTab:
                collection.activeSpace?.previousTab()
            case .goToTab(let index):
                collection.activeSpace?.goToTab(index: index)
            case .newSpace:
                let wd = collection.resolveWorkingDirectory()
                collection.createSpace(workingDirectory: wd)
            default:
                return event
            }

            return nil
        }
    }

    // MARK: - Sidebar

    private func handleSidebarToggle() {
        NotificationCenter.default.post(
            name: .toggleSidebar,
            object: self.workspaceCollection
        )
    }

    // MARK: - Worktree

    private func handleNewWorktreeSpace() {
        let wd = workspaceCollection.activeSpaceCollection?.resolveWorkingDirectory() ?? ""
        NotificationCenter.default.post(
            name: .showWorktreeBranchInput,
            object: workspaceCollection,
            userInfo: [Notification.worktreeWorkingDirectoryKey: wd]
        )
    }

    private func removeKeyboardMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let windowCount = windowCoordinator?.windowCount ?? -1
        Log.lifecycle.info("[WindowController.windowShouldClose] windowCount=\(windowCount), workspaces=\(self.workspaceCollection.workspaces.count)")
        // If this is the last window, delegate to the app termination flow
        // so session state is serialized and process detection runs.
        if windowCoordinator?.windowCount == 1 {
            Log.lifecycle.info("[WindowController.windowShouldClose] last window — calling NSApp.terminate")
            NSApp.terminate(nil)
            return false
        }

        for workspace in workspaceCollection.workspaces {
            workspace.cleanup()
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        Log.lifecycle.info("[WindowController.windowWillClose] window closing")
        trafficLightAligner?.tearDown()
        removeKeyboardMonitor()
        windowCoordinator?.removeController(self)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        workspaceManager?.activeWorkspaceID = workspaceCollection.activeWorkspaceID
    }
}
