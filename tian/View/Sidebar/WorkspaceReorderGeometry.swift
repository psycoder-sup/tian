import CoreGraphics

/// Pure geometry for the sidebar workspace reorder drag: mapping a pointer/row
/// position to an insertion slot, and the shuffle offset that opens the gap.
/// Lives beside the view that uses it; the model owns only slot→index math.
enum WorkspaceReorderGeometry {
    /// The insertion slot (0...count) for a drag whose pointer is at `y`, given each
    /// row's vertical midpoint in display order. A row whose midpoint is above `y`
    /// means the drop goes below it; the slot is the count of such rows.
    static func insertionSlot(forY y: CGFloat, rowMidYs: [CGFloat]) -> Int {
        rowMidYs.filter { $0 < y }.count
    }

    /// The vertical offset a NON-dragged row at `index` takes to open a gap for a row
    /// being dragged from `source` to insertion `slot` (0...count), given the dragged
    /// row's `draggedHeight`. Rows between the vacated slot and the target shift by
    /// ±draggedHeight; all others stay. Returns 0 for the no-op zone (slot == source
    /// or slot == source+1).
    static func reorderShuffleOffset(index: Int, source: Int, slot: Int, draggedHeight: CGFloat) -> CGFloat {
        if slot > source {
            return (index > source && index < slot) ? -draggedHeight : 0   // dragging down: intervening rows move up
        } else {
            return (index >= slot && index < source) ? draggedHeight : 0     // dragging up: intervening rows move down
        }
    }
}
