import Testing
@testable import tian

@MainActor
struct DockToggleDuringDragTests {

    // FR-15 — Dock toggle is queued while divider drag is active.
    @Test func dockToggleMidDragIsQueuedUntilGestureEnd() {
        let session = SessionCollection(workingDirectory: "/tmp").activeSession!
        session.showTerminal()
        #expect(session.dockPosition == .bottom)

        // Start drag.
        session.dividerDragController.beginDrag()
        session.setDockPosition(.right)  // should be queued
        #expect(session.dockPosition == .bottom)  // unchanged mid-drag

        // End drag; queued toggle applies.
        session.dividerDragController.endDrag(finalRatio: 0.6)
        #expect(session.dockPosition == .right)
    }
}
