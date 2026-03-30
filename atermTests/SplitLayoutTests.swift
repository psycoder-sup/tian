import Testing
import Foundation
@testable import aterm

struct SplitLayoutTests {
    // MARK: - Helpers

    /// Check that two CGRects are approximately equal (floating-point tolerance).
    private func expectApproxEqual(
        _ a: CGRect, _ b: CGRect,
        tolerance: CGFloat = 0.001,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(a.origin.x - b.origin.x) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(a.origin.y - b.origin.y) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(a.size.width - b.size.width) < tolerance, sourceLocation: sourceLocation)
        #expect(abs(a.size.height - b.size.height) < tolerance, sourceLocation: sourceLocation)
    }

    // MARK: - Single Pane Layout

    @Test func singlePaneGetsFullRect() {
        let id = UUID()
        let node = PaneNode.leaf(paneID: id, workingDirectory: "")
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)

        let result = SplitLayout.layout(node: node, in: rect)

        #expect(result.paneFrames.count == 1)
        #expect(result.dividers.isEmpty)
        expectApproxEqual(result.paneFrames[id]!, rect)
    }

    // MARK: - Horizontal Split Layout

    @Test func horizontalSplitEqualRatio() {
        let a = UUID()
        let b = UUID()
        let splitID = UUID()
        let node = PaneNode.split(
            id: splitID, direction: .horizontal, ratio: 0.5,
            first: .leaf(paneID: a, workingDirectory: ""),
            second: .leaf(paneID: b, workingDirectory: "")
        )
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)

        let result = SplitLayout.layout(node: node, in: rect)

        // 800 - 4 (divider) = 796, split equally = 398 each
        #expect(result.paneFrames.count == 2)
        expectApproxEqual(result.paneFrames[a]!, CGRect(x: 0, y: 0, width: 398, height: 600))
        expectApproxEqual(result.paneFrames[b]!, CGRect(x: 402, y: 0, width: 398, height: 600))
    }

    @Test func horizontalSplitUnequalRatio() {
        let a = UUID()
        let b = UUID()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal, ratio: 0.3,
            first: .leaf(paneID: a, workingDirectory: ""),
            second: .leaf(paneID: b, workingDirectory: "")
        )
        let rect = CGRect(x: 0, y: 0, width: 1004, height: 600)

        let result = SplitLayout.layout(node: node, in: rect)

        // 1004 - 4 = 1000, first = 300, second = 700
        expectApproxEqual(result.paneFrames[a]!, CGRect(x: 0, y: 0, width: 300, height: 600))
        expectApproxEqual(result.paneFrames[b]!, CGRect(x: 304, y: 0, width: 700, height: 600))
    }

    // MARK: - Vertical Split Layout

    @Test func verticalSplitEqualRatio() {
        let a = UUID()
        let b = UUID()
        let node = PaneNode.split(
            id: UUID(), direction: .vertical, ratio: 0.5,
            first: .leaf(paneID: a, workingDirectory: ""),
            second: .leaf(paneID: b, workingDirectory: "")
        )
        let rect = CGRect(x: 0, y: 0, width: 800, height: 604)

        let result = SplitLayout.layout(node: node, in: rect)

        // 604 - 4 = 600, split equally = 300 each
        expectApproxEqual(result.paneFrames[a]!, CGRect(x: 0, y: 0, width: 800, height: 300))
        expectApproxEqual(result.paneFrames[b]!, CGRect(x: 0, y: 304, width: 800, height: 300))
    }

    @Test func verticalSplitUnequalRatio() {
        let a = UUID()
        let b = UUID()
        let node = PaneNode.split(
            id: UUID(), direction: .vertical, ratio: 0.75,
            first: .leaf(paneID: a, workingDirectory: ""),
            second: .leaf(paneID: b, workingDirectory: "")
        )
        let rect = CGRect(x: 0, y: 0, width: 800, height: 804)

        let result = SplitLayout.layout(node: node, in: rect)

        // 804 - 4 = 800, first = 600, second = 200
        expectApproxEqual(result.paneFrames[a]!, CGRect(x: 0, y: 0, width: 800, height: 600))
        expectApproxEqual(result.paneFrames[b]!, CGRect(x: 0, y: 604, width: 800, height: 200))
    }

    // MARK: - Divider Rects

    @Test func horizontalSplitDividerRect() {
        let splitID = UUID()
        let node = PaneNode.split(
            id: splitID, direction: .horizontal, ratio: 0.5,
            first: .leaf(paneID: UUID(), workingDirectory: ""),
            second: .leaf(paneID: UUID(), workingDirectory: "")
        )
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)

        let result = SplitLayout.layout(node: node, in: rect)

        #expect(result.dividers.count == 1)
        let divider = result.dividers[0]
        #expect(divider.splitID == splitID)
        #expect(divider.direction == .horizontal)
        expectApproxEqual(divider.rect, CGRect(x: 398, y: 0, width: 4, height: 600))
    }

    @Test func verticalSplitDividerRect() {
        let splitID = UUID()
        let node = PaneNode.split(
            id: splitID, direction: .vertical, ratio: 0.5,
            first: .leaf(paneID: UUID(), workingDirectory: ""),
            second: .leaf(paneID: UUID(), workingDirectory: "")
        )
        let rect = CGRect(x: 0, y: 0, width: 800, height: 604)

        let result = SplitLayout.layout(node: node, in: rect)

        #expect(result.dividers.count == 1)
        let divider = result.dividers[0]
        #expect(divider.splitID == splitID)
        #expect(divider.direction == .vertical)
        expectApproxEqual(divider.rect, CGRect(x: 0, y: 300, width: 800, height: 4))
    }

    @Test func dividerThicknessIs4Points() {
        #expect(SplitLayout.dividerThickness == 4.0)
    }

    // MARK: - Nested Layout

    @Test func nestedSplitsLayout() {
        // Layout: a | (b / c)
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let innerSplitID = UUID()
        let outerSplitID = UUID()

        let node = PaneNode.split(
            id: outerSplitID, direction: .horizontal, ratio: 0.5,
            first: .leaf(paneID: a, workingDirectory: ""),
            second: .split(
                id: innerSplitID, direction: .vertical, ratio: 0.5,
                first: .leaf(paneID: b, workingDirectory: ""),
                second: .leaf(paneID: c, workingDirectory: "")
            )
        )
        let rect = CGRect(x: 0, y: 0, width: 800, height: 604)

        let result = SplitLayout.layout(node: node, in: rect)

        #expect(result.paneFrames.count == 3)
        #expect(result.dividers.count == 2)

        // Outer: 800 - 4 = 796, each side = 398
        // a gets full left side
        expectApproxEqual(result.paneFrames[a]!, CGRect(x: 0, y: 0, width: 398, height: 604))

        // Inner: right side is (402, 0, 398, 604)
        // 604 - 4 = 600, each half = 300
        expectApproxEqual(result.paneFrames[b]!, CGRect(x: 402, y: 0, width: 398, height: 300))
        expectApproxEqual(result.paneFrames[c]!, CGRect(x: 402, y: 304, width: 398, height: 300))
    }

    @Test func deepNestedLayout() {
        // 4 panes: ((a | b) / (c | d))
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()

        let node = PaneNode.split(
            id: UUID(), direction: .vertical, ratio: 0.5,
            first: .split(
                id: UUID(), direction: .horizontal, ratio: 0.5,
                first: .leaf(paneID: a, workingDirectory: ""),
                second: .leaf(paneID: b, workingDirectory: "")
            ),
            second: .split(
                id: UUID(), direction: .horizontal, ratio: 0.5,
                first: .leaf(paneID: c, workingDirectory: ""),
                second: .leaf(paneID: d, workingDirectory: "")
            )
        )
        let rect = CGRect(x: 0, y: 0, width: 800, height: 604)

        let result = SplitLayout.layout(node: node, in: rect)

        #expect(result.paneFrames.count == 4)
        #expect(result.dividers.count == 3)
    }

    // MARK: - Edge Cases

    @Test func verySmallRectLayout() {
        let a = UUID()
        let b = UUID()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal, ratio: 0.5,
            first: .leaf(paneID: a, workingDirectory: ""),
            second: .leaf(paneID: b, workingDirectory: "")
        )
        // Rect smaller than divider thickness
        let rect = CGRect(x: 0, y: 0, width: 2, height: 100)

        let result = SplitLayout.layout(node: node, in: rect)

        // Should not crash; pane widths will be 0
        #expect(result.paneFrames.count == 2)
        #expect(result.paneFrames[a]!.width >= 0)
        #expect(result.paneFrames[b]!.width >= 0)
    }

    @Test func zeroSizeRectLayout() {
        let id = UUID()
        let node = PaneNode.leaf(paneID: id, workingDirectory: "")
        let rect = CGRect.zero

        let result = SplitLayout.layout(node: node, in: rect)
        #expect(result.paneFrames[id] == CGRect.zero)
    }

    @Test func paneFramesSumToTotalRect() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal, ratio: 0.5,
            first: .leaf(paneID: a, workingDirectory: ""),
            second: .split(
                id: UUID(), direction: .vertical, ratio: 0.5,
                first: .leaf(paneID: b, workingDirectory: ""),
                second: .leaf(paneID: c, workingDirectory: "")
            )
        )
        let containerRect = CGRect(x: 0, y: 0, width: 800, height: 604)

        let result = SplitLayout.layout(node: node, in: containerRect)

        // Total area of pane frames + dividers should equal container area
        let paneArea = result.paneFrames.values.reduce(0.0) { $0 + $1.width * $1.height }
        let dividerArea = result.dividers.reduce(0.0) { $0 + $1.rect.width * $1.rect.height }
        let totalArea = containerRect.width * containerRect.height

        #expect(abs(paneArea + dividerArea - totalArea) < 0.01)
    }

    @Test func nonOriginRectLayout() {
        let a = UUID()
        let b = UUID()
        let node = PaneNode.split(
            id: UUID(), direction: .horizontal, ratio: 0.5,
            first: .leaf(paneID: a, workingDirectory: ""),
            second: .leaf(paneID: b, workingDirectory: "")
        )
        let rect = CGRect(x: 100, y: 200, width: 800, height: 600)

        let result = SplitLayout.layout(node: node, in: rect)

        // First pane should start at (100, 200)
        #expect(result.paneFrames[a]!.origin.x == 100)
        #expect(result.paneFrames[a]!.origin.y == 200)
        // Second pane should be offset by first width + divider
        #expect(result.paneFrames[b]!.origin.x > 100)
        #expect(result.paneFrames[b]!.origin.y == 200)
    }
}
