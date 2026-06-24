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
}
