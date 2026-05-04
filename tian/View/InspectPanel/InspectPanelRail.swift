import SwiftUI

/// 22 px collapsed rail along the right edge (FR-07).
///
/// Shows the word `inspect` rotated 90° (so it reads bottom-to-top).
/// Tapping the rail calls `onShow` — the wiring task will set
/// `panelState.isVisible = true`.
struct InspectPanelRail: View {
    static let width: CGFloat = 22

    let onShow: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color(red: 8/255, green: 11/255, blue: 18/255).opacity(0.55)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 0.5)
                }

            Text("inspect")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(isHovering ? 0.6 : 0.3))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onShow() }
        .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Previews

#Preview("Rail") {
    InspectPanelRail(onShow: {})
        .frame(height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
