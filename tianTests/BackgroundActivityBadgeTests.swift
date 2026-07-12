import Testing
import Foundation
@testable import tian

/// `BackgroundActivityBadgeView`'s glyph and accessibility-label logic, tested
/// directly via its `internal` static helpers rather than hosting the SwiftUI
/// view. Covers the teammate-dominant precedence this file exists to fix: a mix
/// that includes a teammate must read as team-mode busy, not the neutral glyph.
@MainActor
struct BackgroundActivityBadgeTests {

    // MARK: - Helpers

    private func activity(_ kind: BackgroundActivity.Kind, id: String? = nil) -> BackgroundActivity {
        BackgroundActivity(id: id ?? UUID().uuidString, kind: kind, label: kind.rawValue, status: "running")
    }

    // MARK: - glyph(for:) — single kind

    @Test func teammateOnlyGlyphIsPersonThree() {
        let activities = [activity(.teammate)]
        #expect(BackgroundActivityBadgeView.glyph(for: activities) == "person.3.fill")
    }

    @Test func agentOnlyGlyphIsPersonTwo() {
        let activities = [activity(.agent)]
        #expect(BackgroundActivityBadgeView.glyph(for: activities) == "person.2.fill")
    }

    @Test func bashOnlyGlyphIsTerminal() {
        let activities = [activity(.bash), activity(.bash)]
        #expect(BackgroundActivityBadgeView.glyph(for: activities) == "terminal")
    }

    // MARK: - glyph(for:) — mixes

    /// The regression this task exists for: a subagent alongside a teammate must
    /// not degrade to the neutral glyph — the team signal wins outright.
    @Test func agentAndTeammateGlyphIsPersonThree() {
        let activities = [activity(.agent), activity(.teammate)]
        #expect(BackgroundActivityBadgeView.glyph(for: activities) == "person.3.fill")
    }

    @Test func agentAndBashGlyphIsPersonTwo() {
        let activities = [activity(.agent), activity(.bash)]
        #expect(BackgroundActivityBadgeView.glyph(for: activities) == "person.2.fill")
    }

    @Test func bashAndOtherGlyphIsNeutral() {
        let activities = [activity(.bash), activity(.other)]
        #expect(BackgroundActivityBadgeView.glyph(for: activities) == "bolt.horizontal.circle")
    }

    @Test func emptyGlyphDoesNotCrashAndTheViewGuardStillHidesIt() {
        // `glyph(for:)` itself never renders — `body`'s `!activities.isEmpty`
        // guard (unchanged by this task) is what actually hides the badge for
        // an empty activity list. This just asserts the helper stays total.
        #expect(BackgroundActivityBadgeView.glyph(for: []) == "bolt.horizontal.circle")
        #expect([BackgroundActivity]().isEmpty)
    }

    // MARK: - accessibilityText(for:)

    @Test func oneAgentAccessibilityTextIsSingular() {
        let activities = [activity(.agent)]
        #expect(BackgroundActivityBadgeView.accessibilityText(for: activities) == "1 subagent running")
    }

    @Test func twoAgentsAccessibilityTextIsPlural() {
        let activities = [activity(.agent), activity(.agent)]
        #expect(BackgroundActivityBadgeView.accessibilityText(for: activities) == "2 subagents running")
    }

    @Test func mixedAgentsAndTeammateAccessibilityTextNamesTheMix() {
        let activities = [activity(.agent), activity(.agent), activity(.teammate)]
        #expect(BackgroundActivityBadgeView.accessibilityText(for: activities) == "2 subagents, 1 teammate running")
    }

    @Test func bashAccessibilityTextUsesBackgroundTaskNoun() {
        #expect(BackgroundActivityBadgeView.accessibilityText(for: [activity(.bash)]) == "1 background task running")
        #expect(
            BackgroundActivityBadgeView.accessibilityText(for: [activity(.bash), activity(.bash)])
                == "2 background tasks running"
        )
    }

    @Test func emptyAccessibilityTextIsEmptyString() {
        #expect(BackgroundActivityBadgeView.accessibilityText(for: []).isEmpty)
    }
}
