import AppKit
import SwiftUI

/// Excludes the SwiftUI region it backs from `.fullSizeContentView` titlebar
/// window-dragging while leaving SwiftUI gestures functional. Two layers:
///
/// - `mouseDownCanMoveWindow == false`: AppKit consults the deepest
///   hit-tested NSView at the click point; SwiftUI-drawn content has no
///   backing NSView, so this `.background` becomes that deepest view and
///   vetoes the drag. Not airtight — Liquid Glass platform views can sit
///   above it in AppKit hit-testing and answer `true` themselves, and
///   titlebar dragging is performed server-side from a pre-registered drag
///   region, so a mouse-down-time veto can be too late.
/// - A tracking area toggles `window.isMovable = false` while the cursor
///   hovers this view, well before any click lands, and restores movability
///   when the cursor leaves. This is the layer that closes the glass hole.
///
/// Events still bubble to NSHostingView via the responder chain, so taps,
/// drags, and context menus on the SwiftUI content above keep working.
///
/// Must be applied with `.background(...)` — an `.overlay` would occlude
/// SwiftUI hit-testing, and `.allowsHitTesting(false)` would remove it from
/// AppKit hit-testing and defeat the veto.
struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BlockerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class BlockerView: NSView {
    private var didDisableMovability = false
    private var movabilityTrackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil { restoreMovability() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncToCurrentMouseLocation()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let movabilityTrackingArea { removeTrackingArea(movabilityTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        movabilityTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        disableMovability()
    }

    override func mouseExited(with event: NSEvent) {
        restoreMovability()
    }

    /// Tracking areas only report transitions; when the view appears with
    /// the cursor already inside (window restore, space switch) no
    /// mouseEntered will fire, so sync the initial state manually.
    private func syncToCurrentMouseLocation() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if bounds.contains(point) {
            disableMovability()
        } else {
            restoreMovability()
        }
    }

    private func disableMovability() {
        guard let window else { return }
        window.isMovable = false
        didDisableMovability = true
    }

    private func restoreMovability() {
        guard didDisableMovability else { return }
        window?.isMovable = true
        didDisableMovability = false
    }
}
