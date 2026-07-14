import AppKit
import SwiftUI

/// The spinning rainbow border, animated by Core Animation instead of SwiftUI.
///
/// The `TimelineView` this replaces re-evaluated the view graph on every display
/// cycle for as long as it was on screen — a full `NSHostingView.layout` pass at
/// ~60 Hz, whose cost scaled with the size of the whole window's graph, not with
/// the border. A `CABasicAnimation` runs on the render server: the main thread
/// touches it once, at setup, and never again.
///
/// Pausing on occlusion is handled for free — Core Animation stops advancing
/// animations for windows nobody can see — so unlike the SwiftUI version this
/// needs no `\.windowIsVisible` plumbing.
struct RainbowBorderLayer: NSViewRepresentable {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 2
    /// Seconds per revolution. 6 s == the 60°/s of the `TimelineView` version.
    var period: CFTimeInterval = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> RainbowBorderNSView {
        RainbowBorderNSView(
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            period: period,
            animates: !reduceMotion
        )
    }

    func updateNSView(_ view: RainbowBorderNSView, context: Context) {
        view.update(
            cornerRadius: cornerRadius,
            lineWidth: lineWidth,
            period: period,
            animates: !reduceMotion
        )
    }
}

/// Layer-backed host for the rainbow border: a conic gradient spinning behind a
/// rounded-rect stroke mask.
final class RainbowBorderNSView: NSView {
    private static let rotationKey = "rainbow.spin"

    private let gradientLayer = CAGradientLayer()
    private let maskLayer = CAShapeLayer()

    private var cornerRadius: CGFloat
    private var lineWidth: CGFloat
    private var period: CFTimeInterval
    private var animates: Bool

    init(cornerRadius: CGFloat, lineWidth: CGFloat, period: CFTimeInterval, animates: Bool) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.period = period
        self.animates = animates
        super.init(frame: .zero)

        wantsLayer = true
        // Decorative only — the SwiftUI overlay it sits in is already
        // non-interactive, but this keeps the AppKit view out of hit testing too.
        let container = layer ?? CALayer()
        layer = container

        gradientLayer.type = .conic
        gradientLayer.colors = rainbowCGColors
        gradientLayer.locations = Self.evenLocations(count: rainbowCGColors.count)
        // Conic gradients sweep around `startPoint`; `endPoint` only fixes where
        // the sweep begins (straight up here). The rotation animation does the rest.
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        container.addSublayer(gradientLayer)

        maskLayer.fillColor = NSColor.clear.cgColor
        maskLayer.strokeColor = NSColor.black.cgColor
        container.mask = maskLayer

        applyAnimation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var isFlipped: Bool { true }

    func update(cornerRadius: CGFloat, lineWidth: CGFloat, period: CFTimeInterval, animates: Bool) {
        let geometryChanged = cornerRadius != self.cornerRadius || lineWidth != self.lineWidth
        let animationChanged = period != self.period || animates != self.animates

        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.period = period
        self.animates = animates

        if geometryChanged { needsLayout = true }
        if animationChanged { applyAnimation() }
    }

    override func layout() {
        super.layout()
        // Implicit animations would make every resize crossfade the mask.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let size = bounds.size
        // A rotating rectangle sweeps its own corners out of frame; size the
        // gradient to the circumscribing square so the mask is always covered.
        let side = hypot(size.width, size.height)
        gradientLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradientLayer.position = CGPoint(x: size.width / 2, y: size.height / 2)

        maskLayer.frame = bounds
        maskLayer.lineWidth = lineWidth
        // `strokeBorder` semantics: inset by half the line width so the stroke
        // sits fully inside the view, matching the SwiftUI shape it replaces.
        let inset = lineWidth / 2
        maskLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: max(0, cornerRadius - inset),
            cornerHeight: max(0, cornerRadius - inset),
            transform: nil
        )
    }

    /// Re-adding the animation after a window move keeps it running across
    /// display changes; dropping it when there is no window avoids spinning
    /// against nothing.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAnimation()
    }

    private func applyAnimation() {
        gradientLayer.removeAnimation(forKey: Self.rotationKey)
        guard animates, window != nil else { return }

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi
        spin.duration = period
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        gradientLayer.add(spin, forKey: Self.rotationKey)
    }

    private static func evenLocations(count: Int) -> [NSNumber] {
        guard count > 1 else { return [0] }
        return (0..<count).map { NSNumber(value: Double($0) / Double(count - 1)) }
    }
}
