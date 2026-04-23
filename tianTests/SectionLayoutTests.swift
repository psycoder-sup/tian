import Testing
import CoreGraphics
@testable import tian

struct SectionLayoutTests {

    // FR-17 — hidden Terminal section not exercised here (handled in SpaceContentView),
    // but the layout helper always produces non-negative frames.
    @Test func rightDockedLayoutGeometry() {
        let layout = SectionLayout.computeFrames(
            containerSize: CGSize(width: 1000, height: 600),
            ratio: 0.7,
            dock: .right,
            claudeMin: 320, terminalMin: 160,
            dividerThickness: 6
        )
        // Claude gets 70% of (width - divider)
        let expectedClaudeWidth: CGFloat = (1000 - 6) * 0.7
        #expect(abs(layout.claude.width - expectedClaudeWidth) < 0.5)
        #expect(layout.claude.height == 600)
        #expect(layout.divider.width == 6)
        #expect(layout.divider.height == 600)
        #expect(layout.terminal.width > 0)
        #expect(layout.terminal.height == 600)
    }

    @Test func bottomDockedLayoutGeometry() {
        let layout = SectionLayout.computeFrames(
            containerSize: CGSize(width: 800, height: 600),
            ratio: 0.6,
            dock: .bottom,
            claudeMin: 320, terminalMin: 160,
            dividerThickness: 6
        )
        #expect(layout.claude.width == 800)
        #expect(layout.divider.height == 6)
        #expect(layout.terminal.width == 800)
        #expect(abs((layout.claude.height + layout.divider.height + layout.terminal.height) - 600) < 0.5)
    }
}
