import SwiftUI

/// Spinning rainbow gradient dot for the "busy" Claude session state.
/// Animation always active regardless of Reduce Motion setting.
struct BusyDotView: View {
    @State private var rotation: Double = 0

    var body: some View {
        Circle()
            .fill(
                AngularGradient(colors: rainbowColors, center: .center)
            )
            .frame(width: 8, height: 8)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
