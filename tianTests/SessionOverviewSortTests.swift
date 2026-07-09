import Foundation
import Testing
@testable import tian

/// Pure ordering coverage for `SessionOverviewSort.ordered(_:mode:state:)`.
/// No SwiftUI, no `Session` objects — a tiny local `Item` stands in for
/// whatever card type the caller sorts.
struct SessionOverviewSortTests {
    private struct Item {
        let id: Int
        let state: ClaudeSessionState?
    }

    @Test func defaultOrderIsIdentity() {
        let items = [
            Item(id: 3, state: .idle),
            Item(id: 1, state: .needsAttention),
            Item(id: 4, state: nil),
            Item(id: 2, state: .busy)
        ]
        let result = SessionOverviewSort.ordered(items, mode: .defaultOrder) { $0.state }
        #expect(result.map(\.id) == [3, 1, 4, 2])
    }

    @Test func sessionStateOrdersMostUrgentFirst() {
        let idle = Item(id: 1, state: .idle)
        let needsAttention = Item(id: 2, state: .needsAttention)
        let fresh = Item(id: 3, state: nil)
        let busy = Item(id: 4, state: .busy)
        let items = [idle, needsAttention, fresh, busy]

        let result = SessionOverviewSort.ordered(items, mode: .sessionState) { $0.state }
        #expect(result.map(\.id) == [2, 4, 1, 3])
    }

    @Test func freshNilAlwaysLandsLastEvenWhenFirstInInput() {
        let items = [
            Item(id: 1, state: nil),
            Item(id: 2, state: .idle)
        ]
        let result = SessionOverviewSort.ordered(items, mode: .sessionState) { $0.state }
        #expect(result.map(\.id) == [2, 1])
    }

    @Test func equalStatesAreStable() {
        let items = [
            Item(id: 1, state: .busy),
            Item(id: 2, state: .idle),
            Item(id: 3, state: .busy)
        ]
        let result = SessionOverviewSort.ordered(items, mode: .sessionState) { $0.state }
        // Both busy items keep their input relative order (1 before 3), idle trails.
        #expect(result.map(\.id) == [1, 3, 2])
    }

    @Test func failedSortsJustUnderNeedsAttention() {
        let items = [
            Item(id: 1, state: .failed),
            Item(id: 2, state: .needsAttention)
        ]
        let result = SessionOverviewSort.ordered(items, mode: .sessionState) { $0.state }
        #expect(result.map(\.id) == [2, 1])
    }

    @Test func activeSortsJustUnderBusyAndAboveIdle() {
        let items = [
            Item(id: 1, state: .idle),
            Item(id: 2, state: .active),
            Item(id: 3, state: .busy)
        ]
        let result = SessionOverviewSort.ordered(items, mode: .sessionState) { $0.state }
        #expect(result.map(\.id) == [3, 2, 1])
    }
}
