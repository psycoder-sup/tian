import Foundation

enum WorkingDirectoryResolver {
    /// Resolves the working directory for a new pane by walking up the hierarchy.
    ///
    /// Resolution order:
    /// 1. `sourcePaneDirectory` -- inherited from the source pane (split/new tab)
    /// 2. `spaceDefault` -- the space-level default working directory
    /// 3. `workspaceDefault` -- the workspace-level default working directory
    /// 4. `home` -- the user's home directory ($HOME)
    static func resolve(
        sourcePaneDirectory: String?,
        spaceDefault: URL?,
        workspaceDefault: URL?,
        home: String = ProcessInfo.processInfo.environment["HOME"] ?? "~"
    ) -> String {
        if let source = sourcePaneDirectory, !source.isEmpty, source != "~" {
            return source
        }
        if let spaceDir = spaceDefault {
            return spaceDir.path
        }
        if let workspaceDir = workspaceDefault {
            return workspaceDir.path
        }
        return home
    }
}
