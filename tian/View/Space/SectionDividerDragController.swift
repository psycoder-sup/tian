import Foundation
import Observation

/// Coordinates live divider-drag state and FR-15 mid-drag dock-toggle queueing.
///
/// Lives on `SpaceModel` so both `SectionDividerView` and the
/// `SectionToolbarView` dock-toggle buttons route through the same
/// controller. During an active drag:
///
/// * `SpaceModel.setDockPosition` enqueues rather than applies (FR-15).
/// * Toolbar buttons visually disable themselves.
/// * On gesture end, the queued position (if any) is surfaced via
///   `onDragEnd` so the owning `SpaceModel` can apply it without creating
///   a back-reference cycle.
@MainActor @Observable
final class SectionDividerDragController {
    private(set) var isDragging: Bool = false
    private(set) var queuedDockPosition: DockPosition?

    /// Fires once per `endDrag(finalRatio:)` call. Payload is the queued
    /// dock position (or nil) that the owner should apply after the drag.
    /// Wired by `SpaceModel` init.
    var onDragEnd: ((DockPosition?) -> Void)?

    init() {}

    func beginDrag() {
        isDragging = true
    }

    func endDrag(finalRatio: Double) {
        _ = finalRatio  // reserved for future analytics; ratio commit happens on SpaceModel
        isDragging = false
        let queued = consumeQueuedDockPosition()
        onDragEnd?(queued)
    }

    /// Stores a mid-drag dock toggle to be applied on drag end (FR-15).
    func enqueueDockPosition(_ position: DockPosition) {
        queuedDockPosition = position
    }

    /// Returns + clears the queued dock position (if any). Called from
    /// `endDrag` and exposed for direct consumption in tests.
    @discardableResult
    func consumeQueuedDockPosition() -> DockPosition? {
        let queued = queuedDockPosition
        queuedDockPosition = nil
        return queued
    }
}
