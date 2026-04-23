import Foundation
import Observation

/// Coordinates live divider-drag state and FR-15 mid-drag dock-toggle queueing.
///
/// Phase 1 provides this as a minimal stub; full drag behaviour lands in Phase 2.
@MainActor @Observable
final class SectionDividerDragController {
    private(set) var isDragging: Bool = false
    private(set) var queuedDockPosition: DockPosition?

    init() {}

    func beginDrag() {
        isDragging = true
    }

    func endDrag(finalRatio: Double) {
        isDragging = false
    }

    /// Internal helper used by `SpaceModel.setDockPosition` when a drag is
    /// in progress. FR-15 behaviour: the toggle is queued and applied on
    /// drag end.
    func enqueueDockPosition(_ position: DockPosition) {
        queuedDockPosition = position
    }
}
