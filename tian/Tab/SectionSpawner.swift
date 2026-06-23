import Foundation

/// Configures a fresh `TerminalSurfaceView` for the given section kind.
///
/// Keeps the `"claude"` autostart literal in exactly one place — every
/// pane-creation call site routes through here to enforce FR-05 / FR-11.
enum SectionSpawner {
    /// The shell command a Claude pane auto-runs once its rc files finish.
    /// Resolved from `TianSettings` so the user can customise it (e.g.
    /// `claude --chrome`, `headroom wrap claude`); falls back to bare `claude`
    /// when unset.
    @MainActor
    static var claudeAutostartCommand: String { TianSettings.shared.effectiveClaudeCommand }

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
    /// bundled `.zshrc` runs the autostart command after the user's rc files
    /// complete.
    ///
    /// - Parameter restoreCommand: a per-pane restore command (e.g.
    ///   `"claude --resume <id>"`) registered via IPC and persisted across
    ///   sessions. When present it *replaces* the bare `claude` launch so the
    ///   session resumes — routed through the same `TIAN_AUTOSTART_CMD` path
    ///   (which survives interactive rc prompts) rather than injected as
    ///   keystrokes, which would race with `claude` already autostarting.
    @MainActor
    static func autostartEnvironment(
        kind: SectionKind,
        base: [String: String],
        restoreCommand: String? = nil
    ) -> [String: String] {
        var env = base
        if let cmd = autostartCommand(kind: kind, restoreCommand: restoreCommand) {
            env["TIAN_AUTOSTART_CMD"] = cmd
        }
        return env
    }

    /// Resolves the shell command an autostart pane runs on its first prompt,
    /// or `nil` if the pane should land on a plain shell. A restore command
    /// takes precedence over the kind-based default. Terminal panes never
    /// autostart — they replay any restore command as keystrokes instead.
    @MainActor
    static func autostartCommand(
        kind: SectionKind,
        restoreCommand: String?
    ) -> String? {
        switch kind {
        case .claude:
            return restoreCommand ?? claudeAutostartCommand
        case .terminal:
            return nil
        }
    }
}
