import Testing
@testable import aterm

struct ClaudeSessionStateTests {

    // MARK: - Raw Value Init

    @Test func initFromValidRawValues() {
        #expect(ClaudeSessionState(rawValue: "needs_attention") == .needsAttention)
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

    @Test func busyIsSecondHighest() {
        #expect(ClaudeSessionState.busy > .active)
        #expect(ClaudeSessionState.busy > .idle)
        #expect(ClaudeSessionState.busy > .inactive)
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
        let states: [ClaudeSessionState] = [.idle, .needsAttention, .inactive, .busy, .active]
        let sorted = states.sorted()
        #expect(sorted == [.inactive, .idle, .active, .busy, .needsAttention])
    }

    @Test func maxReturnsHighestPriority() {
        let states: [ClaudeSessionState] = [.idle, .busy, .active]
        #expect(states.max() == .busy)
    }

    // MARK: - CaseIterable

    @Test func allCasesContainsFiveCases() {
        #expect(ClaudeSessionState.allCases.count == 5)
    }
}
