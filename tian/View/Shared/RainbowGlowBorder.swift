import SwiftUI

/// Rainbow colors derived from the Figma conic gradient spec.
let rainbowColors: [Color] = [
    Color(red: 1.0,  green: 0.2,  blue: 0.2),
    Color(red: 1.0,  green: 0.55, blue: 0.0),
    Color(red: 1.0,  green: 0.85, blue: 0.0),
    Color(red: 0.25, green: 0.9,  blue: 0.4),
    Color(red: 0.2,  green: 0.85, blue: 0.85),
    Color(red: 0.2,  green: 0.55, blue: 1.0),
    Color(red: 0.55, green: 0.3,  blue: 1.0),
    Color(red: 0.8,  green: 0.25, blue: 0.85),
    Color(red: 1.0,  green: 0.2,  blue: 0.45),
    Color(red: 1.0,  green: 0.2,  blue: 0.2),
]

private let glowCornerRadius: CGFloat = 6

/// Tick interval for the rainbow overlays. 10 fps is indistinguishable from
/// 12 fps once the gradients are blurred/stroked, and saves main-thread work.
private let rainbowTickInterval: TimeInterval = 1.0 / 10.0

/// Shared breathing envelope for rainbow overlays — oscillates in
/// `[0.70, 1.00]` with a 2.5 s period. Drives `RainbowGlow`'s pulse.
@inlinable func rainbowBreathe(_ t: TimeInterval) -> Double {
    0.85 + 0.15 * sin(t * 0.8 * .pi)
}

// MARK: - Focus indicator (sharp rainbow border, no glow)

struct RainbowBorder: View {
    /// Corner radius of the border stroke. Defaults to the shared glow radius so
    /// existing callers are unaffected; larger surfaces (e.g. the 12pt overview
    /// card) pass their own so the rainbow hugs their rounded corners.
    var cornerRadius: CGFloat = glowCornerRadius

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.windowIsVisible) private var windowIsVisible

    var body: some View {
        if reduceMotion {
            // Static gradient — no animation
            AngularGradient(
                colors: rainbowColors,
                center: .center
            )
            .mask {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(lineWidth: 2)
            }
            .allowsHitTesting(false)
        } else {
            TimelineView(.animation(minimumInterval: rainbowTickInterval, paused: !windowIsVisible)) { timeline in
                let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate * 60)

                AngularGradient(
                    colors: rainbowColors,
                    center: .center,
                    startAngle: angle,
                    endAngle: angle + .degrees(360)
                )
                .mask {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(lineWidth: 2)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Notification indicator (soft inward glow, no border)

struct RainbowGlow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.windowIsVisible) private var windowIsVisible

    /// Paused when motion is reduced or the window is occluded. With `t`
    /// frozen at 0 the glow renders once, statically, at a fixed angle.
    private var paused: Bool { reduceMotion || !windowIsVisible }

    var body: some View {
        TimelineView(.animation(minimumInterval: rainbowTickInterval, paused: paused)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(t * 60)
            let breathe = rainbowBreathe(t)

            let gradient = AngularGradient(
                colors: rainbowColors,
                center: .center,
                startAngle: angle,
                endAngle: angle + .degrees(360)
            )

            ZStack {
                gradient
                    .mask {
                        RoundedRectangle(cornerRadius: glowCornerRadius)
                            .strokeBorder(lineWidth: 18)
                    }
                    .blur(radius: 18)
                    .opacity(0.35 * breathe)

                gradient
                    .mask {
                        RoundedRectangle(cornerRadius: glowCornerRadius)
                            .strokeBorder(lineWidth: 8)
                    }
                    .blur(radius: 8)
                    .opacity(0.6 * breathe)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Session state indicator (static colored border)

struct SessionStateBorder: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: glowCornerRadius)
            .strokeBorder(color, lineWidth: 2)
            .allowsHitTesting(false)
    }
}
