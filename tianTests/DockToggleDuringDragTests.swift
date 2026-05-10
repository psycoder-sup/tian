import Testing
@testable import tian

@MainActor
struct DockToggleDuringDragTests {

    // FR-15 — Dock toggle is queued while divider drag is active.
    @Test func dockToggleMidDragIsQueuedUntilGestureEnd() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()
        #expect(space.dockPosition == .bottom)

        // Start drag.
        space.sectionDividerDragController.beginDrag()
        space.setDockPosition(.right)  // should be queued
        #expect(space.dockPosition == .bottom)  // unchanged mid-drag

        // End drag; queued toggle applies.
        space.sectionDividerDragController.endDrag(finalRatio: 0.6)
        #expect(space.dockPosition == .right)
    }
}
