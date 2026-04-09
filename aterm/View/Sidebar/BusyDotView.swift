import SwiftUI

/// Pulsing blue dot for the "busy" Claude session state.
/// Animates with a smooth opacity pulse (1.0 → 0.4 → 1.0 over ~2s).
/// Respects the system's Reduce Motion accessibility setting.
struct BusyDotView: View {
    @State private var isAnimating: Bool = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        Circle()
            .fill(Color(red: 0.2, green: 0.55, blue: 1.0))
            .frame(width: 8, height: 8)
            .opacity(isAnimating ? 0.4 : 1.0)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                if !reduceMotion {
                    isAnimating = true
                }
            }
            .onChange(of: reduceMotion) { _, newValue in
                isAnimating = !newValue
            }
    }
}
