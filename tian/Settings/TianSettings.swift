import Foundation
import Observation

/// App-wide, user-editable preferences backed by `UserDefaults`.
///
/// Currently holds a single setting: the command a fresh Claude pane
/// auto-runs (see `SectionSpawner.claudeAutostartCommand`). The shell
/// integration appends `; builtin exit`, so this value is just the command
/// word(s) — e.g. `claude`, `claude --chrome`, or `headroom wrap claude`.
@MainActor
@Observable
final class TianSettings {
    /// Shared instance read by non-UI code (`SectionSpawner`). The settings
    /// UI binds to the same instance so edits take effect immediately.
    static let shared = TianSettings()

    /// The built-in default used when the user hasn't set a command (or has
    /// cleared it). Keeping this the bare `claude` literal preserves the
    /// historical behaviour for existing users.
    static let defaultClaudeCommand = "claude"

    /// Quick-launch presets shown in the Claude "+" button's right-click menu
    /// ("Run Custom Claude"). One-off overrides — they do not change the saved
    /// default above.
    static let claudeCommandPresets = ["claude --chrome", "headroom wrap claude"]

    private enum Keys {
        static let claudeCommand = "claudeCommand"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// The raw command string as edited by the user. Persisted on every
    /// mutation so the value survives relaunches without an explicit save.
    var claudeCommand: String {
        didSet { defaults.set(claudeCommand, forKey: Keys.claudeCommand) }
    }

    /// The command actually handed to the autostart path. Whitespace is
    /// trimmed and a blank value falls back to `defaultClaudeCommand`, so
    /// clearing the field never leaves a Claude pane with nothing to run.
    var effectiveClaudeCommand: String {
        let trimmed = claudeCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultClaudeCommand : trimmed
    }

    /// - Parameter defaults: the backing store. Defaults to `.standard`; tests
    ///   inject an isolated suite so they don't pollute the real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.claudeCommand = defaults.string(forKey: Keys.claudeCommand) ?? Self.defaultClaudeCommand
    }
}
