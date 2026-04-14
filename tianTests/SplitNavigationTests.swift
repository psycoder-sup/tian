import Testing
import Foundation
import CoreGraphics
@testable import tian

struct SplitNavigationTests {
    // MARK: - Helpers

    private let paneA = UUID()
    private let paneB = UUID()
    private let paneC = UUID()
    private let paneD = UUID()

    // MARK: - Single Pane

    @Test func singlePaneReturnsNil() {
        let frames: [UUID: CGRect] = [paneA: CGRect(x: 0, y: 0, width: 800, height: 600)]
        for direction in [NavigationDirection.left, .right, .up, .down] {
            #expect(SplitNavigation.neighbor(of: paneA, direction: direction, in: frames) == nil)
        }
    }

    // MARK: - Unknown Focused Pane

    @Test func unknownFocusedPaneReturnsNil() {
        let unknown = UUID()
        let frames: [UUID: CGRect] = [paneA: CGRect(x: 0, y: 0, width: 400, height: 600)]
        #expect(SplitNavigation.neighbor(of: unknown, direction: .right, in: frames) == nil)
    }

    // MARK: - Two Panes Horizontal (A | B)

    @Test func horizontalSplitNavigateRight() {
        // A on left, B on right, 4pt divider between
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 398, height: 600),
            paneB: CGRect(x: 402, y: 0, width: 398, height: 600),
        ]
        #expect(SplitNavigation.neighbor(of: paneA, direction: .right, in: frames) == paneB)
    }

    @Test func horizontalSplitNavigateLeft() {
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 398, height: 600),
            paneB: CGRect(x: 402, y: 0, width: 398, height: 600),
        ]
        #expect(SplitNavigation.neighbor(of: paneB, direction: .left, in: frames) == paneA)
    }

    @Test func horizontalSplitNoNeighborBeyondEdge() {
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 398, height: 600),
            paneB: CGRect(x: 402, y: 0, width: 398, height: 600),
        ]
        #expect(SplitNavigation.neighbor(of: paneA, direction: .left, in: frames) == nil)
        #expect(SplitNavigation.neighbor(of: paneB, direction: .right, in: frames) == nil)
    }

    // MARK: - Two Panes Vertical (A / B)

    @Test func verticalSplitNavigateDown() {
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 800, height: 298),
            paneB: CGRect(x: 0, y: 302, width: 800, height: 298),
        ]
        #expect(SplitNavigation.neighbor(of: paneA, direction: .down, in: frames) == paneB)
    }

    @Test func verticalSplitNavigateUp() {
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 800, height: 298),
            paneB: CGRect(x: 0, y: 302, width: 800, height: 298),
        ]
        #expect(SplitNavigation.neighbor(of: paneB, direction: .up, in: frames) == paneA)
    }

    // MARK: - Perpendicular Direction Returns Nil

    @Test func horizontalSplitPerpendicularReturnsNil() {
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 398, height: 600),
            paneB: CGRect(x: 402, y: 0, width: 398, height: 600),
        ]
        #expect(SplitNavigation.neighbor(of: paneA, direction: .up, in: frames) == nil)
        #expect(SplitNavigation.neighbor(of: paneA, direction: .down, in: frames) == nil)
    }

    // MARK: - Three Panes: A | (B / C)

    @Test func threePanesNavigateFromLeftToRight() {
        // A is full height on left, B on top-right, C on bottom-right
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 398, height: 600),
            paneB: CGRect(x: 402, y: 0, width: 398, height: 298),
            paneC: CGRect(x: 402, y: 302, width: 398, height: 298),
        ]
        // From A, navigating right should pick B (closer to A's center since B is at top)
        let result = SplitNavigation.neighbor(of: paneA, direction: .right, in: frames)
        #expect(result == paneB || result == paneC)
    }

    @Test func threePanesNavigateVerticallyOnRight() {
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 398, height: 600),
            paneB: CGRect(x: 402, y: 0, width: 398, height: 298),
            paneC: CGRect(x: 402, y: 302, width: 398, height: 298),
        ]
        #expect(SplitNavigation.neighbor(of: paneB, direction: .down, in: frames) == paneC)
        #expect(SplitNavigation.neighbor(of: paneC, direction: .up, in: frames) == paneB)
    }

    @Test func threePanesNavigateLeftFromRight() {
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 398, height: 600),
            paneB: CGRect(x: 402, y: 0, width: 398, height: 298),
            paneC: CGRect(x: 402, y: 302, width: 398, height: 298),
        ]
        #expect(SplitNavigation.neighbor(of: paneB, direction: .left, in: frames) == paneA)
        #expect(SplitNavigation.neighbor(of: paneC, direction: .left, in: frames) == paneA)
    }

    // MARK: - Four Panes Grid: (A | B) / (C | D)

    @Test func fourPaneGridNavigation() {
        let frames: [UUID: CGRect] = [
            paneA: CGRect(x: 0, y: 0, width: 398, height: 298),
            paneB: CGRect(x: 402, y: 0, width: 398, height: 298),
            paneC: CGRect(x: 0, y: 302, width: 398, height: 298),
            paneD: CGRect(x: 402, y: 302, width: 398, height: 298),
        ]
        // A: right→B, down→C
        #expect(SplitNavigation.neighbor(of: paneA, direction: .right, in: frames) == paneB)
        #expect(SplitNavigation.neighbor(of: paneA, direction: .down, in: frames) == paneC)
        #expect(SplitNavigation.neighbor(of: paneA, direction: .left, in: frames) == nil)
        #expect(SplitNavigation.neighbor(of: paneA, direction: .up, in: frames) == nil)

        // B: left→A, down→D
        #expect(SplitNavigation.neighbor(of: paneB, direction: .left, in: frames) == paneA)
        #expect(SplitNavigation.neighbor(of: paneB, direction: .down, in: frames) == paneD)

        // C: right→D, up→A
        #expect(SplitNavigation.neighbor(of: paneC, direction: .right, in: frames) == paneD)
        #expect(SplitNavigation.neighbor(of: paneC, direction: .up, in: frames) == paneA)

        // D: left→C, up→B
        #expect(SplitNavigation.neighbor(of: paneD, direction: .left, in: frames) == paneC)
        #expect(SplitNavigation.neighbor(of: paneD, direction: .up, in: frames) == paneB)
    }

    // MARK: - Integration with SplitLayout

    @Test func integrationWithSplitLayout() {
        // Build a real tree: horizontal split (A | B)
        let tree = PaneNode.split(
            id: UUID(),
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(paneID: paneA, workingDirectory: "~"),
            second: .leaf(paneID: paneB, workingDirectory: "~")
        )
        let result = SplitLayout.layout(node: tree, in: CGRect(x: 0, y: 0, width: 800, height: 600))

        #expect(SplitNavigation.neighbor(of: paneA, direction: .right, in: result.paneFrames) == paneB)
        #expect(SplitNavigation.neighbor(of: paneB, direction: .left, in: result.paneFrames) == paneA)
        #expect(SplitNavigation.neighbor(of: paneA, direction: .left, in: result.paneFrames) == nil)
    }

    @Test func integrationWithNestedSplitLayout() {
        // Tree: A | (B / C)
        let tree = PaneNode.split(
            id: UUID(),
            direction: .horizontal,
            ratio: 0.5,
            first: .leaf(paneID: paneA, workingDirectory: "~"),
            second: .split(
                id: UUID(),
                direction: .vertical,
                ratio: 0.5,
                first: .leaf(paneID: paneB, workingDirectory: "~"),
                second: .leaf(paneID: paneC, workingDirectory: "~")
            )
        )
        let result = SplitLayout.layout(node: tree, in: CGRect(x: 0, y: 0, width: 800, height: 600))

        // B and C are vertically stacked on the right
        #expect(SplitNavigation.neighbor(of: paneB, direction: .down, in: result.paneFrames) == paneC)
        #expect(SplitNavigation.neighbor(of: paneC, direction: .up, in: result.paneFrames) == paneB)
        #expect(SplitNavigation.neighbor(of: paneB, direction: .left, in: result.paneFrames) == paneA)
        #expect(SplitNavigation.neighbor(of: paneC, direction: .left, in: result.paneFrames) == paneA)
    }
}
