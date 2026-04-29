import AppKit

@MainActor
enum SkipTeardownConfirmationDialog {

    enum Response { case skipTeardown, cancel }

    static func show(
        on window: NSWindow,
        archiveCommandCount: Int,
        completion: @escaping (Response) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Skip teardown?"
        alert.informativeText = """
        This space has \(archiveCommandCount) archive command\
        \(archiveCommandCount == 1 ? "" : "s") configured \
        in .tian/config.toml that will not run if you close \
        without removing the worktree.
        """
        alert.addButton(withTitle: "Skip Teardown")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: completion(.skipTeardown)
            default:                       completion(.cancel)
            }
        }
    }
}
