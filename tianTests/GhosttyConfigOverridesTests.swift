import Testing
import Foundation
@testable import tian

struct GhosttyConfigOverridesTests {
    @Test func rendersNothingWhenNothingOverridden() {
        let body = GhosttyConfigOverrides.render(optionAsAlt: .default, rawOverrides: "")
        #expect(body.isEmpty)
    }

    @Test func defaultOptionEmitsNoLineSoGhosttyConfigStillWins() {
        let body = GhosttyConfigOverrides.render(optionAsAlt: .default, rawOverrides: "font-size = 14")
        #expect(!body.contains("macos-option-as-alt"))
        #expect(body.contains("font-size = 14"))
    }

    @Test func optionAsAltRendersGhosttyKey() {
        #expect(
            GhosttyConfigOverrides.render(optionAsAlt: .alt, rawOverrides: "")
                .contains("macos-option-as-alt = true")
        )
        #expect(
            GhosttyConfigOverrides.render(optionAsAlt: .unicode, rawOverrides: "")
                .contains("macos-option-as-alt = false")
        )
        #expect(
            GhosttyConfigOverrides.render(optionAsAlt: .left, rawOverrides: "")
                .contains("macos-option-as-alt = left")
        )
        #expect(
            GhosttyConfigOverrides.render(optionAsAlt: .right, rawOverrides: "")
                .contains("macos-option-as-alt = right")
        )
    }

    /// Raw lines come last so a user who writes their own `macos-option-as-alt`
    /// in the box beats the picker rather than being silently ignored.
    @Test func rawOverridesFollowGeneratedLines() {
        let body = GhosttyConfigOverrides.render(
            optionAsAlt: .alt,
            rawOverrides: "font-size = 14\nkeybind = alt+p=text:\\x1bp"
        )
        let lines = body.split(separator: "\n").map(String.init)
        #expect(lines == [
            "macos-option-as-alt = true",
            "font-size = 14",
            "keybind = alt+p=text:\\x1bp",
        ])
    }

    @Test func whitespaceOnlyRawOverridesAreDropped() {
        let body = GhosttyConfigOverrides.render(optionAsAlt: .alt, rawOverrides: "  \n\t ")
        #expect(body == "macos-option-as-alt = true\n")
    }

    @Test func writeRoundTripsThroughTheFile() throws {
        let original = try? String(contentsOf: GhosttyConfigOverrides.fileURL, encoding: .utf8)
        defer { GhosttyConfigOverrides.write(original ?? "") }

        GhosttyConfigOverrides.write("macos-option-as-alt = true\n")
        let written = try String(contentsOf: GhosttyConfigOverrides.fileURL, encoding: .utf8)
        #expect(written == "macos-option-as-alt = true\n")
    }
}
