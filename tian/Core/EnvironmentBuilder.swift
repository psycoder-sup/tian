import Foundation

/// Builds the `TIAN_*` environment dictionary injected into every
/// spawned terminal shell so the CLI binary can identify its pane,
/// tab, space, and workspace.
enum EnvironmentBuilder {

    /// Returns a dictionary of environment variables for a new pane.
    ///
    /// The dictionary includes `TIAN_*` identifiers, `PATH` with the
    /// bundle's Resources directory prepended, and shell integration variables
    /// (`ZDOTDIR`, `TIAN_SHELL_INTEGRATION_DIR`, `TIAN_RESOURCES_DIR`)
    /// so the claude wrapper and CLI are discoverable from any shell.
    static func buildPaneEnvironment(
        socketPath: String,
        paneID: UUID,
        tabID: UUID,
        spaceID: UUID,
        workspaceID: UUID,
        cliPath: String
    ) -> [String: String] {
        let resourcesDir = Bundle.main.resourceURL?.path ?? ""
        let existingPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let shellIntegrationDir = resourcesDir + "/shell-integration"
        let zdotdir = shellIntegrationDir + "/zsh"

        // Preserve the user's original ZDOTDIR so our .zshenv can restore it.
        let originalZdotdir = ProcessInfo.processInfo.environment["ZDOTDIR"]
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? ""

        var env: [String: String] = [
            "TIAN_SOCKET": socketPath,
            "TIAN_PANE_ID": paneID.uuidString,
            "TIAN_TAB_ID": tabID.uuidString,
            "TIAN_SPACE_ID": spaceID.uuidString,
            "TIAN_WORKSPACE_ID": workspaceID.uuidString,
            "TIAN_CLI_PATH": cliPath,
            "TIAN_RESOURCES_DIR": resourcesDir,
            "TIAN_SHELL_INTEGRATION_DIR": shellIntegrationDir,
            // Resources is first so the bundled `tian` CLI (and `claude`
            // wrapper) win over anything else on PATH. The GUI executable in
            // Contents/MacOS is intentionally left off PATH so `tian` resolves
            // to the CLI, never the app binary.
            "PATH": "\(resourcesDir):\(existingPath)",
            // Suppress oh-my-zsh's auto-update "[Y/n]" prompt, which otherwise
            // blocks shell startup in spawned panes. (The dotenv "Source it?"
            // prompt is left intact — autostart runs after it is answered.)
            "DISABLE_AUTO_UPDATE": "true",
        ]

        // ZDOTDIR injection for zsh shell integration.
        env["ZDOTDIR"] = zdotdir
        env["TIAN_ORIGINAL_ZDOTDIR"] = originalZdotdir

        return env
    }
}
