import AppKit

/// Presents an NSAlert for confirming worktree Space closure.
/// Follows the pattern established by `CloseConfirmationDialog`.
@MainActor
enum WorktreeCloseDialog {

    enum Response {
        case removeWorktreeAndClose
        case closeOnly
        case cancel
    }

    static func show(
        on window: NSWindow,
        worktreePath: String,
        completion: @escaping (Response) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Remove worktree?"
        alert.informativeText = "This space is backed by a git worktree at:\n\(worktreePath)"
        alert.addButton(withTitle: "Remove Worktree & Close")
        alert.addButton(withTitle: "Close Only")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                completion(.removeWorktreeAndClose)
            case .alertSecondButtonReturn:
                completion(.closeOnly)
            default:
                completion(.cancel)
            }
        }
    }
}
