import SwiftUI

/// Compact line chart used in the status bar's CPU/RAM cells. Thin stroked
/// polyline over a translucent fill of the same color. Input is expected
/// in `[0, 1]`; the chart normalizes against `1.0` (not `data.max()`) so
/// height tracks absolute load — a 5% peak doesn't visually equal a 95%
/// peak.
struct SparklineView: View {
    let data: [Double]
    let color: Color
    var width: CGFloat = 38
    var height: CGFloat = 10

    var body: some View {
        Canvas { context, _ in
            guard data.count >= 2 else { return }
            let stepX = width / CGFloat(data.count - 1)
            var line = Path()
            for (i, value) in data.enumerated() {
                let x = CGFloat(i) * stepX
                let clamped = min(max(value, 0), 1)
                let y = height - CGFloat(clamped) * height
                if i == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
            }
            var fill = line
            fill.addLine(to: CGPoint(x: width, y: height))
            fill.addLine(to: CGPoint(x: 0, y: height))
            fill.closeSubpath()
            context.fill(fill, with: .color(color.opacity(0.18)))
            context.stroke(line, with: .color(color), lineWidth: 1)
        }
        .frame(width: width, height: height)
    }
}
