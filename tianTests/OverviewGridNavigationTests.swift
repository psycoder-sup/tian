import Foundation
import Testing
@testable import tian

/// Arrow-key navigation across the overview's stacked per-workspace grids.
///
/// Regression coverage for the flat-global-columnCount bug: Up/Down was
/// computed as `index ± columnCount` over a single flat concatenation of every
/// workspace's cards, so in a layout like `tian:[c1][c2]`, `.claude:[c3]`,
/// `ax-monorepo:[c4]` wide enough for 3 columns, Up/Down only toggled c1 ↔ c4
/// (`0 ± 3`) and c3 was unreachable except via Left/Right.
/// `OverviewGridNavigation` is pure, so these drive it directly with synthetic
/// id layouts.
struct OverviewGridNavigationTests {
    // Stable ids so failures read positionally.
    private let c1 = UUID(), c2 = UUID(), c3 = UUID(), c4 = UUID()

    /// The reported layout: `tian:[c1][c2]`, `.claude:[c3]`, `ax-monorepo:[c4]`.
    private var reportedSections: [[UUID]] { [[c1, c2], [c3], [c4]] }

    @Test func downCrossesSectionBoundaries() {
        #expect(OverviewGridNavigation.move(.down, from: c1, sections: reportedSections, columnCount: 3) == c3)
        #expect(OverviewGridNavigation.move(.down, from: c3, sections: reportedSections, columnCount: 3) == c4)
    }

    @Test func upCrossesSectionBoundaries() {
        #expect(OverviewGridNavigation.move(.up, from: c4, sections: reportedSections, columnCount: 3) == c3)
        #expect(OverviewGridNavigation.move(.up, from: c3, sections: reportedSections, columnCount: 3) == c1)
    }

    @Test func downFromSecondColumnClampsOntoShortRow() {
        // c2 is top-right; the row below (.claude) holds a single card, so Down
        // clamps the column onto c3 rather than skipping past it.
        #expect(OverviewGridNavigation.move(.down, from: c2, sections: reportedSections, columnCount: 3) == c3)
    }

    @Test func leftRightWalkReadingOrder() {
        #expect(OverviewGridNavigation.move(.right, from: c2, sections: reportedSections, columnCount: 3) == c3)
        #expect(OverviewGridNavigation.move(.left, from: c4, sections: reportedSections, columnCount: 3) == c3)
        #expect(OverviewGridNavigation.move(.right, from: c1, sections: reportedSections, columnCount: 3) == c2)
    }

    @Test func downFromTopReachesEachStackedRow() {
        // The core regression: stepping Down from the top lands on the first
        // card of every visual row — the rows the old flat model skipped over.
        var id = c1
        var visited = [id]
        for _ in 0..<3 {
            id = OverviewGridNavigation.move(.down, from: id, sections: reportedSections, columnCount: 3)!
            visited.append(id)
        }
        #expect(visited == [c1, c3, c4, c4])   // c1 → c3 → c4 → (clamp) c4
    }

    @Test func fixIsIndependentOfColumnCount() {
        // Same visual outcome at 2 columns — the bug was the flat model, not the
        // specific count.
        #expect(OverviewGridNavigation.move(.down, from: c1, sections: reportedSections, columnCount: 2) == c3)
    }

