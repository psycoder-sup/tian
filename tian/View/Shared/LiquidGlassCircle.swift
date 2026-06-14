import SwiftUI

/// Glass treatment used for floating UI controls (section toolbar buttons, the
/// new-tab "+"/copy control).
///
/// A flat ultra-thin-material background with a white edge stroke, inset top
/// highlight, and drop shadow, clipped to the supplied shape. No fill tint and
/// no whole-shape hover — hover feedback is per-button via `glassHoverHighlight()`
/// on the controls inside. Use `liquidGlassCircle()` for a single round control,
/// or `liquidGlassCapsule()` for a pill that can grow to hold more than one
/// control (and morph between the two as it resizes).
struct LiquidGlassBackground<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .overlay(
                shape
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
    }
}

/// Per-button hover highlight for controls inside (or styled like) a glass
/// control — a subtle inset fill behind just that button, replacing any
/// whole-shape hover. Lets a multi-button capsule read segment-by-segment.
private struct GlassHoverHighlight: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            // Whole cell (not just the glyph) is the hover target.
            .contentShape(Rectangle())
            .background {
                Circle()
                    .fill(Color.white.opacity(isHovering ? 0.12 : 0))
                    .padding(3)
            }
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

extension View {
    /// Applies the glass style clipped to a circle (single round control).
    func liquidGlassCircle() -> some View {
        modifier(LiquidGlassBackground(shape: Circle()))
    }

    /// Applies the glass style clipped to a capsule. A capsule sized to a
    /// single square control renders as a circle, so a control row can morph
    /// from circle to pill as it gains/loses members.
    func liquidGlassCapsule() -> some View {
        modifier(LiquidGlassBackground(shape: Capsule()))
    }

    /// Subtle per-button hover highlight. Apply to a sized button cell inside a
    /// glass control so hover reads per button instead of for the whole shape.
    func glassHoverHighlight() -> some View {
        modifier(GlassHoverHighlight())
    }
}
