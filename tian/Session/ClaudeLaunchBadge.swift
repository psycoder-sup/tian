import Foundation

/// A small per-variant indicator shown on a session so the launched command
/// (`claude --chrome`, `headroom wrap claude`, …) is distinguishable at a glance.
struct ClaudeLaunchBadge: Equatable {
    /// SF Symbol name rendered in the session's leading slot.
    let symbol: String
    /// Full launch command, surfaced as the session's tooltip / accessibility text.
    let command: String

    /// Maps a launch command to its badge, or `nil` when the command is empty or
    /// the bare default (`TianSettings.defaultClaudeCommand`) — plain `claude`
    /// sessions stay unmarked. Known variants get a recognizable glyph; any other
    /// custom command gets a generic one.
    @MainActor
    static func forCommand(_ command: String) -> ClaudeLaunchBadge? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != TianSettings.defaultClaudeCommand else { return nil }

        let lower = trimmed.lowercased()
        let symbol: String
        if lower.contains("--chrome") {
            symbol = "globe"
        } else if lower.contains("headroom") {
            symbol = "rectangle.compress.vertical"
        } else {
            symbol = "wand.and.stars"
        }
        return ClaudeLaunchBadge(symbol: symbol, command: trimmed)
    }
}
