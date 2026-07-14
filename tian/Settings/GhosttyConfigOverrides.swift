import Foundation

/// How the macOS *Option* key is delivered to the terminal — Ghostty's
/// `macos-option-as-alt`. Claude Code (and most TUIs binding `alt+…`) need
/// Option to arrive as *Alt*; the macOS default instead composes Unicode
/// (⌥p → `π`), which swallows the binding.
///
/// `.default` deliberately emits nothing, so Ghostty keeps its own
/// per-keyboard-layout default and any value in the user's
/// `~/.config/ghostty/config` still applies.
enum OptionAsAltSetting: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case alt
    case unicode
    case left
    case right

    var id: String { rawValue }

    /// The `macos-option-as-alt` value, or `nil` when tian should stay out of
    /// the way and let Ghostty's own default (or the user's config) decide.
    var configValue: String? {
        switch self {
        case .default: nil
        case .alt: "true"
        case .unicode: "false"
        case .left: "left"
        case .right: "right"
        }
    }

    var displayName: String {
        switch self {
        case .default: "Default (keyboard layout)"
        case .alt: "Alt / Meta (for alt+… bindings)"
        case .unicode: "Unicode input (⌥p → π)"
        case .left: "Left Option only"
        case .right: "Right Option only"
        }
    }
}

/// Renders tian's Settings into a Ghostty config file that is loaded **after**
/// `~/.config/ghostty/config`, so what the user picks in tian's UI wins — while
/// anything left unset emits no line at all and falls through to their own
/// Ghostty config.
///
/// Kept free of `GhosttyApp` and `TianSettings` so `render` stays a pure,
/// directly testable function.
enum GhosttyConfigOverrides {
    /// Renders the override file body. Empty when nothing is overridden, which
    /// loads as a no-op file.
    static func render(optionAsAlt: OptionAsAltSetting, rawOverrides: String) -> String {
        var lines: [String] = []
        if let value = optionAsAlt.configValue {
            lines.append("macos-option-as-alt = \(value)")
        }
        let raw = rawOverrides.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            lines.append(raw)
        }
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Where the rendered file lives. The debug build uses its own directory so
    /// a running debug app and the release app don't fight over one file —
    /// same split as `FileLogWriter`'s `tian-debug` log directory.
    static let fileURL: URL = {
        #if DEBUG
        let folder = "tian-debug"
        #else
        let folder = "tian"
        #endif
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("ghostty-overrides.config")
    }()

    /// Writes the body to `fileURL`, creating the directory on first use.
    /// An empty body still writes (an empty file), so clearing every override
    /// actually clears them on the next config build.
    static func write(_ body: String) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.ghostty.error("Failed to write ghostty overrides: \(String(describing: error))")
        }
    }
}
