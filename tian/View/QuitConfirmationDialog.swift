import AppKit

/// Presents a native NSAlert for quit confirmation when running processes are detected.
@MainActor
enum QuitConfirmationDialog {

    /// Shows a quit confirmation as a sheet on the key window (async).
    /// Calls `onQuitAnyway` or `onCancel` when the user responds.
    static func showSheet(
        on window: NSWindow,
        processCount: Int,
        onQuitAnyway: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let alert = makeAlert(processCount: processCount)
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                onQuitAnyway()
            } else {
                onCancel()
            }
        }
    }

    /// Shows a quit confirmation as an app-modal dialog (synchronous).
    /// Returns `true` if the user chose "Quit Anyway".
    static func showModal(processCount: Int) -> Bool {
        let alert = makeAlert(processCount: processCount)
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Private

    private static func makeAlert(processCount: Int) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit tian?"

        if processCount == 1 {
            alert.informativeText = "A process is still running. It will be terminated if you quit."
        } else {
            alert.informativeText = "\(processCount) processes are still running. They will be terminated if you quit."
        }

        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true

        return alert
    }
}
