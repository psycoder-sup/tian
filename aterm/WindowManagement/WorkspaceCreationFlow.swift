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
}
