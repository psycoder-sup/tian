import CoreGraphics
import Foundation

/// Value-type helper enforcing FR-16 pixel minimums.
///
/// Clamps the Claude/Terminal split ratio so Claude stays ≥ `claudeMin`
/// and reports whether the user dragged past the Terminal minimum so the
/// caller can trigger auto-hide on gesture end.
struct SessionDividerClamper: Equatable {
    static let defaultClaudeMin: CGFloat = 320
    static let defaultTerminalMin: CGFloat = 160

    /// Container extent on the dock axis (width for `.right`, height for `.bottom`).
    let containerAxis: CGFloat
    let claudeMin: CGFloat
    let terminalMin: CGFloat

    init(
        containerAxis: CGFloat,
        claudeMin: CGFloat = SessionDividerClamper.defaultClaudeMin,
        terminalMin: CGFloat = SessionDividerClamper.defaultTerminalMin
    ) {
        self.containerAxis = containerAxis
        self.claudeMin = claudeMin
        self.terminalMin = terminalMin
    }

    /// Clamps `proposed` so Claude stays ≥ `claudeMin`. Also enforces an
    /// upper bound keeping Terminal ≥ `terminalMin` (the auto-hide decision
    /// is made separately in `evaluateDragEnd`). The axis is already encoded
    /// in `containerAxis`, so the math is dock-agnostic.
    func clampRatio(proposed: Double) -> Double {
        guard containerAxis > 0 else { return proposed }

        let minRatio = Double(claudeMin / containerAxis)
        let maxRatio = Double((containerAxis - terminalMin) / containerAxis)

        // If the window is so small both minimums can't be satisfied, prefer
        // respecting the Claude minimum (the pane we always keep visible).
        if minRatio >= maxRatio {
            return Swift.max(Swift.min(proposed, 1.0), minRatio)
        }
        return Swift.min(Swift.max(proposed, minRatio), maxRatio)
    }

    /// On gesture end, returns the final clamped ratio plus whether auto-hide
    /// should fire (proposed ratio would have left Terminal below `terminalMin`).
    func evaluateDragEnd(proposedRatio: Double)
        -> (clamped: Double, shouldHide: Bool) {
        guard containerAxis > 0 else {
            return (proposedRatio, false)
        }
        let terminalExtent = containerAxis * (1.0 - CGFloat(proposedRatio))
        let shouldHide = terminalExtent < terminalMin
        let clamped = clampRatio(proposed: proposedRatio)
        return (clamped, shouldHide)
    }
}
