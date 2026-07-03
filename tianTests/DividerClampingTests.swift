import Testing
import CoreGraphics
@testable import tian

@MainActor
struct DividerClampingTests {

    // FR-16 — hard stop at Claude min
    @Test func dragBelowClaudeMinimumIsClamped() {
        let helper = SessionDividerClamper(containerAxis: 800, claudeMin: 320, terminalMin: 160)
        let clamped = helper.clampRatio(proposed: 0.1)
        // Claude ≥ 320pt of 800pt => ratio ≥ 0.4
        #expect(clamped >= 0.4 - 0.001)
    }

    // FR-16 — auto-hide when past Terminal min on release
    @Test func dragPastTerminalMinimumSignalsAutoHide() {
        let helper = SessionDividerClamper(containerAxis: 800, claudeMin: 320, terminalMin: 160)
        let (clamped, shouldHide) = helper.evaluateDragEnd(proposedRatio: 0.95)
        #expect(shouldHide == true)
        #expect(clamped >= 0.4 - 0.001)
    }
}
