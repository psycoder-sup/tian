import SwiftUI

/// Toggle button for the inspect panel (FR-07).
///
/// Plain SF Symbol icon (no liquid-glass capsule) to match the sidebar
/// toggle's understated style. Used both as the floating top-trailing
/// toggle when the panel is collapsed and as the in-header toggle when
/// the panel is open. Tap fires `action`, which the call site wires to
/// either show or hide the panel.
struct InspectPanelRail: View {
    static let size: CGFloat = 22

    let action: () -> Void
    var accessibilityTitle: String = "Toggle inspect panel"

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Self.size, height: Self.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#Preview("Toggle button") {
    InspectPanelRail(action: {})
        .padding(40)
        .background(
            Color(red: 8/255, green: 11/255, blue: 18/255).opacity(0.95)
        )
}
