import Foundation

/// Result of a worktree Space creation attempt.
struct WorktreeCreateResult: Sendable {
    /// The ID of the created or found Space.
    let spaceID: UUID
    /// True if an existing Space was focused instead of creating a new one.
    let existed: Bool
    /// The primary terminal tab of the Space (nil if it has no terminal tab yet).
    let tabID: UUID?
    /// The focused pane within the primary tab (nil if it has no terminal pane yet).
    /// Callers can immediately target this with `tian pane send` / `pane capture`.
    let paneID: UUID?
    /// The Space's auto-seeded Claude tab (nil if the Claude section has no tab).
    let claudeTabID: UUID?
    /// The focused pane within the Claude tab. This is the worktree's primary
    /// Claude session; callers can target it with `tian pane send` / `pane capture`.
    let claudePaneID: UUID?
}
