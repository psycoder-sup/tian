import Testing
@testable import tian

struct ClaudeSessionStateTests {

    // MARK: - Raw Value Init

    @Test func initFromValidRawValues() {
        #expect(ClaudeSessionState(rawValue: "needs_attention") == .needsAttention)
        #expect(ClaudeSessionState(rawValue: "failed") == .failed)
        #expect(ClaudeSessionState(rawValue: "busy") == .busy)
        #expect(ClaudeSessionState(rawValue: "active") == .active)
        #expect(ClaudeSessionState(rawValue: "idle") == .idle)
        #expect(ClaudeSessionState(rawValue: "inactive") == .inactive)
    }

    @Test func initFromInvalidRawValueReturnsNil() {
        #expect(ClaudeSessionState(rawValue: "unknown") == nil)
        #expect(ClaudeSessionState(rawValue: "") == nil)
        #expect(ClaudeSessionState(rawValue: "BUSY") == nil)
    }

    // MARK: - Comparable Priority

    @Test func needsAttentionIsHighestPriority() {
        #expect(ClaudeSessionState.needsAttention > .busy)
        #expect(ClaudeSessionState.needsAttention > .active)
        #expect(ClaudeSessionState.needsAttention > .idle)
        #expect(ClaudeSessionState.needsAttention > .inactive)
    }

    @Test func failedIsSecondHighest() {
        #expect(ClaudeSessionState.failed < .needsAttention)
        #expect(ClaudeSessionState.failed > .busy)
        #expect(ClaudeSessionState.failed > .active)
        #expect(ClaudeSessionState.failed > .idle)
        #expect(ClaudeSessionState.failed > .inactive)
    }

    @Test func busyIsThirdHighest() {
        #expect(ClaudeSessionState.busy > .active)
        #expect(ClaudeSessionState.busy > .idle)
        #expect(ClaudeSessionState.busy > .inactive)
        #expect(ClaudeSessionState.busy < .failed)
        #expect(ClaudeSessionState.busy < .needsAttention)
    }

    @Test func inactiveIsLowestPriority() {
        #expect(ClaudeSessionState.inactive < .idle)
        #expect(ClaudeSessionState.inactive < .active)
        #expect(ClaudeSessionState.inactive < .busy)
        #expect(ClaudeSessionState.inactive < .needsAttention)
    }

    @Test func equalStatesAreNotLessThan() {
        #expect(!(ClaudeSessionState.busy < .busy))
        #expect(!(ClaudeSessionState.busy > .busy))
    }

    @Test func sortedPutsLowestPriorityFirst() {
        let states: [ClaudeSessionState] = [.idle, .needsAttention, .inactive, .busy, .active, .failed]
        let sorted = states.sorted()
        #expect(sorted == [.inactive, .idle, .active, .busy, .failed, .needsAttention])
    }

    @Test func maxReturnsHighestPriority() {
        let states: [ClaudeSessionState] = [.idle, .busy, .active]
        #expect(states.max() == .busy)
    }

    @Test func maxPrefersFailedOverBusy() {
        let states: [ClaudeSessionState] = [.idle, .busy, .failed, .active]
        #expect(states.max() == .failed)
    }

    // MARK: - canReplace transition guard

    @Test func idleDoesNotReplaceNeedsAttentionOrFailed() {
        #expect(ClaudeSessionState.idle.canReplace(.needsAttention) == false)
        #expect(ClaudeSessionState.idle.canReplace(.failed) == false)
    }

    @Test func idleReplacesActivityAndNil() {
        #expect(ClaudeSessionState.idle.canReplace(nil))
        #expect(ClaudeSessionState.idle.canReplace(.busy))
        #expect(ClaudeSessionState.idle.canReplace(.active))
        #expect(ClaudeSessionState.idle.canReplace(.idle))
    }

    @Test func busyAndFailedAndInactiveAlwaysReplace() {
        // Activity resumed, a failure, or session end all clear a pending prompt.
        #expect(ClaudeSessionState.busy.canReplace(.needsAttention))
        #expect(ClaudeSessionState.failed.canReplace(.needsAttention))
        #expect(ClaudeSessionState.inactive.canReplace(.needsAttention))
        // A later failure overrides a prior failure; a clean inactive overrides it too.
        #expect(ClaudeSessionState.inactive.canReplace(.failed))
    }

    // MARK: - CaseIterable

    @Test func allCasesContainsSixCases() {
        #expect(ClaudeSessionState.allCases.count == 6)
    }
}
