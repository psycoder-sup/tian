import Foundation

/// Result of a worktree Session creation attempt.
struct WorktreeCreateResult: Sendable {
    /// The ID of the created or found Session.
    let sessionID: UUID
    /// True if an existing Session was focused instead of creating a new one.
    let existed: Bool
    /// The focused leaf of the Session's Claude pane. This is the worktree's
    /// primary Claude session; callers can target it with `tian pane send` /
    /// `pane capture`. `nil` when the Session has no live Claude pane.
    let claudePaneID: UUID?
    /// The focused leaf of the Session's terminal panel (post-`showTerminal`),
    /// or `nil` when the Session has no terminal panel yet.
    let terminalPaneID: UUID?
}
