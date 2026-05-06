import SwiftUI

/// Compact per-section toolbar rendered inside the section tab bar.
///
/// * Claude toolbar — empty. The Show/Hide Terminal control was relocated
///   to the bottom status bar (rendered from `SidebarContainerView`).
/// * Terminal toolbar — Menu with "Move to Bottom" / "Move to Right"
///   (dock toggle) and "Reset Terminal section".
///
/// Buttons are visually disabled mid-drag (FR-15) with a tooltip pointing
/// to the `SectionDividerDragController`'s active gesture.
struct SectionToolbarView: View {
    @Bindable var spaceModel: SpaceModel
    let kind: SectionKind

    var body: some View {
        if kind == .terminal {
            terminalToolbar(isDragging: spaceModel.sectionDividerDragController.isDragging)
        }
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
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 220/255, green: 228/255, blue: 240/255).opacity(0.92))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 32, height: 32)
        .liquidGlassCircle()
        .disabled(isDragging)
        .opacity(isDragging ? 0.5 : 1.0)
        .help(isDragging ? "Release divider to switch dock" : "Terminal section options")
        .accessibilityLabel("Terminal section options")
    }
}