    @Test func multipleRowsWithinAWorkspace() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), e = UUID(), f = UUID()
        let sections = [[a, b, c, d, e], [f]]   // a 5-card workspace, then a 1-card one
        // rows at cols=2: [a,b] [c,d] [e] [f]
        #expect(OverviewGridNavigation.move(.down, from: a, sections: sections, columnCount: 2) == c)
        #expect(OverviewGridNavigation.move(.down, from: b, sections: sections, columnCount: 2) == d)
        #expect(OverviewGridNavigation.move(.down, from: d, sections: sections, columnCount: 2) == e) // clamp column
        #expect(OverviewGridNavigation.move(.down, from: e, sections: sections, columnCount: 2) == f) // cross section
        #expect(OverviewGridNavigation.move(.up, from: e, sections: sections, columnCount: 2) == c)
    }

    @Test func clampsAtEdges() {
        #expect(OverviewGridNavigation.move(.up, from: c1, sections: reportedSections, columnCount: 3) == c1)
        #expect(OverviewGridNavigation.move(.left, from: c1, sections: reportedSections, columnCount: 3) == c1)
        #expect(OverviewGridNavigation.move(.down, from: c4, sections: reportedSections, columnCount: 3) == c4)
        #expect(OverviewGridNavigation.move(.right, from: c4, sections: reportedSections, columnCount: 3) == c4)
    }

    @Test func missingOrStaleSelectionStartsAtFirstCard() {
        #expect(OverviewGridNavigation.move(.down, from: nil, sections: reportedSections, columnCount: 3) == c3)
        #expect(OverviewGridNavigation.move(.right, from: nil, sections: reportedSections, columnCount: 3) == c2)
        // An id no longer present is treated the same as a missing selection.
        #expect(OverviewGridNavigation.move(.right, from: UUID(), sections: reportedSections, columnCount: 3) == c2)
    }

    @Test func noCardsReturnsNil() {
        #expect(OverviewGridNavigation.move(.down, from: nil, sections: [], columnCount: 3) == nil)
        #expect(OverviewGridNavigation.move(.down, from: nil, sections: [[]], columnCount: 3) == nil)
    }

    @Test func emptyWorkspaceSectionsAreSkipped() {
        // A workspace with no sessions contributes no visual row.
        let sections = [[c1], [], [c2]]
        #expect(OverviewGridNavigation.move(.down, from: c1, sections: sections, columnCount: 3) == c2)
        #expect(OverviewGridNavigation.move(.up, from: c2, sections: sections, columnCount: 3) == c1)
    }

    // MARK: - selectionAfterRemoval

    @Test func removingMiddleCardSelectsTheCardThatTookItsSlot() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        // b (index 1) is deleted; c slides into slot 1.
        #expect(
            OverviewGridNavigation.selectionAfterRemoval(
                previous: b, oldIDs: [a, b, c, d], newIDs: [a, c, d]
            ) == c
        )
    }

    @Test func removingLastCardClampsToTheNewLast() {
        let a = UUID(), b = UUID(), c = UUID()
        // c (index 2) is deleted; the new list only has indices 0-1, so clamp.
        #expect(
            OverviewGridNavigation.selectionAfterRemoval(
                previous: c, oldIDs: [a, b, c], newIDs: [a, b]
            ) == b
        )
    }

    @Test func removingFirstCardSelectsTheNewFirst() {
        let a = UUID(), b = UUID(), c = UUID()
        // a (index 0) is deleted; b slides into slot 0.
        #expect(
            OverviewGridNavigation.selectionAfterRemoval(
                previous: a, oldIDs: [a, b, c], newIDs: [b, c]
            ) == b
        )
    }

    @Test func removingTheOnlyRemainingCardReturnsNil() {
        let a = UUID()
        #expect(
            OverviewGridNavigation.selectionAfterRemoval(
                previous: a, oldIDs: [a], newIDs: []
            ) == nil
        )
    }

    @Test func missingOrUnresolvablePreviousFallsBackToFirst() {
        let a = UUID(), b = UUID(), c = UUID()
        // No previous selection at all.
        #expect(
            OverviewGridNavigation.selectionAfterRemoval(
                previous: nil, oldIDs: [a, b, c], newIDs: [b, c]
            ) == b
        )
        // Previous id isn't found in oldIDs (stale/unknown selection).
        #expect(
            OverviewGridNavigation.selectionAfterRemoval(
                previous: UUID(), oldIDs: [a, b, c], newIDs: [b, c]
            ) == b
        )
    }
}
