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

// MARK: - Focus indicator (sharp rainbow border, no glow)

struct RainbowBorder: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let angle = Angle.degrees(timeline.date.timeIntervalSinceReferenceDate * 60)

            AngularGradient(
                colors: rainbowColors,
                center: .center,
                startAngle: angle,
                endAngle: angle + .degrees(360)
            )
            .mask {
                RoundedRectangle(cornerRadius: glowCornerRadius)
                    .strokeBorder(lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Notification indicator (soft inward glow, no border)

struct RainbowGlow: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(t * 60)
            let breathe = 0.85 + 0.15 * sin(t * 0.8 * .pi)

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
