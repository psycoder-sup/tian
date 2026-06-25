import Testing
import Foundation
@testable import tian

@MainActor
struct PaneViewModelRealizeSurfaceTests {
    /// A pane ID that isn't in the view model has no wrapper/view, so realization
    /// cannot proceed and must return nil (handlers map this to "no live terminal").
    @Test func realizeUnknownPaneReturnsNil() {
        let pvm = PaneViewModel.makeEmpty()
        #expect(pvm.realizeSurface(for: UUID()) == nil)
    }

    /// An empty (non-terminal) view model has a placeholder leaf but no surface/view,
    /// so realizing its leaf must also return nil rather than attempt to spawn.
    @Test func realizeLeafWithoutSurfaceReturnsNil() {
        let pvm = PaneViewModel.makeEmpty()
        #expect(pvm.realizeSurface(for: pvm.splitTree.focusedPaneID) == nil)
    }

    /// A normal (foreground) split moves keyboard focus to the new pane.
    @Test func splitPaneFocusesNewPaneByDefault() {
        let pvm = PaneViewModel.makeEmpty()
        let newID = pvm.splitPane(direction: .vertical)
        #expect(newID != nil)
        #expect(pvm.splitTree.focusedPaneID == newID)
    }

    /// A background split (`focusOnCreate: false`, used by `pane split --background`)
    /// creates the pane but leaves keyboard focus on the originally-focused pane.
    @Test func backgroundSplitKeepsFocusOnOriginalPane() {
        let pvm = PaneViewModel.makeEmpty()
        let original = pvm.splitTree.focusedPaneID
        let newID = pvm.splitPane(direction: .vertical, focusOnCreate: false)
        #expect(newID != nil)
        #expect(newID != original)
        #expect(pvm.splitTree.focusedPaneID == original)
    }
}
