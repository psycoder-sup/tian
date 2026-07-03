import Foundation

enum WorkingDirectoryResolver {
    /// Resolves the working directory for a new pane by walking up the hierarchy.
    ///
    /// Resolution order:
    /// 1. `sourcePaneDirectory` -- inherited from the source pane (split/new pane)
    /// 2. `sessionDefault` -- the session-level default working directory
    /// 3. `workspaceDefault` -- the workspace-level default working directory
    /// 4. `home` -- the user's home directory ($HOME)
    static func resolve(
        sourcePaneDirectory: String?,
        sessionDefault: URL?,
        workspaceDefault: URL?,
        home: String = ProcessInfo.processInfo.environment["HOME"] ?? "~"
    ) -> String {
        if let source = sourcePaneDirectory, !source.isEmpty, source != "~" {
            return source
        }
        if let sessionDir = sessionDefault {
            return sessionDir.path
        }
        if let workspaceDir = workspaceDefault {
            return workspaceDir.path
        }
        return home
    }
}
