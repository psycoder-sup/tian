import AppKit
import SwiftUI

/// Thin drag handle on the leading edge of the inspect panel (FR-02).
///
/// On drag, mutates `panelState.width` via `panelState.clampedWidth(_:)`,
/// clamping to [240, 480] px.
struct InspectPanelResizeHandle: View {
    @Bindable var panelState: InspectPanelState

    /// Total hit-target width.
    private static let hitWidth: CGFloat = 8

    @GestureState private var dragStart: CGFloat? = nil
    @State private var isHovering = false

    var body: some View {
        Color.clear
            .frame(width: Self.hitWidth)
            .contentShape(Rectangle())
            .frame(maxHeight: .infinity)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .updating($dragStart) { _, state, _ in
                    // Anchor purely on the panel width at drag start; do not
                    // include the first-sample translation here (that caused a
                    // ~1 pt jump because the anchor shifted with the gesture).
                    if state == nil {
                        state = panelState.width
                    }
                }
                .onChanged { value in
                    // translation.width is negative when dragging left (widening the panel)
                    // The handle sits on the leading edge, so dragging left increases width.
                    let proposed = (dragStart ?? panelState.width) - value.translation.width
                    panelState.width = panelState.clampedWidth(proposed)
                }
        )
    }
}

// MARK: - Previews

#Preview("Resize handle") {
    let state = InspectPanelState()
    HStack(spacing: 0) {
        Color.gray.opacity(0.3)
            .frame(maxWidth: .infinity)
        InspectPanelResizeHandle(panelState: state)
        Color(red: 8/255, green: 11/255, blue: 18/255)
            .frame(width: state.width)
    }
    .frame(height: 200)
}
