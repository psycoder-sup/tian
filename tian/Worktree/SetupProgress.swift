import Foundation

/// Per-Space progress signal published by `WorktreeOrchestrator` while
/// `[[setup]]` commands run. Drives both the sidebar Space-row indicator
/// and the bottom-right `SetupProgressCapsule`.
///
/// Lifecycle:
/// - `nil` ⇔ no setup is in flight.
/// - Non-nil from just before the first `[[setup]]` command runs until
///   the loop exits (success, all-failed, or cancelled). Cleared back
///   to `nil` before layout application.
struct SetupProgress: Equatable, Sendable {
    /// Workspace that owns the new Space.
    let workspaceID: UUID
    /// The Space being set up.
    let spaceID: UUID
    /// Number of `[[setup]]` commands declared in `.tian/config.toml`.
    let totalCommands: Int
    /// 0-based index of the currently executing command. `-1` before the
    /// first command starts.
    var currentIndex: Int
    /// The command string currently running, or `nil` before the first
    /// command starts.
    var currentCommand: String?
    /// Index of the most recent command that exited non-zero, if any.
    var lastFailedIndex: Int?

    /// Builds the initial pre-run progress value.
    static func starting(
        workspaceID: UUID,
        spaceID: UUID,
        totalCommands: Int
    ) -> SetupProgress {
        SetupProgress(
            workspaceID: workspaceID,
            spaceID: spaceID,
            totalCommands: totalCommands,
            currentIndex: -1,
            currentCommand: nil,
            lastFailedIndex: nil
        )
    }
}

/// Sendable handle for terminating an in-flight setup command from another
/// isolation domain. The closure captures only the child PID and signals
/// it via `kill(2)`.
struct SetupCancellationToken: Sendable {
    let terminate: @Sendable () -> Void
}
