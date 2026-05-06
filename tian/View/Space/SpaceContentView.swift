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
        // Keep Claude's SectionView at a single, stable position in the view
        // tree (always inside this ZStack) so its underlying NSView/Metal
        // surface is preserved across `terminalVisible` toggles. Branching
        // the ZStack vs a top-level SectionView here used to give SwiftUI
        // two structural identities for Claude, which tore down and
        // recreated the surface on every toggle (visible flicker).
        let ratio = liveDragRatio ?? spaceModel.splitRatio
        let layout: SectionLayout? = spaceModel.terminalVisible
            ? SectionLayout.computeFrames(
                containerSize: containerSize,
                ratio: ratio,
                dock: spaceModel.dockPosition,
                claudeMin: SectionDividerClamper.defaultClaudeMin,
                terminalMin: SectionDividerClamper.defaultTerminalMin,
                dividerThickness: SectionDividerView.thickness
            )
            : nil
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
            .frame(
                width: layout?.claude.width ?? containerSize.width,
                height: layout?.claude.height ?? containerSize.height
            )
            .offset(
                x: layout?.claude.minX ?? 0,
                y: layout?.claude.minY ?? 0
            )

            if let layout {
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
        }
        .frame(width: containerSize.width, height: containerSize.height, alignment: .topLeading)
    }
}
