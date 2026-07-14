import Testing
import Foundation
@testable import tian

@MainActor
struct TianSettingsTests {
    /// A fresh, isolated UserDefaults suite so tests never touch `.standard`.
    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "TianSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultsToBareClaudeWhenUnset() {
        let settings = TianSettings(defaults: makeIsolatedDefaults())
        #expect(settings.claudeCommand == "claude")
        #expect(settings.effectiveClaudeCommand == "claude")
    }

    @Test func blankCommandFallsBackToDefault() {
        let settings = TianSettings(defaults: makeIsolatedDefaults())
        settings.claudeCommand = ""
        #expect(settings.effectiveClaudeCommand == "claude")

        settings.claudeCommand = "   \n\t  "
        #expect(settings.effectiveClaudeCommand == "claude")
    }

    @Test func effectiveCommandTrimsWhitespace() {
        let settings = TianSettings(defaults: makeIsolatedDefaults())
        settings.claudeCommand = "  claude --chrome  "
        #expect(settings.effectiveClaudeCommand == "claude --chrome")
    }

    @Test func commandPersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let first = TianSettings(defaults: defaults)
        first.claudeCommand = "headroom wrap claude"

        let second = TianSettings(defaults: defaults)
        #expect(second.claudeCommand == "headroom wrap claude")
        #expect(second.effectiveClaudeCommand == "headroom wrap claude")
    }

    // MARK: - Ghostty overrides

    @Test func ghosttyOverridesAreEmptyByDefault() {
        let settings = TianSettings(defaults: makeIsolatedDefaults())
        #expect(settings.optionAsAlt == .default)
        #expect(settings.ghosttyConfigOverrides.isEmpty)
        #expect(settings.ghosttyOverrideText.isEmpty)
    }

    @Test func ghosttyOverridesPersistAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let first = TianSettings(defaults: defaults)
        first.optionAsAlt = .alt
        first.ghosttyConfigOverrides = "font-size = 14"

        let second = TianSettings(defaults: defaults)
        #expect(second.optionAsAlt == .alt)
        #expect(second.ghosttyConfigOverrides == "font-size = 14")
        #expect(second.ghosttyOverrideText == "macos-option-as-alt = true\nfont-size = 14\n")
    }

    @Test func unknownPersistedOptionFallsBackToDefault() {
        let defaults = makeIsolatedDefaults()
        defaults.set("bogus", forKey: "ghosttyOptionAsAlt")

        let settings = TianSettings(defaults: defaults)
        #expect(settings.optionAsAlt == .default)
    }
}
