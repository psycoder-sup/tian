import Foundation

/// Builds the `ATERM_*` environment dictionary injected into every
/// spawned terminal shell so the CLI binary can identify its pane,
/// tab, space, and workspace.
enum EnvironmentBuilder {

    /// Returns a dictionary of environment variables for a new pane.
    ///
    /// The dictionary contains 7 entries: `ATERM_SOCKET`, `ATERM_PANE_ID`,
    /// `ATERM_TAB_ID`, `ATERM_SPACE_ID`, `ATERM_WORKSPACE_ID`,
    /// `ATERM_CLI_PATH`, and `PATH` (prepended with the app bundle's
    /// `MacOS` directory so the CLI binary is on the user's path).
    static func buildPaneEnvironment(
        socketPath: String,
        paneID: UUID,
        tabID: UUID,
        spaceID: UUID,
        workspaceID: UUID,
        cliPath: String
    ) -> [String: String] {
        let macOSDir = Bundle.main.executableURL!
            .deletingLastPathComponent()
            .path
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? ""

        return [
            "ATERM_SOCKET": socketPath,
            "ATERM_PANE_ID": paneID.uuidString,
            "ATERM_TAB_ID": tabID.uuidString,
            "ATERM_SPACE_ID": spaceID.uuidString,
            "ATERM_WORKSPACE_ID": workspaceID.uuidString,
            "ATERM_CLI_PATH": cliPath,
            "PATH": "\(macOSDir):\(existingPath)",
        ]
    }
}
