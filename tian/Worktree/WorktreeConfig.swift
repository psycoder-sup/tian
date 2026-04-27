import Foundation

/// Top-level configuration parsed from `.tian/config.toml`.
struct WorktreeConfig: Sendable, Equatable {
    /// Default grace period (seconds) between SIGTERM and SIGKILL.
    static let defaultKillGrace: TimeInterval = 2.0
    /// Lower / upper bounds applied to the parsed `setup_kill_grace` value
    /// to keep a misconfigured config from hanging the orchestrator.
    static let killGraceBounds: ClosedRange<TimeInterval> = 0.1...60.0

    /// Worktree base directory. Tilde-expanded or absolute paths (e.g. `~/.worktrees`)
    /// place worktrees at `<dir>/<repo-name>/<branch>`. Relative paths are resolved
    /// from the repo root (e.g. `.worktrees` → `<repo>/.worktrees/<branch>`).
    var worktreeDir: String = "~/.worktrees"
    /// Timeout in seconds per setup command.
    var setupTimeout: TimeInterval = 300
    /// Grace period in seconds between SIGTERM and SIGKILL when a
    /// `[[setup]]` or `[[archive]]` command must be killed (timeout or
    /// user-cancel). A child that traps or ignores SIGTERM is force-killed
    /// after this interval so the awaiting flow can never hang
    /// indefinitely.
    var setupKillGrace: TimeInterval = WorktreeConfig.defaultKillGrace
    /// Fallback delay in seconds for shell readiness when OSC 7 is not received.
    var shellReadyDelay: TimeInterval = 0.5
    /// Files to copy from main worktree to new worktree.
    var copyRules: [CopyRule] = []
    /// Ordered shell commands to run during setup.
    var setupCommands: [String] = []
    /// Ordered shell commands to run on worktree removal — the inverse of
    /// `setupCommands`. Use to tear down side effects spawned by setup
    /// (e.g. `docker compose down`). Run with the worktree root as cwd
    /// before the worktree directory is deleted.
    var archiveCommands: [String] = []
    /// Pane layout tree for the first tab.
    var layout: LayoutNode?
}

/// A single file copy directive.
struct CopyRule: Sendable, Equatable {
    /// Glob pattern relative to repo root (e.g., `.env*`).
    var source: String
    /// Destination path relative to repo root. If it ends with `/`, files are placed inside that directory.
    var dest: String
}

/// A recursive layout tree node, mirroring `PaneNode` structure.
indirect enum LayoutNode: Sendable, Equatable {
    /// A terminal pane. `command` is the startup command (nil means plain shell).
    case pane(command: String?)
    /// A split container with two children.
    case split(direction: SplitDirection, ratio: Double, first: LayoutNode, second: LayoutNode)

    /// Total number of leaf panes in the layout tree.
    var paneCount: Int {
        switch self {
        case .pane:
            return 1
        case .split(_, _, let first, let second):
            return first.paneCount + second.paneCount
        }
    }
}
