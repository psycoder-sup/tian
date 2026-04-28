import SwiftUI

/// Rainbow edge glow around the active Claude tab pill while a pane
/// is busy. A 5×3 `MeshGradient` with rainbow hues on the 12
/// perimeter slots in clockwise order, masked to a stroked capsule
/// and blurred so the color reads as a soft rotating halo. The phase
/// advances over time so the rainbow orbits the pill clockwise.
///
/// Uses an HSB-computed palette rather than the shared
/// `rainbowColors` constant — at saturation 0.85 / brightness 0.95
/// the hues stay distinct on a wide pill where the shared Figma
/// palette smeared into red-dominant mud. Keep in sync with
/// `BusyDotView` if the aesthetic is ever retuned.
///
/// Respects the system's Reduce Motion accessibility setting.
struct AuroraCapsuleFill: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        TimelineView(reduceMotion ? .animation(minimumInterval: nil, paused: true) : .animation(minimumInterval: 1.0 / 12.0)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(t) * 0.18
            let breathe = reduceMotion ? 1.0 : rainbowBreathe(t)

            MeshGradient(
                width: 5,
                height: 3,
                points: auroraMeshPoints,
                colors: meshColors(phase: phase),
                smoothsColors: true
            )
            .mask {
                Capsule().strokeBorder(lineWidth: 16)
            }
            .blur(radius: 10)
            .opacity(0.55 * breathe)
            .allowsHitTesting(false)
        }
    }

    private func meshColors(phase: CGFloat) -> [Color] {
        var colors = Array(repeating: Color.black, count: 15)
        let count = auroraClockwisePerimeter.count
        for (step, idx) in auroraClockwisePerimeter.enumerated() {
            let h = CGFloat(step) / CGFloat(count) + phase
            colors[idx] = hueColor(h)
        }
        return colors
    }

    private func hueColor(_ h: CGFloat) -> Color {
        var n = h.truncatingRemainder(dividingBy: 1.0)
        if n < 0 { n += 1 }
        return Color(hue: Double(n), saturation: 0.85, brightness: 0.95)
    }
}

// 5×3 grid, row-major. Used by `AuroraCapsuleFill`.
//  0  1  2  3  4   <- top row
//  5  6  7  8  9   <- middle row
// 10 11 12 13 14   <- bottom row
private let auroraMeshPoints: [SIMD2<Float>] = [
    SIMD2(0.00, 0.0), SIMD2(0.25, 0.0), SIMD2(0.50, 0.0), SIMD2(0.75, 0.0), SIMD2(1.00, 0.0),
    SIMD2(0.00, 0.5), SIMD2(0.25, 0.5), SIMD2(0.50, 0.5), SIMD2(0.75, 0.5), SIMD2(1.00, 0.5),
    SIMD2(0.00, 1.0), SIMD2(0.25, 1.0), SIMD2(0.50, 1.0), SIMD2(0.75, 1.0), SIMD2(1.00, 1.0),
]

// 12 perimeter slots in clockwise order: top row L→R, middle-right,
// bottom row R→L, middle-left.
private let auroraClockwisePerimeter: [Int] = [0, 1, 2, 3, 4, 9, 14, 13, 12, 11, 10, 5]
