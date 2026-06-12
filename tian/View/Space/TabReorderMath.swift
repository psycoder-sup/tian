import CoreGraphics

/// Pure slot math for the live tab-reorder drag in `SectionTabBarView`.
/// Pills are equal width, so every computation works in slot units
/// (`slotWidth` = pill width + inter-pill spacing). Kept value-type and
/// SwiftUI-free so the index/offset semantics are trivially unit-testable.
enum TabReorderMath {
    /// Horizontal translation of the dragged pill, clamped so it can never
    /// leave the row: at most `sourceIndex` slots to the left and
    /// `count - 1 - sourceIndex` slots to the right.
    static func clampedTranslation(
        _ raw: CGFloat,
        sourceIndex: Int,
        count: Int,
        slotWidth: CGFloat
    ) -> CGFloat {
        guard count > 1, slotWidth > 0 else { return 0 }
        let lower = -CGFloat(sourceIndex) * slotWidth
        let upper = CGFloat(count - 1 - sourceIndex) * slotWidth
        return min(max(raw, lower), upper)
    }

    /// Slot the dragged pill would land in if released now — the nearest
    /// slot to its current visual position.
    static func proposedIndex(
        clampedTranslation: CGFloat,
        sourceIndex: Int,
        count: Int,
        slotWidth: CGFloat
    ) -> Int {
        guard count > 0 else { return sourceIndex }
        guard slotWidth > 0 else { return min(max(sourceIndex, 0), count - 1) }
        let shift = Int((clampedTranslation / slotWidth).rounded())
        return min(max(sourceIndex + shift, 0), count - 1)
    }

    /// Offset for a non-dragged pill: pills between the dragged pill's
    /// origin and its proposed slot step one slot toward the origin to
    /// make room; everything else stays put. The dragged pill itself
    /// (`index == sourceIndex`) returns 0 — its offset is the translation.
    static func siblingOffset(
        index: Int,
        sourceIndex: Int,
        proposedIndex: Int,
        slotWidth: CGFloat
    ) -> CGFloat {
        if sourceIndex < proposedIndex, index > sourceIndex, index <= proposedIndex {
            return -slotWidth
        }
        if sourceIndex > proposedIndex, index >= proposedIndex, index < sourceIndex {
            return slotWidth
        }
        return 0
    }
}
