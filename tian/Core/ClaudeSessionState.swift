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

    /// Whether this state reports the session *getting on with work* — the states a
    /// pending prompt is resolved by, and so the ones `PaneStatusManager` gates on
    /// the attention owner. `failed` and `inactive` are not: they end the turn (or
    /// the session) whoever reports them.
    var resumesWork: Bool {
        self == .busy || self == .active
    }
}

extension ClaudeSessionState: Comparable {
    static func < (lhs: ClaudeSessionState, rhs: ClaudeSessionState) -> Bool {
        // Higher priority (lower number) is "greater", so lhs < rhs when lhs has higher number.
        lhs.priority > rhs.priority
    }
}

/// Who inside a Claude session produced a hook event: the main thread, or one of
/// its subagents.
///
/// Claude Code fires the tool hooks for a subagent's calls from the *same*
/// process, with the same `TIAN_PANE_ID` — the only discriminator in the payload
/// is `agent_id`, empty for the main thread and an opaque id for a subagent. Panes
/// therefore need this to tell "the thread that raised the prompt is moving again"
/// apart from "some unrelated background agent is working" (see
/// `PaneStatusManager`'s attention ownership).
enum ClaudeEventOrigin: Equatable, Sendable {
    case main
    case agent(String)

    /// Builds an origin from a hook payload's `agent_id`: absent or empty means the
    /// main thread.
    init(agentID: String?) {
        guard let agentID, !agentID.isEmpty else {
            self = .main
            return
        }
        self = .agent(agentID)
    }

    /// The underlying agent id, for logging. Empty string for the main thread.
    var agentID: String {
        switch self {
        case .main: ""
        case .agent(let id): id
        }
    }
}
