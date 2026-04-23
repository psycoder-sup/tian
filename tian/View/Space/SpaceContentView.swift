import SwiftUI

/// Root view for a Space. Branches on `dockPosition` (HStack for `.right`,
/// VStack for `.bottom`) and renders the Claude `SectionView`, the
/// `SectionDividerView`, and the Terminal `SectionView` when
/// `terminalVisible == true`. When hidden, Claude expands to fill (FR-17).
///
/// Performance: the live divider-drag state lives in `@State liveDragRatio`
/// at this view so per-frame drag updates do NOT invalidate terminal
/// surfaces (Spec Section 10). `SpaceModel.splitRatio` is committed only on
/// gesture end.
struct SpaceContentView: View {
    @Bindable var spaceModel: SpaceModel
    var resolveWorkingDirectory: () -> String

    /// Live ratio threaded from the divider drag gesture to the two
    /// sibling sections. `nil` when no drag is active.
    @State private var liveDragRatio: Double?

    var body: some View {
        GeometryReader { geo in
            content(containerSize: geo.size)
                .animation(.easeInOut(duration: 0.2), value: spaceModel.terminalVisible)
                .animation(.easeInOut(duration: 0.2), value: spaceModel.dockPosition)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(containerSize: CGSize) -> some View {
        if !spaceModel.terminalVisible {
            // FR-17 — Claude fills the whole space.
            SectionView(
                spaceModel: spaceModel,
                section: spaceModel.claudeSection,
                resolveWorkingDirectory: resolveWorkingDirectory,
                isSectionFocused: spaceModel.focusedSectionKind == .claude
            )
            .frame(width: containerSize.width, height: containerSize.height)
        } else {
            let ratio = liveDragRatio ?? spaceModel.splitRatio
            let layout = SectionLayout.computeFrames(
                containerSize: containerSize,
                ratio: ratio,
                dock: spaceModel.dockPosition,
                claudeMin: SectionDividerClamper.defaultClaudeMin,
                terminalMin: SectionDividerClamper.defaultTerminalMin,
                dividerThickness: SectionDividerView.thickness
            )
            let axis: CGFloat = spaceModel.dockPosition == .right
                ? containerSize.width
                : containerSize.height

            ZStack(alignment: .topLeading) {
                SectionView(
                    spaceModel: spaceModel,
                    section: spaceModel.claudeSection,
                    resolveWorkingDirectory: resolveWorkingDirectory,
                    isSectionFocused: spaceModel.focusedSectionKind == .claude
                )
                .frame(width: layout.claude.width, height: layout.claude.height)
                .offset(x: layout.claude.minX, y: layout.claude.minY)

                SectionView(
                    spaceModel: spaceModel,
                    section: spaceModel.terminalSection,
                    resolveWorkingDirectory: resolveWorkingDirectory,
                    isSectionFocused: spaceModel.focusedSectionKind == .terminal
                )
                .frame(width: layout.terminal.width, height: layout.terminal.height)
                .offset(x: layout.terminal.minX, y: layout.terminal.minY)

                SectionDividerView(
                    spaceModel: spaceModel,
                    dock: spaceModel.dockPosition,
                    containerAxis: axis,
                    liveDragRatio: $liveDragRatio
                )
                .frame(width: layout.divider.width, height: layout.divider.height)
                .offset(x: layout.divider.minX, y: layout.divider.minY)
            }
            .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
        }
    }
}
