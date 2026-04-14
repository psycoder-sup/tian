import SwiftUI

/// Renders two child views side-by-side (or top/bottom) with a draggable divider.
///
/// Modeled after Ghostty's `SplitView` — uses `GeometryReader` + `ZStack`
/// to position children at computed frames with a divider between them.
struct SplitContainerView<First: View, Second: View>: View {
    let splitID: UUID
    let direction: SplitDirection
    let ratio: Double
    let viewModel: PaneViewModel
    @ViewBuilder let first: First
    @ViewBuilder let second: Second

    private let dividerVisibleSize: CGFloat = 1
    private let dividerInvisibleSize: CGFloat = 6
    private let minSplitFraction: CGFloat = 0.1

    var body: some View {
        GeometryReader { geo in
            let leftRect = self.leftRect(for: geo.size)
            let rightRect = self.rightRect(for: geo.size, leftRect: leftRect)
            let splitterPoint = self.splitterPoint(for: geo.size, leftRect: leftRect)

            ZStack(alignment: .topLeading) {
                first
                    .frame(width: leftRect.size.width, height: leftRect.size.height)
                    .offset(x: leftRect.origin.x, y: leftRect.origin.y)

                second
                    .frame(width: rightRect.size.width, height: rightRect.size.height)
                    .offset(x: rightRect.origin.x, y: rightRect.origin.y)

                SplitDividerView(direction: direction, visibleSize: dividerVisibleSize, invisibleSize: dividerInvisibleSize)
                    .position(splitterPoint)
                    .gesture(dragGesture(geo.size))
                    .accessibilityLabel("Split divider")
            }
        }
    }

    // MARK: - Layout

    private func leftRect(for size: CGSize) -> CGRect {
        var result = CGRect(origin: .zero, size: size)
        switch direction {
        case .horizontal:
            result.size.width *= ratio
            result.size.width -= dividerVisibleSize / 2
        case .vertical:
            result.size.height *= ratio
            result.size.height -= dividerVisibleSize / 2
        }
        return result
    }

    private func rightRect(for size: CGSize, leftRect: CGRect) -> CGRect {
        var result = CGRect(origin: .zero, size: size)
        switch direction {
        case .horizontal:
            result.origin.x = leftRect.size.width + dividerVisibleSize / 2
            result.size.width -= result.origin.x
        case .vertical:
            result.origin.y = leftRect.size.height + dividerVisibleSize / 2
            result.size.height -= result.origin.y
        }
        return result
    }

    private func splitterPoint(for size: CGSize, leftRect: CGRect) -> CGPoint {
        switch direction {
        case .horizontal:
            CGPoint(x: leftRect.size.width, y: size.height / 2)
        case .vertical:
            CGPoint(x: size.width / 2, y: leftRect.size.height)
        }
    }

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { gesture in
                let newRatio: Double
                switch direction {
                case .horizontal:
                    let clamped = min(max(size.width * minSplitFraction, gesture.location.x), size.width * (1 - minSplitFraction))
                    newRatio = clamped / size.width
                case .vertical:
                    let clamped = min(max(size.height * minSplitFraction, gesture.location.y), size.height * (1 - minSplitFraction))
                    newRatio = clamped / size.height
                }
                viewModel.updateRatio(splitID: splitID, newRatio: newRatio)
            }
    }
}

// MARK: - Divider View

/// The visual divider between two split panes.
private struct SplitDividerView: View {
    let direction: SplitDirection
    let visibleSize: CGFloat
    let invisibleSize: CGFloat

    var body: some View {
        ZStack {
            // Invisible hit target
            Color.clear
                .frame(
                    width: direction == .horizontal ? visibleSize + invisibleSize : nil,
                    height: direction == .vertical ? visibleSize + invisibleSize : nil
                )
                .contentShape(Rectangle())

            // Visible divider line
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(
                    width: direction == .horizontal ? visibleSize : nil,
                    height: direction == .vertical ? visibleSize : nil
                )
        }
        .onHover { isHovered in
            if isHovered {
                switch direction {
                case .horizontal: NSCursor.resizeLeftRight.push()
                case .vertical: NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
    }
}
