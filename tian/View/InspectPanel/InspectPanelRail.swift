import SwiftUI

/// Collapsed-state toggle for the inspect panel (FR-07).
///
/// 32×32 circular liquid-glass button — gradient + inset highlights + drop
/// shadow — floated at the top-trailing corner of the workspace content
/// area. Tap fires `onShow`.
struct InspectPanelRail: View {
    static let size: CGFloat = 32

    let onShow: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onShow) {
            inspectorIcon
                .frame(width: 15, height: 15)
                .foregroundStyle(Color(red: 220/255, green: 228/255, blue: 240/255).opacity(0.92))
        }
        .buttonStyle(.plain)
        .frame(width: Self.size, height: Self.size)
        .background(
            Circle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.14), location: 0.0),
                            .init(color: Color.white.opacity(0.05), location: 0.55),
                            .init(color: Color.white.opacity(0.025), location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(.ultraThinMaterial, in: Circle())
        )
        .overlay(
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .overlay(
            // Inset highlights (top + bottom) per design.
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .blur(radius: 0.5)
                .mask(
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 7, x: 0, y: 4)
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
        .accessibilityLabel("Show inspect panel")
        .accessibilityAddTraits(.isButton)
    }

    /// Inspector-panel glyph: rounded outer rect, vertical divider near the
    /// trailing edge, with the trailing portion subtly filled.
    private var inspectorIcon: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            let outerRect = CGRect(x: 2, y: 3, width: 12, height: 10)
                .scaled(by: w / 16, h / 16)
            let outerPath = Path(roundedRect: outerRect, cornerRadius: 2 * w / 16)

            let dividerStart = CGPoint(x: 10 * w / 16, y: 3.5 * h / 16)
            let dividerEnd = CGPoint(x: 10 * w / 16, y: 12.5 * h / 16)
            var divider = Path()
            divider.move(to: dividerStart)
            divider.addLine(to: dividerEnd)

            let trailingFill = CGRect(x: 10.4, y: 3.6, width: 3.2, height: 8.8)
                .scaled(by: w / 16, h / 16)
            let trailingPath = Path(
                roundedRect: trailingFill,
                cornerRadius: 0.6 * w / 16
            )

            // Filled trailing area (subtle).
            context.fill(trailingPath, with: .color(Color.primary.opacity(0.18)))

            // Outline + divider.
            context.stroke(outerPath, with: .color(Color.primary), lineWidth: 1.1)
            context.stroke(divider, with: .color(Color.primary), lineWidth: 1.1)
        }
    }
}

private extension CGRect {
    func scaled(by sx: CGFloat, _ sy: CGFloat) -> CGRect {
        CGRect(
            x: origin.x * sx,
            y: origin.y * sy,
            width: size.width * sx,
            height: size.height * sy
        )
    }
}

// MARK: - Previews

#Preview("Toggle button") {
    InspectPanelRail(onShow: {})
        .padding(40)
        .background(
            Color(red: 8/255, green: 11/255, blue: 18/255).opacity(0.95)
        )
}
