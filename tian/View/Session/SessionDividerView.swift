import AppKit
import SwiftUI

/// Draggable divider between the Claude and Terminal areas of a Session.
///
/// * 1pt visual hairline (thinner than `SplitLayout.dividerThickness` which is 4pt).
/// * 10pt total hit area for comfortable pointer acquisition.
/// * Cursor swaps to `resizeLeftRight` / `resizeUpDown` based on `dock`.
/// * Drag clamped via `SessionDividerClamper` (Claude ≥ 320pt, Terminal ≥ 160pt).
/// * On drag past the Terminal minimum, gesture end triggers auto-hide (FR-16).
///
/// Performance (Spec Section 10): the live drag offset lives in local
/// `@GestureState` / `@State` so per-frame updates do NOT mutate
/// `Session.splitRatio` — the pane surfaces never re-layout mid-drag.
/// The ratio is committed exactly once on gesture end.
struct SessionDividerView: View {
    @Bindable var session: Session
    let dock: DockPosition
    /// Container extent along the dock axis (width for `.right`, height for `.bottom`).
    let containerAxis: CGFloat
    /// Live visual offset the parent applies to the two sibling areas
    /// so they track the gesture without involving `Session`.
    @Binding var liveDragRatio: Double?

    @GestureState private var dragging: Bool = false

    var body: some View {
        let clamper = SessionDividerClamper(containerAxis: containerAxis)

        ZStack {
            // Invisible hit target (wider than the visible line).
            Color.clear
                .frame(
                    width: dock == .right ? hitSize : nil,
                    height: dock == .bottom ? hitSize : nil
                )
                .contentShape(Rectangle())

            // Visible divider.
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(
                    width: dock == .right ? Self.thickness : nil,
                    height: dock == .bottom ? Self.thickness : nil
                )
        }
        .frame(
            width: dock == .right ? hitSize : nil,
            height: dock == .bottom ? hitSize : nil
        )
        .onHover { hovering in
            if hovering {
                switch dock {
                case .right:  NSCursor.resizeLeftRight.push()
                case .bottom: NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
        .gesture(dragGesture(clamper: clamper))
        .accessibilityLabel("Terminal divider")
        .accessibilityHint("Drag to resize the Terminal panel.")
    }

    // MARK: - Constants

    /// Hit-target size along the drag axis (larger than visible thickness).
    private var hitSize: CGFloat { 10 }

    // MARK: - Gesture

    private func dragGesture(clamper: SessionDividerClamper) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in
                if !state {
                    state = true
                }
            }
            .onChanged { value in
                if !session.dividerDragController.isDragging {
                    session.dividerDragController.beginDrag()
                }
                let proposed = proposedRatio(fromTranslation: value.translation)
                liveDragRatio = clamper.clampRatio(proposed: proposed)
            }
            .onEnded { value in
                let proposed = proposedRatio(fromTranslation: value.translation)
                let result = clamper.evaluateDragEnd(proposedRatio: proposed)
                if result.shouldHide {
                    session.hideTerminal()
                }
                session.setSplitRatio(result.clamped)
                liveDragRatio = nil
                session.dividerDragController.endDrag(finalRatio: result.clamped)
            }
    }

    private func proposedRatio(fromTranslation translation: CGSize) -> Double {
        guard containerAxis > 0 else { return session.splitRatio }
        let delta: CGFloat
        switch dock {
        case .right:  delta = translation.width
        case .bottom: delta = translation.height
        }
        let baseRatio = session.splitRatio
        return baseRatio + Double(delta / containerAxis)
    }
}

extension SessionDividerView {
    /// Visual thickness of the session divider in points.
    static let thickness: CGFloat = 1
}
