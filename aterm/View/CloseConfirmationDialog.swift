import AppKit

/// Presents a native NSAlert for close confirmation when running processes are detected
/// in a pane, tab, or set of tabs.
@MainActor
enum CloseConfirmationDialog {

    enum CloseTarget {
        case pane
        case tab
        case tabs(count: Int)
    }

    /// Checks processCount > 0 and shows a sheet; otherwise runs the action directly.
    static func confirmIfNeeded(
        processCount: Int,
        target: CloseTarget,
        action: @escaping () -> Void
    ) {
        guard processCount > 0 else {
            action()
            return
        }
        guard let window = NSApp.keyWindow else {
            return
        }
        showSheet(
            on: window,
            target: target,
            processCount: processCount,
            onCloseAnyway: action
        )
    }

    /// Shows a close confirmation as a sheet on the given window.
    static func showSheet(
        on window: NSWindow,
        target: CloseTarget,
        processCount: Int,
        onCloseAnyway: @escaping () -> Void,
        onCancel: @escaping () -> Void = { }
    ) {
        let alert = makeAlert(target: target, processCount: processCount)
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                onCloseAnyway()
            } else {
                onCancel()
            }
        }
    }

    // MARK: - Private

    private static func makeAlert(target: CloseTarget, processCount: Int) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch target {
        case .pane:
            alert.messageText = "Close Pane?"
        case .tab:
            alert.messageText = "Close Tab?"
        case .tabs(let count):
            alert.messageText = "Close \(count) Tabs?"
        }

        if processCount == 1 {
            alert.informativeText = "A process is still running. It will be terminated if you close."
        } else {
            alert.informativeText = "\(processCount) processes are still running. They will be terminated if you close."
        }

        alert.addButton(withTitle: "Close Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true

        return alert
    }
}
