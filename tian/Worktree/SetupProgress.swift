import Foundation

/// Per-Space progress signal published by `WorktreeOrchestrator` while
/// `[[setup]]` commands run. Drives both the sidebar Space-row indicator
/// and the bottom-right `SetupProgressCapsule`.
///
/// Lifecycle: `nil` ⇔ no setup is in flight. Non-nil from just before the
/// first `[[setup]]` command runs until the loop exits (success, all-failed,
/// or cancelled). Cleared back to `nil` before layout application.
struct SetupProgress: Equatable, Sendable {
    let workspaceID: UUID
    let spaceID: UUID
    let totalCommands: Int
    /// 0-based index of the currently executing command. `-1` before the
    /// first command starts.
    var currentIndex: Int
    /// The command string currently running, or `nil` before the first
    /// command starts.
    var currentCommand: String?
    /// Index of the most recent command that exited non-zero, if any.
    var lastFailedIndex: Int?

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
}
