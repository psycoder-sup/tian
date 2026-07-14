import Foundation
import Observation

/// App-wide, user-editable preferences backed by `UserDefaults`.
///
/// Holds the command a fresh Claude pane auto-runs (see
/// `PaneSpawner.claudeAutostartCommand`; the shell integration appends
/// `; builtin exit`, so the value is just the command word(s) — e.g. `claude`,
/// `claude --chrome`), the worktree-engine choice, and tian's Ghostty
/// preference overrides (`GhosttyConfigOverrides`).
@MainActor
@Observable
final class TianSettings {
    /// Shared instance read by non-UI code (`PaneSpawner`). The settings
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
        static let useClaudeWorktreeEngine = "useClaudeWorktreeEngine"
        static let optionAsAlt = "ghosttyOptionAsAlt"
        static let ghosttyConfigOverrides = "ghosttyConfigOverrides"
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

    /// When `true`, checking "Create worktree" in the new-space dialog routes
    /// to the `claude --worktree` engine: Claude creates and names the worktree
    /// (`<repo>/.claude/worktrees/<name>`) and tian detects the result. When
    /// `false` (the default), tian's own `git worktree add` engine runs and the
    /// user names the branch. Persisted on every mutation so it survives relaunches.
    var useClaudeWorktreeEngine: Bool {
        didSet { defaults.set(useClaudeWorktreeEngine, forKey: Keys.useClaudeWorktreeEngine) }
    }

    // MARK: - Ghostty overrides

    /// How the *Option* key reaches the terminal (`macos-option-as-alt`).
    /// `.default` writes no line, leaving Ghostty's own default — and the
    /// user's `~/.config/ghostty/config` — in charge.
    var optionAsAlt: OptionAsAltSetting {
        didSet { defaults.set(optionAsAlt.rawValue, forKey: Keys.optionAsAlt) }
    }

    /// Free-form Ghostty config lines (`key = value`, one per line) applied on
    /// top of the user's own Ghostty config. The escape hatch for any
    /// preference tian doesn't expose as a dedicated control.
    var ghosttyConfigOverrides: String {
        didSet { defaults.set(ghosttyConfigOverrides, forKey: Keys.ghosttyConfigOverrides) }
    }

    /// The body of the Ghostty config file tian loads last. Empty when nothing
    /// is overridden.
    var ghosttyOverrideText: String {
        GhosttyConfigOverrides.render(
            optionAsAlt: optionAsAlt,
            rawOverrides: ghosttyConfigOverrides
        )
    }

    /// - Parameter defaults: the backing store. Defaults to `.standard`; tests
    ///   inject an isolated suite so they don't pollute the real preferences.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.claudeCommand = defaults.string(forKey: Keys.claudeCommand) ?? Self.defaultClaudeCommand
        self.useClaudeWorktreeEngine = defaults.bool(forKey: Keys.useClaudeWorktreeEngine)
        // An unknown/corrupt persisted value falls back to `.default` rather
        // than trapping — the setting is cosmetic enough to recover silently.
        self.optionAsAlt = defaults.string(forKey: Keys.optionAsAlt)
            .flatMap(OptionAsAltSetting.init(rawValue:)) ?? .default
        self.ghosttyConfigOverrides = defaults.string(forKey: Keys.ghosttyConfigOverrides) ?? ""
    }
}
