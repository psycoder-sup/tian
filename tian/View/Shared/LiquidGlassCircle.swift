import SwiftUI

/// Liquid-glass circular treatment used for floating UI controls
/// (inspect panel toggle, section toolbar buttons).
///
/// Provides the gradient + ultra-thin-material background, white stroke,
/// inset top highlight, drop shadow, and a subtle hover scale.
/// Apply to a sized container (typically 32×32).
struct LiquidGlassCircle: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
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
    }
}

extension View {
    /// Applies the liquid-glass circular style used by floating controls.
    func liquidGlassCircle() -> some View {
        modifier(LiquidGlassCircle())
    }
}
