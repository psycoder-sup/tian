import Foundation

/// Per-Space progress signal published by `WorktreeOrchestrator` while
/// `[[setup]]` or `[[archive]]` commands run. Drives both the sidebar Space-row indicator
/// and the bottom-right `SetupProgressCapsule`.
///
/// Lifecycle: `nil` ⇔ no setup/cleanup is in flight. Non-nil from just before the
/// first command runs until the loop exits (success, all-failed, or cancelled).
/// Cleared back to `nil` before layout application.
struct SetupProgress: Equatable, Sendable {

    /// Which lifecycle stage owns this progress snapshot. Drives the
    /// user-visible label prefix on both the sidebar row and the capsule.
    enum Phase: Equatable, Sendable {
        /// Active during `[[setup]]` command execution at create time.
        case setup
        /// Active during `[[archive]]` command execution at close time.
        case cleanup
        /// Active during `git worktree remove` + directory pruning.
        /// No step counter, no current command, no cancel affordance.
        case removing
    }

    let workspaceID: UUID
    let spaceID: UUID
    let phase: Phase
    let totalCommands: Int
    /// 0-based index of the currently executing command. `-1` before the
    /// first command starts. Always `-1` when `phase == .removing`.
    var currentIndex: Int
    /// The command string currently running, or `nil` before the first
    /// command starts. Always `nil` when `phase == .removing`.
    var currentCommand: String?
    /// Index of the most recent command that exited non-zero, if any.
    var lastFailedIndex: Int?

    static func starting(
        workspaceID: UUID,
        spaceID: UUID,
        phase: Phase,
        totalCommands: Int
    ) -> SetupProgress {
        SetupProgress(
            workspaceID: workspaceID,
            spaceID: spaceID,
            phase: phase,
            totalCommands: totalCommands,
            currentIndex: -1,
            currentCommand: nil,
            lastFailedIndex: nil
        )
    }

    /// Snapshot for the brief "Removing..." state (no archive commands or
    /// post-archive `git worktree remove` window). `totalCommands` is `0`
    /// and `stepText` is unused — UI gates on `phase == .removing`.
    static func removingPlaceholder(
        workspaceID: UUID,
        spaceID: UUID
    ) -> SetupProgress {
        SetupProgress(
            workspaceID: workspaceID,
            spaceID: spaceID,
            phase: .removing,
            totalCommands: 0,
            currentIndex: -1,
            currentCommand: nil,
            lastFailedIndex: nil
        )
    }

    // MARK: - UI helpers

    /// "n/N" step counter. Displays as 1/N before the first command starts
    /// so the user never sees 0/N.
    var stepText: String {
        let displayed = max(currentIndex + 1, 1)
        return "\(displayed)/\(totalCommands)"
    }

    /// Command currently running, with a placeholder before the first command.
    var commandLabel: String {
        currentCommand ?? "starting…"
    }

    /// True if any command in this run has exited non-zero. Drives the
    /// sticky failure glyph on both UI surfaces.
    var didFailRun: Bool {
        lastFailedIndex != nil
    }

    /// User-visible prefix on the sidebar row and capsule.
    /// "Setup", "Cleanup", or "Removing...".
    var labelPrefix: String {
        switch phase {
        case .setup:    return "Setup"
        case .cleanup:  return "Cleanup"
        case .removing: return "Removing..."
        }
    }
}
