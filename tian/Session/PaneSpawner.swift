import Foundation

/// Configures a fresh `TerminalSurfaceView` for the given pane kind.
///
/// Keeps the `"claude"` autostart literal in exactly one place — every
/// pane-creation call site routes through here to enforce FR-05 / FR-11.
enum PaneSpawner {
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
    ///   - kind: which kind the pane belongs to. Claude panes receive
    ///     `TIAN_AUTOSTART_CMD = "claude"`; Terminal panes get nothing.
    ///   - workingDirectory: starting working directory for the shell. For a
    ///     remote pane this is the remote `cd` target embedded in the ssh line.
    ///   - environmentVariables: pre-built TIAN_* env vars (computed by
    ///     the caller via `EnvironmentBuilder` / `PaneHierarchyContext`).
    ///   - remoteSpawn: non-nil for a remote workspace — routes the pane through
    ///     `ssh -tt` instead of a local shell.
    @MainActor
    static func configure(
        view: TerminalSurfaceView,
        kind: PaneKind,
        workingDirectory: String,
        environmentVariables: [String: String],
        remoteSpawn: RemoteSpawnSpec? = nil
    ) {
        assert(view.window == nil, "PaneSpawner.configure must be called before the view enters a window")

        if let remoteSpawn {
            configureRemote(
                view: view,
                kind: kind,
                workingDirectory: workingDirectory,
                environmentVariables: environmentVariables,
                remoteSpawn: remoteSpawn
            )
            return
        }

        view.initialWorkingDirectory = workingDirectory
        view.environmentVariables = autostartEnvironment(kind: kind, base: environmentVariables)
        // Claude is launched from tian's bundled .zshrc (via TIAN_AUTOSTART_CMD),
        // not by injecting "claude\n" as keystrokes — injected keystrokes race
        // with interactive rc prompts (oh-my-zsh dotenv/auto-update) and get
        // swallowed before `claude` ever runs.
        view.initialInput = nil
    }

    /// Remote pane configuration: ghostty runs an `ssh -tt … 'cd <dir> && exec
    /// <cmd>'` line via `/bin/sh -c` in place of a login shell.
    ///
    /// Ghostty chdirs *locally* before exec, so the local working directory is
    /// kept at `$HOME` (a real, always-present local dir) — the remote `cd`
    /// happens inside the ssh command. There is NO `TIAN_AUTOSTART_CMD`: Claude
    /// runs on the remote host, launched directly by the ssh line, not by tian's
    /// bundled local `.zshrc` (which isn't on the remote).
    @MainActor
    private static func configureRemote(
        view: TerminalSurfaceView,
        kind: PaneKind,
        workingDirectory: String,
        environmentVariables: [String: String],
        remoteSpawn: RemoteSpawnSpec
    ) {
        view.initialWorkingDirectory = NSHomeDirectory()
        view.environmentVariables = environmentVariables
        view.initialInput = nil
        view.initialCommand = RemoteCommandBuilder.interactiveSSHCommandLine(
            host: remoteSpawn.channel.host,
            workingDirectory: workingDirectory,
            remoteCommand: remoteCommand(kind: kind)
        )
        view.waitAfterCommand = true
    }

    /// The command a remote pane execs on the host. The builder prepends `exec `,
    /// so these are the bare target (no leading `exec`); both are inserted into
    /// the remote-shell fragment unquoted, so `$SHELL` expands remotely.
    ///
    /// Both run through a **login + interactive** shell (`-lic` / `-l` with a
    /// tty). `ssh host <cmd>` otherwise runs a non-login, non-interactive shell
    /// whose PATH is the bare `/usr/bin:/bin:…`, so a direct `exec claude` fails
    /// with "command not found" (Claude typically lives in `~/.local/bin`, put on
    /// PATH by the user's `.zshrc`). Routing Claude through `$SHELL -lic` sources
    /// the user's rc files first — the remote analogue of the local pane's
    /// bundled-`.zshrc` autostart.
    @MainActor
    static func remoteCommand(kind: PaneKind) -> String {
        switch kind {
        case .claude:
            // `$SHELL -lic '<claude command>'` — the launch command is passed as a
            // single `-c` argument (single-quoted for that login shell); the
            // builder's outer quoting escapes these quotes for the layers above.
            return "\"${SHELL:-/bin/sh}\" -lic " + ShellQuoting.singleQuote(claudeAutostartCommand)
        case .terminal:
            // A login shell with a tty is already interactive (sources .zshrc),
            // so the user's normal environment/PATH is present.
            return "\"${SHELL:-/bin/sh}\" -l"
        }
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
        kind: PaneKind,
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
        kind: PaneKind,
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
