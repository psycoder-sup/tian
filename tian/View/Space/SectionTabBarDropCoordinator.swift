import Foundation

/// FR-22 — gating helper for tab drag-and-drop. Rejects drops that cross
/// a section boundary (Claude tab dragged onto Terminal's tab bar, and
/// vice versa). Kept as a value-type helper so the decision is trivially
/// unit-testable and re-usable outside the `SectionTabBarView` drop
/// destination.
enum SectionTabBarDropCoordinator {
    /// Returns `true` iff the drop is permitted. Crossing the section
    /// divider is always rejected.
    ///
    /// - Parameters:
    ///   - sourceSectionKind: the SectionKind of the tab being dragged.
    ///   - destinationSectionKind: the SectionKind of the tab bar that
    ///     received the drop.
    ///   - tabID: the dragged tab's id, surfaced for future diagnostics
    ///     logging.
    static func canAccept(
        sourceSectionKind: SectionKind,
        destinationSectionKind: SectionKind,
        tabID: UUID
    ) -> Bool {
        _ = tabID
        return sourceSectionKind == destinationSectionKind
    }
}
