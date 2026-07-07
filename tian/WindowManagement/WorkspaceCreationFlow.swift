import Foundation

@MainActor
enum WorkspaceCreationFlow {

    /// Returns nil for basenames that can't name a workspace (empty or "/"),
    /// signalling the caller to fall back to auto-numbered "Workspace N".
    static func deriveWorkspaceName(from url: URL) -> String? {
        let basename = url.standardizedFileURL.lastPathComponent
        if basename.isEmpty || basename == "/" {
            return nil
        }
        return basename
    }

    @discardableResult
    static func createWorkspace(in collection: WorkspaceCollection) -> Workspace? {
        guard let url = DirectoryPicker.chooseDirectory(
            title: "New Workspace",
            prompt: "Choose",
            message: "Choose a directory for this workspace"
        ) else { return nil }
        let standardized = url.standardizedFileURL
        if let name = deriveWorkspaceName(from: standardized) {
            return collection.createWorkspace(name: name, workingDirectory: standardized.path)
        } else {
            return collection.createWorkspace(workingDirectory: standardized.path)
        }
    }

    /// Opens the SSH-workspace creation modal for `collection` (host + remote
    /// directory can't come from a native directory picker, so this posts a
    /// notification that `WorkspaceWindowContent` renders `CreateWorkspaceView`
    /// for).
    static func requestSSHWorkspace(in collection: WorkspaceCollection) {
        NotificationCenter.default.post(name: .showCreateSSHWorkspaceInput, object: collection)
    }
}
