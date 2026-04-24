import AppKit
import SwiftUI

/// Draggable divider between the Claude and Terminal sections.
///
/// * 1pt visual hairline (thinner than `SplitLayout.dividerThickness` which is 4pt).
/// * 10pt total hit area for comfortable pointer acquisition.
/// * Cursor swaps to `resizeLeftRight` / `resizeUpDown` based on `dock`.
/// * Drag clamped via `SectionDividerClamper` (Claude ≥ 320pt, Terminal ≥ 160pt).
/// * On drag past the Terminal minimum, gesture end triggers auto-hide (FR-16).
///
/// Performance (Spec Section 10): the live drag offset lives in local
/// `@GestureState` / `@State` so per-frame updates do NOT mutate
/// `SpaceModel.splitRatio` — the pane surfaces never re-layout mid-drag.
/// The ratio is committed exactly once on gesture end.
struct SectionDividerView: View {
    @Bindable var spaceModel: SpaceModel
    let dock: DockPosition
    /// Container extent along the dock axis (width for `.right`, height for `.bottom`).
    let containerAxis: CGFloat
    /// Live visual offset the parent applies to the two sibling sections
    /// so they track the gesture without involving `SpaceModel`.
    @Binding var liveDragRatio: Double?

    @GestureState private var dragging: Bool = false

    var body: some View {
        let clamper = SectionDividerClamper(containerAxis: containerAxis)

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
        .accessibilityLabel("Section divider")
        .accessibilityHint("Drag to resize the Terminal section.")
    }

    // MARK: - Constants

    /// Hit-target size along the drag axis (larger than visible thickness).
    private var hitSize: CGFloat { 10 }

    // MARK: - Gesture

    private func dragGesture(clamper: SectionDividerClamper) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in
                if !state {
                    state = true
                }
            }
            .onChanged { value in
                if !spaceModel.sectionDividerDragController.isDragging {
                    spaceModel.sectionDividerDragController.beginDrag()
                }
                let proposed = proposedRatio(fromTranslation: value.translation)
                liveDragRatio = clamper.clampRatio(proposed: proposed, dock: dock)
            }
            .onEnded { value in
                let proposed = proposedRatio(fromTranslation: value.translation)
                let result = clamper.evaluateDragEnd(proposedRatio: proposed, dock: dock)
                if result.shouldHide {
                    spaceModel.hideTerminal()
                    spaceModel.setSplitRatio(result.clamped)
                } else {
                    spaceModel.setSplitRatio(result.clamped)
                }
                liveDragRatio = nil
                spaceModel.sectionDividerDragController.endDrag(finalRatio: result.clamped)
            }
    }

    private func proposedRatio(fromTranslation translation: CGSize) -> Double {
        guard containerAxis > 0 else { return spaceModel.splitRatio }
        let delta: CGFloat
        switch dock {
        case .right:  delta = translation.width
        case .bottom: delta = translation.height
        }
        let baseRatio = spaceModel.splitRatio
        return baseRatio + Double(delta / containerAxis)
    }
}

extension SectionDividerView {
    /// Visual thickness of the section divider in points.
    static let thickness: CGFloat = 1
}
