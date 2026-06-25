import Foundation

/// Typed session state for a Claude Code session attached to a pane.
/// Priority ordering: needsAttention (1) > failed (2) > busy (3) > active (4) > idle (5) > inactive (6).
enum ClaudeSessionState: String, Codable, Sendable, Equatable, CaseIterable {
    case needsAttention = "needs_attention"
    case failed = "failed"
    case busy = "busy"
    case active = "active"
    case idle = "idle"
    case inactive = "inactive"

    private var priority: Int {
        switch self {
        case .needsAttention: 1
        case .failed: 2
        case .busy: 3
        case .active: 4
        case .idle: 5
        case .inactive: 6
        }
    }

    /// Whether an incoming `self` should overwrite `current` for the same pane.
    ///
    /// Session state is otherwise last-write-wins, but a clean turn-end
    /// (`idle`) must not paper over a state the user still needs to act on: a
    /// pending prompt (`needsAttention`) or a recorded turn failure (`failed`).
    /// Both are cleared by the next real activity (`busy`) or by session end
    /// (`inactive`) — never by `idle`. This also makes the Stop/StopFailure
    /// ordering race deterministic: whichever fires last, the failure is not
    /// lost to a trailing `idle`.
    func canReplace(_ current: ClaudeSessionState?) -> Bool {
        guard let current else { return true }
        if self == .idle, current == .needsAttention || current == .failed {
            return false
        }
        return true
    }
}

extension ClaudeSessionState: Comparable {
    static func < (lhs: ClaudeSessionState, rhs: ClaudeSessionState) -> Bool {
        // Higher priority (lower number) is "greater", so lhs < rhs when lhs has higher number.
        lhs.priority > rhs.priority
    }
}
