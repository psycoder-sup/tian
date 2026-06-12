import Testing
import CoreGraphics
@testable import tian

/// Slot math for the live tab-reorder drag. Slot width 100 throughout;
/// translations are in points, indices into the pre-drag tab order.
struct TabReorderMathTests {

    // MARK: clampedTranslation

    @Test func clampsAtRowEnds() {
        // 4 tabs, dragging index 1: at most 1 slot left, 2 slots right.
        #expect(TabReorderMath.clampedTranslation(
            -500, sourceIndex: 1, count: 4, slotWidth: 100
        ) == -100)
        #expect(TabReorderMath.clampedTranslation(
            500, sourceIndex: 1, count: 4, slotWidth: 100
        ) == 200)
    }

    @Test func passesThroughInsideBounds() {
        #expect(TabReorderMath.clampedTranslation(
            -42, sourceIndex: 1, count: 4, slotWidth: 100
        ) == -42)
    }

    @Test func singleTabAndDegenerateSlotClampToZero() {
        #expect(TabReorderMath.clampedTranslation(
            300, sourceIndex: 0, count: 1, slotWidth: 100
        ) == 0)
        #expect(TabReorderMath.clampedTranslation(
            300, sourceIndex: 0, count: 4, slotWidth: 0
        ) == 0)
    }

    // MARK: proposedIndex

    @Test func roundsToNearestSlot() {
        // Just under half a slot stays; half a slot and beyond promotes.
        #expect(TabReorderMath.proposedIndex(
            clampedTranslation: 49, sourceIndex: 1, count: 4, slotWidth: 100
        ) == 1)
        #expect(TabReorderMath.proposedIndex(
            clampedTranslation: 50, sourceIndex: 1, count: 4, slotWidth: 100
        ) == 2)
        #expect(TabReorderMath.proposedIndex(
            clampedTranslation: -49, sourceIndex: 1, count: 4, slotWidth: 100
        ) == 1)
        #expect(TabReorderMath.proposedIndex(
            clampedTranslation: -50, sourceIndex: 1, count: 4, slotWidth: 100
        ) == 0)
    }

    @Test func proposedIndexStaysInRange() {
        // Even with an out-of-clamp translation the result is a valid index.
        #expect(TabReorderMath.proposedIndex(
            clampedTranslation: 900, sourceIndex: 1, count: 4, slotWidth: 100
        ) == 3)
        #expect(TabReorderMath.proposedIndex(
            clampedTranslation: -900, sourceIndex: 1, count: 4, slotWidth: 100
        ) == 0)
    }

    @Test func fullDragAcrossRowLandsAtFarEnd() {
        // [A,B,C,D]: A dragged 3 slots right lands at index 3 (its slot in
        // the post-reorder array — reorderTab's remove-then-insert).
        #expect(TabReorderMath.proposedIndex(
            clampedTranslation: 300, sourceIndex: 0, count: 4, slotWidth: 100
        ) == 3)
        // D dragged 3 slots left lands at index 0.
        #expect(TabReorderMath.proposedIndex(
            clampedTranslation: -300, sourceIndex: 3, count: 4, slotWidth: 100
        ) == 0)
    }

    // MARK: siblingOffset

    @Test func draggingRightShiftsCrossedSiblingsLeft() {
        // [A,B,C,D]: A proposed at 2 → B and C step left, D stays.
        let offsets = (0...3).map {
            TabReorderMath.siblingOffset(
                index: $0, sourceIndex: 0, proposedIndex: 2, slotWidth: 100
            )
        }
        #expect(offsets == [0, -100, -100, 0])
    }

    @Test func draggingLeftShiftsCrossedSiblingsRight() {
        // [A,B,C,D]: D proposed at 1 → B and C step right, A stays.
        let offsets = (0...3).map {
            TabReorderMath.siblingOffset(
                index: $0, sourceIndex: 3, proposedIndex: 1, slotWidth: 100
            )
        }
        #expect(offsets == [0, 100, 100, 0])
    }

    @Test func noShiftWhenProposedEqualsSource() {
        for index in 0...3 {
            #expect(TabReorderMath.siblingOffset(
                index: index, sourceIndex: 2, proposedIndex: 2, slotWidth: 100
            ) == 0)
        }
    }
}
