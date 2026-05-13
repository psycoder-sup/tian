import AppKit
import Testing
@testable import tian

/// Regression coverage for the focus feedback-loop hang (crash log 2026-05-12).
///
/// Calling `window.makeFirstResponder(...)` synchronously inside
/// `TerminalContentView.updateNSView` triggered KVO on `NSWindow.firstResponder`,
/// which SwiftUI's `FirstResponderObserver` re-entered as another view-graph
/// update — looping the main thread inside `flushTransactions` for ~82s.
/// The fix defers the responder change via `TerminalSurfaceView.shouldBeFocused`,
/// so the KVO notification fires after the active SwiftUI transaction.
@MainActor
struct TerminalSurfaceViewFocusTests {

    private struct Harness {
        let window: NSWindow
        let view: TerminalSurfaceView
        let neutralResponder: NSView
    }

    private func makeHarness() -> Harness {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content

        // Park first responder on a neutral subview so the test can detect
        // when (and only when) the surface view actually becomes first responder.
        let neutral = NSView(frame: content.bounds)
        content.addSubview(neutral)

        let view = TerminalSurfaceView()
        view.frame = content.bounds
        content.addSubview(view)

        _ = window.makeFirstResponder(neutral)
        return Harness(window: window, view: view, neutralResponder: neutral)
    }

    /// Spin the main run loop briefly so DispatchQueue.main.async blocks fire.
    private func drainMainQueue(_ ticks: Int = 3) async {
        for _ in 0..<ticks {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Regression invariants

    @Test("shouldBeFocused = true does NOT synchronously change firstResponder")
    func setShouldBeFocusedDoesNotSynchronouslyPromote() {
        let h = makeHarness()
        #expect(h.window.firstResponder !== h.view)

        h.view.shouldBeFocused = true

        // Critical invariant: if this assertion fails, the SwiftUI feedback-loop
        // hang can return. The setter MUST defer to the next runloop turn.
        #expect(h.window.firstResponder !== h.view,
                "shouldBeFocused setter must not synchronously call makeFirstResponder")
    }

    @Test("shouldBeFocused = true eventually makes the view first responder")
    func setShouldBeFocusedEventuallyPromotes() async throws {
        let h = makeHarness()
        h.view.shouldBeFocused = true

        try await pollUntil { h.window.firstResponder === h.view }
    }

    @Test("shouldBeFocused = false leaves first responder alone")
    func setShouldBeFocusedFalseDoesNothing() async {
        let h = makeHarness()
        h.view.shouldBeFocused = false
        await drainMainQueue()
        #expect(h.window.firstResponder !== h.view)
    }

    @Test("Repeated true assignments don't redispatch and don't crash")
    func repeatedAssignmentsAreIdempotent() async throws {
        let h = makeHarness()
        h.view.shouldBeFocused = true
        h.view.shouldBeFocused = true
        h.view.shouldBeFocused = true
        try await pollUntil { h.window.firstResponder === h.view }

        // Setting true again once already focused must remain a no-op.
        h.view.shouldBeFocused = true
        await drainMainQueue()
        #expect(h.window.firstResponder === h.view)
    }

    @Test("Flipping true then false within the same runloop cancels the promotion")
    func toggleWithinTickCancelsPromotion() async {
        let h = makeHarness()
        h.view.shouldBeFocused = true
        h.view.shouldBeFocused = false
        await drainMainQueue()
        #expect(h.window.firstResponder !== h.view)
    }

    @Test("viewDidMoveToWindow with shouldBeFocused restores focus on re-attach")
    func reattachRestoresFocus() async throws {
        let h = makeHarness()
        h.view.shouldBeFocused = true
        try await pollUntil { h.window.firstResponder === h.view }

        // Detach and re-attach (simulates SwiftUI recreating the container).
        h.view.removeFromSuperview()
        _ = h.window.makeFirstResponder(h.neutralResponder)
        #expect(h.window.firstResponder !== h.view)

        h.window.contentView?.addSubview(h.view)
        try await pollUntil { h.window.firstResponder === h.view }
    }
}
