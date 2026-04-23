import SwiftUI

/// Compact per-section toolbar rendered inside the section tab bar.
///
/// * Claude toolbar — Show/Hide Terminal button (FR-28); icon swaps based
///   on `spaceModel.terminalVisible`.
/// * Terminal toolbar — Menu with "Move to Bottom" / "Move to Right"
///   (dock toggle) and "Reset Terminal section".
///
/// Buttons are visually disabled mid-drag (FR-15) with a tooltip pointing
/// to the `SectionDividerDragController`'s active gesture.
struct SectionToolbarView: View {
    @Bindable var spaceModel: SpaceModel
    let kind: SectionKind

    var body: some View {
        let isDragging = spaceModel.sectionDividerDragController.isDragging

        Group {
            switch kind {
            case .claude:
                claudeToolbar(isDragging: isDragging)
            case .terminal:
                terminalToolbar(isDragging: isDragging)
            }
        }
    }

    // MARK: - Claude

    @ViewBuilder
    private func claudeToolbar(isDragging: Bool) -> some View {
        Button {
            spaceModel.toggleTerminal()
        } label: {
            Image(systemName: spaceModel.terminalVisible
                  ? "rectangle.righthalf.inset.filled"
                  : "rectangle.righthalf.inset.filled.arrow.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .glassEffect(.regular, in: .circle)
        .disabled(isDragging)
        .opacity(isDragging ? 0.5 : 1.0)
        .help(isDragging
              ? "Release divider to switch dock"
              : (spaceModel.terminalVisible ? "Hide Terminal" : "Show Terminal"))
        .accessibilityLabel(spaceModel.terminalVisible ? "Hide Terminal" : "Show Terminal")
    }

    // MARK: - Terminal

    @ViewBuilder
    private func terminalToolbar(isDragging: Bool) -> some View {
        Menu {
            Button {
                spaceModel.setDockPosition(.bottom)
            } label: {
                Label(
                    "Move to Bottom",
                    systemImage: spaceModel.dockPosition == .bottom ? "checkmark" : "rectangle.bottomhalf.inset.filled"
                )
            }
            .disabled(spaceModel.dockPosition == .bottom)

            Button {
                spaceModel.setDockPosition(.right)
            } label: {
                Label(
                    "Move to Right",
                    systemImage: spaceModel.dockPosition == .right ? "checkmark" : "rectangle.righthalf.inset.filled"
                )
            }
            .disabled(spaceModel.dockPosition == .right)

            Divider()

            Button(role: .destructive) {
                spaceModel.resetTerminalSection()
            } label: {
                Label("Reset Terminal Section", systemImage: "arrow.counterclockwise")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 28, height: 28)
        .glassEffect(.regular, in: .circle)
        .disabled(isDragging)
        .opacity(isDragging ? 0.5 : 1.0)
        .help(isDragging ? "Release divider to switch dock" : "Terminal section options")
        .accessibilityLabel("Terminal section options")
    }
}
