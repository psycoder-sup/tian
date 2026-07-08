import Testing
@testable import tian

// Pure decision layer for Claude-session macOS notifications: fire only on the
// three moments the user asked for (task done, input needed, a question) and
// only on a real state transition.
struct ClaudeNotificationPolicyTests {

    // MARK: - needsAttention (permission request / AskUserQuestion)

    @Test func needsAttentionFromBusyNotifies() {
        #expect(ClaudeNotificationPolicy.trigger(old: .busy, new: .needsAttention, hasBackgroundWork: false) == .needsAttention)
    }

    @Test func needsAttentionFromIdleNotifies() {
        #expect(ClaudeNotificationPolicy.trigger(old: .idle, new: .needsAttention, hasBackgroundWork: false) == .needsAttention)
    }

    @Test func firstEverStateNeedsAttentionNotifies() {
        // old == nil (no prior state) still counts as a transition.
        #expect(ClaudeNotificationPolicy.trigger(old: nil, new: .needsAttention, hasBackgroundWork: false) == .needsAttention)
    }

    @Test func needsAttentionFiresEvenWithBackgroundWork() {
        // Background work only gates "done"; an attention request is always urgent.
        #expect(ClaudeNotificationPolicy.trigger(old: .busy, new: .needsAttention, hasBackgroundWork: true) == .needsAttention)
    }

    // MARK: - done (turn finished, waiting)

    @Test func idleWithoutBackgroundWorkIsDone() {
        #expect(ClaudeNotificationPolicy.trigger(old: .busy, new: .idle, hasBackgroundWork: false) == .done)
    }

    @Test func idleWithBackgroundWorkIsSuppressed() {
        // The "false idle during background work" case — a subagent is still running.
        #expect(ClaudeNotificationPolicy.trigger(old: .busy, new: .idle, hasBackgroundWork: true) == nil)
    }

    @Test func idleFromActiveIsDone() {
        #expect(ClaudeNotificationPolicy.trigger(old: .active, new: .idle, hasBackgroundWork: false) == .done)
    }

    @Test func firstEverIdleIsNotDone() {
        #expect(ClaudeNotificationPolicy.trigger(old: nil, new: .idle, hasBackgroundWork: false) == nil)
    }

    // MARK: - transition-only

    @Test func sameStateNeverRefires() {
        // e.g. Notification.idle_prompt after Stop already set idle.
        #expect(ClaudeNotificationPolicy.trigger(old: .idle, new: .idle, hasBackgroundWork: false) == nil)
        #expect(ClaudeNotificationPolicy.trigger(old: .needsAttention, new: .needsAttention, hasBackgroundWork: false) == nil)
    }

    // MARK: - non-notifying targets

    @Test func progressAndTeardownStatesDoNotNotify() {
        #expect(ClaudeNotificationPolicy.trigger(old: .idle, new: .busy, hasBackgroundWork: false) == nil)
        #expect(ClaudeNotificationPolicy.trigger(old: .busy, new: .active, hasBackgroundWork: false) == nil)
        #expect(ClaudeNotificationPolicy.trigger(old: .busy, new: .failed, hasBackgroundWork: false) == nil)
        #expect(ClaudeNotificationPolicy.trigger(old: .idle, new: .inactive, hasBackgroundWork: false) == nil)
    }

    // MARK: - canReplace interplay (as seen by the caller)

    @Test func suppressedWriteReadsAsNoTransition() {
        // ClaudeSessionState.idle cannot replace needsAttention, so the caller
        // reads new == old == needsAttention and must not emit a "done".
        #expect(ClaudeSessionState.idle.canReplace(.needsAttention) == false)
        #expect(ClaudeNotificationPolicy.trigger(old: .needsAttention, new: .needsAttention, hasBackgroundWork: false) == nil)
    }
}
