import Foundation

/// The kind of macOS notification a Claude session-state transition warrants.
enum ClaudeNotificationTrigger: Equatable {
    /// The session is blocked on the user: a permission request or an open
    /// `AskUserQuestion` (both surface as `ClaudeSessionState.needsAttention`).
    case needsAttention
    /// Claude finished a turn and is waiting for the user, with no background
    /// work still running (`ClaudeSessionState.idle`).
    case done
}

/// Pure decision layer for Claude-session notifications: given a session-state
/// transition (and whether background work is still running), decide whether —
/// and with what meaning — a macOS banner should fire.
///
/// Deliberately side-effect-free so the notify policy is unit-testable in
/// isolation from focus, debounce, and delivery (which live in
/// `ClaudeSessionNotifier`). We notify on exactly the three moments the user
/// cares about — task done, input needed, and a question — and nothing else.
enum ClaudeNotificationPolicy {
    /// - Parameters:
    ///   - old: the pane's session state before this write (nil if unset).
    ///   - new: the pane's session state after this write (already reflecting
    ///     `ClaudeSessionState.canReplace`, so a suppressed write reads as
    ///     `old == new` and yields `nil`).
    ///   - hasBackgroundWork: whether the pane still has running background
    ///     activities (subagents / background bash). Gates `done`, because
    ///     Claude reports `idle` between turns while subagents are mid-flight
    ///     (the "false idle during background work" case).
    /// - Returns: the notification to fire, or `nil` for no notification.
    static func trigger(
        old: ClaudeSessionState?,
        new: ClaudeSessionState,
        hasBackgroundWork: Bool
    ) -> ClaudeNotificationTrigger? {
        // Only fire on a real transition — re-writing the same state (e.g.
        // idle_prompt after Stop already set idle) must not re-notify.
        guard old != new else { return nil }

        switch new {
        case .needsAttention:
            return .needsAttention
        case .idle where old != nil && !hasBackgroundWork:
            return .done
        case .idle, .busy, .active, .failed, .inactive:
            // busy/active are progress; inactive is teardown; failed stays a
            // sidebar-only signal; idle with background work is not yet "done";
            // first-ever idle (old == nil) is not a completed turn.
            return nil
        }
    }
}
