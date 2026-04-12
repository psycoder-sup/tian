import AppKit
import Foundation

/// Coordinates the "pick directory → create workspace" flow for all explicit
/// workspace creation entry points (menu, sidebar button, first launch).
///
/// Internal helpers are exposed as static members for unit testing.
@MainActor
enum WorkspaceCreationFlow {

    /// Derives a workspace name from a directory URL's last path component.
    /// Returns nil if the basename is empty or equal to "/" — caller falls
    /// back to `WorkspaceCollection`'s auto-generated "Workspace N".
    static func deriveWorkspaceName(from url: URL) -> String? {
        let basename = url.standardizedFileURL.lastPathComponent
        if basename.isEmpty || basename == "/" {
            return nil
        }
        return basename
    }

    /// Presents a directory picker and, if the user picks a directory, creates
    /// and activates a workspace in `collection` anchored to that directory.
    ///
    /// - Returns: The created workspace, or nil if the user cancelled.
    @discardableResult
    static func createWorkspace(in collection: WorkspaceCollection) -> Workspace? {
        guard let url = runPicker() else { return nil }
        let standardized = url.standardizedFileURL
        if let name = deriveWorkspaceName(from: standardized) {
            return collection.createWorkspace(name: name, workingDirectory: standardized.path)
        } else {
            return collection.createWorkspace(workingDirectory: standardized.path)
        }
    }

    /// Runs a directory-only `NSOpenPanel`. Returns the chosen URL, or nil on cancel.
    private static func runPicker() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a directory for this workspace"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Runs a modal directory picker that keeps re-presenting itself until the
    /// user picks a directory. An accessory "Quit aterm" button is the only
    /// non-picking exit, returning nil so the caller can terminate the app.
    static func runFirstLaunchPicker() -> URL? {
        while true {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose"
            panel.message = "Choose a directory for your first workspace"

            // Accessory view with a "Quit aterm" button. Tag 99 signals quit.
            let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 36))
            let quitButton = NSButton(frame: NSRect(x: 12, y: 6, width: 120, height: 24))
            quitButton.title = "Quit aterm"
            quitButton.bezelStyle = .rounded
            quitButton.target = QuitResponder.shared
            quitButton.action = #selector(QuitResponder.quitPressed(_:))
            quitButton.tag = 99
            accessory.addSubview(quitButton)
            panel.accessoryView = accessory
            panel.isAccessoryViewDisclosed = true

            QuitResponder.shared.quitRequested = false
            let response = panel.runModal()

            if QuitResponder.shared.quitRequested {
                return nil
            }
            if response == .OK, let url = panel.url {
                return url
            }
            // Any other dismissal (Cancel, close, Esc) — loop and re-present.
        }
    }
}

/// Local responder for the first-launch picker's "Quit aterm" accessory button.
/// `NSOpenPanel` does not expose an out-of-band quit channel, so we stop the
/// modal and flag the intent for the picker loop to read.
@MainActor
private final class QuitResponder: NSObject {
    static let shared = QuitResponder()
    var quitRequested = false

    @objc func quitPressed(_ sender: NSButton) {
        quitRequested = true
        NSApp.stopModal(withCode: .cancel)
    }
}
