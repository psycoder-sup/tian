import AppKit

/// Orchestrates the quit sequence: process detection, confirmation dialog,
/// session serialization, cleanup, and termination reply.
@MainActor
final class QuitFlowCoordinator {
    private let windowCoordinator: WindowCoordinator
    private var isShowingDialog = false

    init(windowCoordinator: WindowCoordinator) {
        self.windowCoordinator = windowCoordinator
    }

    /// Called from `applicationShouldTerminate`. Returns `.terminateNow` if no
    /// confirmation is needed, or `.terminateLater` when a sheet is presented.
    func initiateQuit() -> NSApplication.TerminateReply {
        guard !isShowingDialog else { return .terminateCancel }

        let collections = windowCoordinator.allWorkspaceCollections
        let runningProcesses = ProcessDetector.detectRunningProcesses(in: collections)

        if runningProcesses.isEmpty {
            performQuitSequence()
            return .terminateNow
        }

        let processCount = runningProcesses.count

        if let keyWindow = NSApp.keyWindow {
            // Async path: show sheet, return .terminateLater, reply later
            isShowingDialog = true
            QuitConfirmationDialog.showSheet(
                on: keyWindow,
                processCount: processCount,
                onQuitAnyway: { [self] in
                    isShowingDialog = false
                    performQuitSequence()
                    NSApp.reply(toApplicationShouldTerminate: true)
                },
                onCancel: { [self] in
                    isShowingDialog = false
                    NSApp.reply(toApplicationShouldTerminate: false)
                }
            )
            return .terminateLater
        } else {
            // Sync path: runModal blocks, return the result directly
            let shouldQuit = QuitConfirmationDialog.showModal(processCount: processCount)
            if shouldQuit {
                performQuitSequence()
                return .terminateNow
            } else {
                return .terminateCancel
            }
        }
    }

    // MARK: - Private

    private func performQuitSequence() {
        serializeSession()

        for collection in windowCoordinator.allWorkspaceCollections {
            for workspace in collection.workspaces {
                workspace.cleanup()
            }
        }
    }

    private func serializeSession() {
        let controllers = windowCoordinator.allControllers
        if controllers.count > 1 {
            Log.lifecycle.warning("Multiple window controllers detected; only the first window's state will be saved")
        }

        guard let controller = controllers.first else { return }

        let collection = controller.workspaceCollection
        let window = controller.window

        let windowFrame: WindowFrame? = window.map { w in
            let frame = w.frame
            return WindowFrame(
                x: frame.origin.x,
                y: frame.origin.y,
                width: frame.size.width,
                height: frame.size.height
            )
        }
        let isFullscreen = window?.styleMask.contains(.fullScreen) ?? false

        let state = SessionSerializer.snapshot(
            from: collection,
            windowFrame: windowFrame,
            isFullscreen: isFullscreen
        )

        do {
            try SessionSerializer.save(state)
            Log.lifecycle.info("Session state saved successfully")
        } catch {
            Log.lifecycle.error("Failed to save session state: \(error.localizedDescription)")
        }
    }
}
