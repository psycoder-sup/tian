import Foundation

/// Typed session state for a Claude Code session attached to a pane.
/// Priority ordering: needsAttention (1) > busy (2) > active (3) > idle (4) > inactive (5).
enum ClaudeSessionState: String, Codable, Sendable, Equatable, CaseIterable {
    case needsAttention = "needs_attention"
    case busy = "busy"
    case active = "active"
    case idle = "idle"
    case inactive = "inactive"

    private var priority: Int {
        switch self {
        case .needsAttention: 1
        case .busy: 2
        case .active: 3
        case .idle: 4
        case .inactive: 5
        }
    }
}

extension ClaudeSessionState: Comparable {
    static func < (lhs: ClaudeSessionState, rhs: ClaudeSessionState) -> Bool {
        // Higher priority (lower number) is "greater", so lhs < rhs when lhs has higher number.
        lhs.priority > rhs.priority
    }
}
