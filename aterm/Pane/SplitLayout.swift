import CoreGraphics
import Foundation

/// Information about a divider between two split children.
struct DividerInfo: Sendable {
    /// The ID of the split node that owns this divider.
    let splitID: UUID
    /// The screen-space rectangle of the divider (4pt wide hit target).
    let rect: CGRect
    /// The direction of the split this divider belongs to.
    let direction: SplitDirection
}

/// Result of computing layout from a split tree.
struct SplitLayoutResult: Sendable {
    /// Map from pane ID to its screen-space frame.
    let paneFrames: [UUID: CGRect]
    /// All divider rects for hit-testing and rendering.
    let dividers: [DividerInfo]
}

/// Layout algorithm that converts a split tree into concrete frames.
enum SplitLayout {
    /// Divider thickness in points.
    static let dividerThickness: CGFloat = 4.0

    /// Compute layout for the given tree within the available rect.
    static func layout(node: PaneNode, in rect: CGRect) -> SplitLayoutResult {
        switch node {
        case .leaf(let paneID, _):
            return SplitLayoutResult(paneFrames: [paneID: rect], dividers: [])

        case .split(let id, let direction, let ratio, let first, let second):
            let (firstRect, dividerRect, secondRect) = subdivide(
                rect: rect, direction: direction, ratio: ratio
            )

            let firstResult = layout(node: first, in: firstRect)
            let secondResult = layout(node: second, in: secondRect)

            let divider = DividerInfo(splitID: id, rect: dividerRect, direction: direction)

            return SplitLayoutResult(
                paneFrames: firstResult.paneFrames.merging(secondResult.paneFrames) { a, _ in a },
                dividers: firstResult.dividers + [divider] + secondResult.dividers
            )
        }
    }

    /// Divide a rect into three regions: first child, divider, second child.
    private static func subdivide(
        rect: CGRect,
        direction: SplitDirection,
        ratio: Double
    ) -> (first: CGRect, divider: CGRect, second: CGRect) {
        let thickness = dividerThickness

        switch direction {
        case .horizontal:
            let available = max(rect.width - thickness, 0)
            let firstWidth = available * ratio
            let secondWidth = available - firstWidth

            let firstRect = CGRect(
                x: rect.minX, y: rect.minY,
                width: firstWidth, height: rect.height
            )
            let dividerRect = CGRect(
                x: rect.minX + firstWidth, y: rect.minY,
                width: thickness, height: rect.height
            )
            let secondRect = CGRect(
                x: rect.minX + firstWidth + thickness, y: rect.minY,
                width: secondWidth, height: rect.height
            )
            return (firstRect, dividerRect, secondRect)

        case .vertical:
            let available = max(rect.height - thickness, 0)
            let firstHeight = available * ratio
            let secondHeight = available - firstHeight

            let firstRect = CGRect(
                x: rect.minX, y: rect.minY,
                width: rect.width, height: firstHeight
            )
            let dividerRect = CGRect(
                x: rect.minX, y: rect.minY + firstHeight,
                width: rect.width, height: thickness
            )
            let secondRect = CGRect(
                x: rect.minX, y: rect.minY + firstHeight + thickness,
                width: rect.width, height: secondHeight
            )
            return (firstRect, dividerRect, secondRect)
        }
    }
}
