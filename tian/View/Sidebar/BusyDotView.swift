import SwiftUI

/// Mesh-gradient dot for the "busy" Claude session state.
/// Displays a vibrant purple/blue/magenta mesh gradient clipped to a circle,
/// with a slow aurora animation that rotates the color positions.
/// Respects the system's Reduce Motion accessibility setting.
struct BusyDotView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        TimelineView(reduceMotion ? .animation(minimumInterval: nil, paused: true) : .animation(minimumInterval: 0.033)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let s = CGFloat(t) * 0.8

            MeshGradient(
                width: 3,
                height: 3,
                points: meshPoints(phase: s),
                colors: meshColors(phase: s)
            )
            .frame(width: 8, height: 8)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.0),
                                .white.opacity(0.8),
                            ],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        lineWidth: 1
                    )
                    .rotationEffect(.degrees(t * 360))
            )
        }
    }

    private func meshPoints(phase s: CGFloat) -> [SIMD2<Float>] {
        let cx = Float(0.5 + 0.15 * cos(s * 1.2))
        let cy = Float(0.5 + 0.15 * sin(s * 0.9))
        return [
            SIMD2(0, 0),   SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5), SIMD2(cx, cy),  SIMD2(1, 0.5),
            SIMD2(0, 1),   SIMD2(0.5, 1), SIMD2(1, 1),
        ]
    }

    private func meshColors(phase s: CGFloat) -> [Color] {
        let t0 = s
        let t1 = s + 1.5
        let t2 = s + 3.0

        return [
            auroraColor(t: t0),        auroraColor(t: t0 + 0.8), auroraColor(t: t1),
            auroraColor(t: t2 + 0.5),  auroraColor(t: t1 + 1.0), auroraColor(t: t2),
            auroraColor(t: t1 + 0.3),  auroraColor(t: t2 + 0.8), auroraColor(t: t0 + 0.5),
        ]
    }

    private func auroraColor(t: CGFloat) -> Color {
        let n = t.truncatingRemainder(dividingBy: 4.0) / 4.0
        let angle = n * 2 * .pi

        let r = 0.55 + 0.45 * cos(angle + 4.0)
        let g = 0.20 + 0.20 * cos(angle + 2.5)
        let b = 0.90 + 0.10 * sin(angle)

        return Color(red: r, green: g, blue: b)
    }
}
