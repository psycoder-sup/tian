import CoreGraphics
import Foundation

/// Computes Claude / divider / Terminal frames for the Space's section region.
///
/// Used by `SpaceContentView` for layout geometry and by
/// `SpaceLevelSplitNavigation` fixtures so tests track the same constants.
struct SectionLayout: Equatable {
    let claude: CGRect
    let terminal: CGRect
    let divider: CGRect

    /// Pure layout calculation — no side effects. Clamps the ratio via
    /// `SectionDividerClamper` so the returned frames always respect the
    /// per-section pixel minimums.
    static func computeFrames(
        containerSize: CGSize,
        ratio: Double,
        dock: DockPosition,
        claudeMin: CGFloat,
        terminalMin: CGFloat,
        dividerThickness: CGFloat
    ) -> SectionLayout {
        let axis: CGFloat
        switch dock {
        case .right:  axis = containerSize.width
        case .bottom: axis = containerSize.height
        }

        let clamper = SectionDividerClamper(
            containerAxis: axis,
            claudeMin: claudeMin,
            terminalMin: terminalMin
        )
        let clampedRatio = clamper.clampRatio(proposed: ratio, dock: dock)

        switch dock {
        case .right:
            let available = Swift.max(containerSize.width - dividerThickness, 0)
            let claudeW = available * CGFloat(clampedRatio)
            let terminalW = available - claudeW
            let claude = CGRect(x: 0, y: 0, width: claudeW, height: containerSize.height)
            let divider = CGRect(
                x: claudeW, y: 0,
                width: dividerThickness, height: containerSize.height
            )
            let terminal = CGRect(
                x: claudeW + dividerThickness, y: 0,
                width: terminalW, height: containerSize.height
            )
            return SectionLayout(claude: claude, terminal: terminal, divider: divider)

        case .bottom:
            let available = Swift.max(containerSize.height - dividerThickness, 0)
            let claudeH = available * CGFloat(clampedRatio)
            let terminalH = available - claudeH
            let claude = CGRect(x: 0, y: 0, width: containerSize.width, height: claudeH)
            let divider = CGRect(
                x: 0, y: claudeH,
                width: containerSize.width, height: dividerThickness
            )
            let terminal = CGRect(
                x: 0, y: claudeH + dividerThickness,
                width: containerSize.width, height: terminalH
            )
            return SectionLayout(claude: claude, terminal: terminal, divider: divider)
        }
    }
}
