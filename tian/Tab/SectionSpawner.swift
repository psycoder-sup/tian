import Foundation

/// Configures a fresh `TerminalSurfaceView` for the given section kind.
///
/// Keeps the `"claude"` autostart literal in exactly one place — every
/// pane-creation call site routes through here to enforce FR-05 / FR-11.
enum SectionSpawner {
    /// The shell command a Claude pane auto-runs once its rc files finish.
    static let claudeAutostartCommand = "claude"

    /// - Parameters:
    ///   - view: the `TerminalSurfaceView` to configure. Must not yet be
    ///     attached to a window (debug-asserted); the initial-* fields are
    ///     read once during `GhosttyTerminalSurface.createSurface`.
    ///   - kind: which section the pane belongs to. Claude panes receive
    ///     `TIAN_AUTOSTART_CMD = "claude"`; Terminal panes get nothing.
    ///   - workingDirectory: starting working directory for the shell.
    ///   - environmentVariables: pre-built TIAN_* env vars (computed by
    ///     the caller via `EnvironmentBuilder` / `PaneHierarchyContext`).
    @MainActor
    static func configure(
        view: TerminalSurfaceView,
        kind: SectionKind,
        workingDirectory: String,
        environmentVariables: [String: String]
    ) {
        assert(view.window == nil, "SectionSpawner.configure must be called before the view enters a window")

        view.initialWorkingDirectory = workingDirectory
        view.environmentVariables = autostartEnvironment(kind: kind, base: environmentVariables)
        // Claude is launched from tian's bundled .zshrc (via TIAN_AUTOSTART_CMD),
        // not by injecting "claude\n" as keystrokes — injected keystrokes race
        // with interactive rc prompts (oh-my-zsh dotenv/auto-update) and get
        // swallowed before `claude` ever runs.
        view.initialInput = nil
    }

    /// Returns `base` with `TIAN_AUTOSTART_CMD` added for Claude panes so the
    /// bundled `.zshrc` runs `claude` after the user's rc files complete.
    @MainActor
    static func autostartEnvironment(
        kind: SectionKind,
        base: [String: String]
    ) -> [String: String] {
        var env = base
        switch kind {
        case .claude:
            env["TIAN_AUTOSTART_CMD"] = claudeAutostartCommand
        case .terminal:
            break
        }
        return env
    }
}
