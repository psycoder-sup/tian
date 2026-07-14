import Testing
import Foundation
@testable import tian

/// Feeds tian's rendered override file to the real Ghostty config parser and
/// reads the value back through `ghostty_config_get` — so these cover what the
/// unit tests can't: that Ghostty *accepts* the line we emit, and that loading
/// tian's file last actually beats the user's own `~/.config/ghostty/config`.
@MainActor
struct GhosttyConfigLoadOrderTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostty-overrides-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Builds a config the way `GhosttyApp.buildConfig` does — user config
    /// first, tian's overrides last — and returns `macos-option-as-alt` as
    /// Ghostty parsed it (`nil` when the key was never set).
    private func optionAsAlt(userConfig: String, overrides: String) throws -> String? {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let userURL = dir.appendingPathComponent("user.config")
        let overrideURL = dir.appendingPathComponent("tian-overrides.config")
        try userConfig.write(to: userURL, atomically: true, encoding: .utf8)
        try overrides.write(to: overrideURL, atomically: true, encoding: .utf8)

        let config = try #require(ghostty_config_new())
        defer { ghostty_config_free(config) }
        userURL.path.withCString { ghostty_config_load_file(config, $0) }
        overrideURL.path.withCString { ghostty_config_load_file(config, $0) }
        ghostty_config_finalize(config)

        var value: UnsafePointer<CChar>?
        let key = "macos-option-as-alt"
        let found = withUnsafeMutablePointer(to: &value) { ptr in
            ghostty_config_get(config, ptr, key, UInt(key.count))
        }
        guard found, let value else { return nil }
        return String(cString: value)
    }

    /// The whole point of the feature: what the user picks in tian's Settings
    /// beats the same key in their own Ghostty config.
    @Test func tianOverrideBeatsUserGhosttyConfig() throws {
        let parsed = try optionAsAlt(
            userConfig: "macos-option-as-alt = false\n",
            overrides: GhosttyConfigOverrides.render(optionAsAlt: .alt, rawOverrides: "")
        )
        #expect(parsed == "true")
    }

    /// "Default" writes no line, so the user's own Ghostty config still wins —
    /// tian never silently hijacks a key the user didn't set here.
    @Test func defaultLeavesUserGhosttyConfigInCharge() throws {
        let parsed = try optionAsAlt(
            userConfig: "macos-option-as-alt = right\n",
            overrides: GhosttyConfigOverrides.render(optionAsAlt: .default, rawOverrides: "")
        )
        #expect(parsed == "right")
    }

    /// With nothing set anywhere the key stays unset, leaving Ghostty's own
    /// per-keyboard-layout default in place.
    @Test func unsetEverywhereStaysUnset() throws {
        let parsed = try optionAsAlt(
            userConfig: "",
            overrides: GhosttyConfigOverrides.render(optionAsAlt: .default, rawOverrides: "")
        )
        #expect(parsed == nil)
    }

    /// A free-form line in the advanced box reaches Ghostty verbatim.
    @Test func rawOverrideLineIsParsed() throws {
        let parsed = try optionAsAlt(
            userConfig: "",
            overrides: GhosttyConfigOverrides.render(
                optionAsAlt: .default,
                rawOverrides: "macos-option-as-alt = left"
            )
        )
        #expect(parsed == "left")
    }

    /// A typo in the advanced box produces a Ghostty diagnostic — which the
    /// Settings window shows — instead of silently doing nothing.
    @Test func badOverrideLineProducesDiagnostic() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("tian-overrides.config")
        try "definitely-not-a-key = 1\n".write(to: url, atomically: true, encoding: .utf8)

        let config = try #require(ghostty_config_new())
        defer { ghostty_config_free(config) }
        url.path.withCString { ghostty_config_load_file(config, $0) }
        ghostty_config_finalize(config)

        #expect(ghostty_config_diagnostics_count(config) > 0)
    }
}
