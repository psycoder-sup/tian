import Foundation

/// Pure, testable arrow-key navigation for the session overview grid.
///
/// The overview does **not** render one uniform grid: it stacks an independent
/// `LazyVGrid` per workspace, each flowing its own sessions into rows of
/// `columnCount`. Navigating a single flat list with a global column count
/// (`index ± columnCount`) therefore skips real cards whenever a workspace
/// holds fewer sessions than there are columns — the short section's empty
/// trailing cells get treated as if cards lived there, so Up/Down jumps over
/// the cards that are actually on screen.
///
/// This models the **visual** layout instead: each section is flowed into rows
/// of `columnCount` and the rows are stacked top-to-bottom across section
/// boundaries. Up/Down step between adjacent rows (preserving the column,
/// clamped to the destination row's width); Left/Right walk the flat render
/// order.
enum OverviewGridNavigation {
    /// One arrow-key move.
    enum Direction {
        case up, down, left, right
    }

    /// The id to select after moving `direction` from `selected`.
    ///
    /// - Parameters:
    ///   - selected: the currently selected session id. A missing id, or one no
    ///     longer present in `sections`, is treated as the first card.
    ///   - sections: each workspace's session ids in render (hierarchical)
    ///     order, in workspace order. Empty sections contribute no rows.
    ///   - columnCount: the live adaptive column count (clamped to `≥ 1`).
    /// - Returns: the next selected id, or `nil` only when there are no cards.
    static func move(
        _ direction: Direction,
        from selected: UUID?,
        sections: [[UUID]],
        columnCount: Int
    ) -> UUID? {
        let cols = max(1, columnCount)

        // Visual rows: each section flowed into rows of `cols`, stacked in order.
        var rows: [[UUID]] = []
        for section in sections {
            var start = 0
            while start < section.count {
                let end = min(start + cols, section.count)
                rows.append(Array(section[start..<end]))
                start = end
            }
        }

        let flat = rows.flatMap { $0 }
        guard !flat.isEmpty else { return nil }

        switch direction {
        case .left:
            return flatStep(flat, from: selected, by: -1)
        case .right:
            return flatStep(flat, from: selected, by: 1)
        case .up, .down:
            let (row, col) = position(of: selected, in: rows)
            let targetRow = direction == .up
                ? max(row - 1, 0)
                : min(row + 1, rows.count - 1)
            // Preserve the column, clamped to the destination row's width.
            let targetCol = min(col, rows[targetRow].count - 1)
            return rows[targetRow][targetCol]
        }
    }

    /// Reading-order neighbor `delta` steps from `selected` across the flat card
    /// order, clamped to the ends. A missing selection starts at the first card.
    private static func flatStep(_ flat: [UUID], from selected: UUID?, by delta: Int) -> UUID {
        let current = selected.flatMap { flat.firstIndex(of: $0) } ?? 0
        let next = min(max(current + delta, 0), flat.count - 1)
        return flat[next]
    }

    /// The `(row, column)` of `selected` in the stacked visual rows, defaulting
    /// to the top-left cell when the selection is missing or no longer present.
    private static func position(of selected: UUID?, in rows: [[UUID]]) -> (row: Int, col: Int) {
        guard let selected else { return (0, 0) }
        for (r, row) in rows.enumerated() {
            if let c = row.firstIndex(of: selected) {
                return (r, c)
            }
        }
        return (0, 0)
    }

    /// The card to select after the current selection's card disappeared from the
    /// list — the neighbor that slid into its slot (the same flat index in the new
    /// list, clamped to the last card), so focus lands on an *adjacent* card
    /// instead of snapping back to the first. Falls back to the first card when the
    /// previous id can't be located in `oldIDs`, and returns `nil` only when no
    /// cards remain.
    static func selectionAfterRemoval(
        previous: UUID?,
        oldIDs: [UUID],
        newIDs: [UUID]
    ) -> UUID? {
        guard !newIDs.isEmpty else { return nil }
        if let previous, let oldIndex = oldIDs.firstIndex(of: previous) {
            return newIDs[min(oldIndex, newIDs.count - 1)]
        }
        return newIDs.first
    }
}
