import CoreGraphics
import Foundation

/// Cross-area directional navigation between a Session's Claude pane and its
/// terminal panel (FR-19).
///
/// Builds the combined pane-frame dict for both areas — the Claude pane as a
/// single frame filling its region, and the terminal panel's split tree laid
/// out within its region (both derived from `SessionLayout`) — and delegates
/// to `SplitNavigation.neighbor` to find the next pane.
///
/// Returns the target pane id together with its `PaneKind` so `Session` can
/// update `focusedArea` when navigation crosses the divider.
@MainActor
struct SessionSplitNavigation {
    struct Target: Equatable {
        let paneID: UUID
        let kind: PaneKind
    }

    let session: Session
    let containerSize: CGSize

    func neighbor(from sourcePaneID: UUID, direction: NavigationDirection) -> Target? {
        let (frames, kindByPaneID) = buildFrames()
        guard let targetID = SplitNavigation.neighbor(
            of: sourcePaneID,
            direction: direction,
            in: frames
        ) else {
            return nil
        }
        guard let kind = kindByPaneID[targetID] else { return nil }
        return Target(paneID: targetID, kind: kind)
    }

    // MARK: - Private

    private func buildFrames() -> (frames: [UUID: CGRect], kindByPaneID: [UUID: PaneKind]) {
        var frames: [UUID: CGRect] = [:]
        var kinds: [UUID: PaneKind] = [:]

        // The terminal panel only participates when it's visible and present —
        // matching the layout `SessionContentView` renders.
        let showTerminal = session.terminalVisible && session.terminalPanel != nil
        let layout: SessionLayout? = showTerminal
            ? SessionLayout.computeFrames(
                containerSize: containerSize,
                ratio: session.splitRatio,
                dock: session.dockPosition,
                claudeMin: SessionDividerClamper.defaultClaudeMin,
                terminalMin: SessionDividerClamper.defaultTerminalMin,
                dividerThickness: SessionDividerView.thickness
            )
            : nil

        // Claude — a single leaf filling its region (the full container when the
        // terminal panel is hidden, so Claude expands to fill).
        if session.hasLiveClaudePane, let claudePaneID = session.claudePaneID {
            frames[claudePaneID] = layout?.claude ?? CGRect(origin: .zero, size: containerSize)
            kinds[claudePaneID] = .claude
        }

        // Terminal — its split tree laid out within the terminal region.
        if let layout, let terminalPanel = session.terminalPanel {
            collectFrames(
                root: terminalPanel.splitTree.root,
                regionFrame: layout.terminal,
                kind: .terminal,
                into: &frames,
                kinds: &kinds
            )
        }

        return (frames, kinds)
    }

    private func collectFrames(
        root: PaneNode,
        regionFrame: CGRect,
        kind: PaneKind,
        into frames: inout [UUID: CGRect],
        kinds: inout [UUID: PaneKind]
    ) {
        guard regionFrame.width > 0, regionFrame.height > 0 else { return }

        let layoutResult = SplitLayout.layout(
            node: root,
            in: CGRect(origin: .zero, size: regionFrame.size)
        )
        for (paneID, localRect) in layoutResult.paneFrames {
            let globalRect = CGRect(
                x: regionFrame.minX + localRect.minX,
                y: regionFrame.minY + localRect.minY,
                width: localRect.width,
                height: localRect.height
            )
            frames[paneID] = globalRect
            kinds[paneID] = kind
        }
    }
}
