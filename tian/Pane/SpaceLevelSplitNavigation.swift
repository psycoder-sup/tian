import CoreGraphics
import Foundation

/// Cross-section directional navigation (FR-19).
///
/// Computes the combined pane-frame dict for both sections' active tabs
/// (scaled/offset into their respective section frames via `SectionLayout`)
/// and delegates to `SplitNavigation.neighbor` to find the next pane.
///
/// Returns the target pane id together with its section kind so the caller
/// can update `SpaceModel.focusedSectionKind` when navigation crosses a
/// divider.
@MainActor
struct SpaceLevelSplitNavigation {
    struct Target: Equatable {
        let paneID: UUID
        let sectionKind: SectionKind
    }

    let space: SpaceModel
    let containerSize: CGSize

    func neighbor(
        from sourcePaneID: UUID,
        in sourceKind: SectionKind,
        direction: NavigationDirection
    ) -> Target? {
        let (frames, kindByPaneID) = buildFrames()
        guard let targetID = SplitNavigation.neighbor(
            of: sourcePaneID,
            direction: direction,
            in: frames
        ) else {
            _ = sourceKind  // keep parameter meaningful even when unused here
            return nil
        }
        guard let kind = kindByPaneID[targetID] else { return nil }
        return Target(paneID: targetID, sectionKind: kind)
    }

    // MARK: - Private

    private func buildFrames() -> (frames: [UUID: CGRect], kindByPaneID: [UUID: SectionKind]) {
        var frames: [UUID: CGRect] = [:]
        var kinds: [UUID: SectionKind] = [:]

        let sectionLayout = SectionLayout.computeFrames(
            containerSize: containerSize,
            ratio: space.splitRatio,
            dock: space.dockPosition,
            claudeMin: SectionDividerClamper.defaultClaudeMin,
            terminalMin: SectionDividerClamper.defaultTerminalMin,
            dividerThickness: SectionDividerView.thickness
        )

        collectFrames(
            from: space.claudeSection,
            sectionFrame: sectionLayout.claude,
            kind: .claude,
            into: &frames,
            kinds: &kinds
        )

        // Skip Terminal when it's hidden — no visible panes to navigate into.
        if space.terminalVisible {
            collectFrames(
                from: space.terminalSection,
                sectionFrame: sectionLayout.terminal,
                kind: .terminal,
                into: &frames,
                kinds: &kinds
            )
        }

        return (frames, kinds)
    }

    private func collectFrames(
        from section: SectionModel,
        sectionFrame: CGRect,
        kind: SectionKind,
        into frames: inout [UUID: CGRect],
        kinds: inout [UUID: SectionKind]
    ) {
        guard sectionFrame.width > 0, sectionFrame.height > 0 else { return }
        guard let activeTab = section.activeTab else { return }

        let layoutResult = SplitLayout.layout(
            node: activeTab.paneViewModel.splitTree.root,
            in: CGRect(origin: .zero, size: sectionFrame.size)
        )
        for (paneID, localRect) in layoutResult.paneFrames {
            let globalRect = CGRect(
                x: sectionFrame.minX + localRect.minX,
                y: sectionFrame.minY + localRect.minY,
                width: localRect.width,
                height: localRect.height
            )
            frames[paneID] = globalRect
            kinds[paneID] = kind
        }
    }
}
