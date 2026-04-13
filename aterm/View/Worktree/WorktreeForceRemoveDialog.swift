import AppKit

@MainActor
enum WorktreeForceRemoveDialog {

    enum Response {
        case forceRemove
        case cancel
    }

    static func show(
        on window: NSWindow,
        worktreePath: String,
        completion: @escaping (Response) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Worktree has uncommitted changes"
        alert.informativeText = "Removing will discard uncommitted or untracked changes at:\n\(worktreePath)"
        alert.addButton(withTitle: "Force Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                completion(.forceRemove)
            default:
                completion(.cancel)
            }
        }
    }
}
