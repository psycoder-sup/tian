import AppKit

/// Maps KeyActions to keyboard shortcut definitions.
/// In M3, populated with hardcoded defaults. In M6, loaded from TOML configuration.
struct KeyBinding: Equatable {
    /// Characters to match (lowercased, from `charactersIgnoringModifiers`).
    /// Nil means match by keyCode only.
    let characters: String?
    /// Key code to match. Nil means match by characters only.
    let keyCode: UInt16?
    /// Required modifier flags (device-independent).
    let modifiers: NSEvent.ModifierFlags
}

/// Hashable lookup key for character-based bindings (e.g. Cmd+T).
/// `modifiers` is stored as the raw `UInt` because `NSEvent.ModifierFlags`
/// (an `OptionSet`) does not synthesise `Hashable`.
private struct CharacterChord: Hashable {
    let characters: String
    let modifiers: UInt

    init(characters: String, modifiers: NSEvent.ModifierFlags) {
        self.characters = characters
        self.modifiers = modifiers.rawValue
    }
}

/// Hashable lookup key for keyCode-based bindings (e.g. arrow keys).
private struct KeyCodeChord: Hashable {
    let keyCode: UInt16
    let modifiers: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.rawValue
    }
}

/// Modifier flags considered significant for chord matching. Other flags
/// (`.numericPad`, `.function`, etc.) carried by `NSEvent` are stripped at
/// both seed and lookup time.
private let chordModifierMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

struct KeyBindingRegistry {
    private var bindings: [KeyAction: [KeyBinding]] = [:]

    /// O(1) lookup index for character-based bindings, rebuilt by `rebuildIndex()`.
    private var bindingsByCharacters: [CharacterChord: KeyAction] = [:]
    /// O(1) lookup index for keyCode-based bindings, rebuilt by `rebuildIndex()`.
    private var bindingsByKeyCode: [KeyCodeChord: KeyAction] = [:]

    static let shared = KeyBindingRegistry.defaults()

    /// Look up which action an event maps to, if any.
    func action(for event: NSEvent) -> KeyAction? {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection(chordModifierMask)

        // Cmd+digit special case (must come before the dict lookup so it shadows
        // any hypothetical future binding on Cmd+0..9). `.goToTab(n)` carries an
        // associated value and cannot be precomputed in a chord dict.
        if modifiers == [.command],
           let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), digit >= 0, digit <= 9 {
            return digit == 0 ? .focusSidebar : .goToTab(digit)
        }

        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           let action = bindingsByCharacters[CharacterChord(characters: chars, modifiers: modifiers)] {
            return action
        }
        return bindingsByKeyCode[KeyCodeChord(keyCode: event.keyCode, modifiers: modifiers)]
    }

    /// Rebuilds `bindingsByCharacters` and `bindingsByKeyCode` from `bindings`.
    /// Must be called after every mutation to `bindings`.
    private mutating func rebuildIndex() {
        bindingsByCharacters.removeAll(keepingCapacity: true)
        bindingsByKeyCode.removeAll(keepingCapacity: true)
        for (action, list) in bindings {
            for binding in list {
                let mods = binding.modifiers.intersection(chordModifierMask)
                if let chars = binding.characters {
                    bindingsByCharacters[CharacterChord(characters: chars, modifiers: mods)] = action
                } else if let code = binding.keyCode {
                    bindingsByKeyCode[KeyCodeChord(keyCode: code, modifiers: mods)] = action
                }
            }
        }
    }

    // MARK: - Defaults

    private static func defaults() -> KeyBindingRegistry {
        var registry = KeyBindingRegistry()

        // Tab navigation
        registry.bindings[.nextTab] = [KeyBinding(
            characters: "]", keyCode: nil, modifiers: [.command, .shift])]
        registry.bindings[.previousTab] = [KeyBinding(
            characters: "[", keyCode: nil, modifiers: [.command, .shift])]
        registry.bindings[.newTab] = [KeyBinding(
            characters: "t", keyCode: nil, modifiers: [.command])]

        // Space navigation
        registry.bindings[.newSpace] = [KeyBinding(
            characters: "t", keyCode: nil, modifiers: [.command, .shift])]

        // Space navigation (across workspaces)
        // Cmd+Shift+Right (keyCode 124) / Cmd+Shift+Left (keyCode 123)
        registry.bindings[.nextSpace] = [KeyBinding(
            characters: nil, keyCode: 124, modifiers: [.command, .shift])]
        registry.bindings[.previousSpace] = [KeyBinding(
            characters: nil, keyCode: 123, modifiers: [.command, .shift])]
        registry.bindings[.newWorkspace] = [KeyBinding(
            characters: "n", keyCode: nil, modifiers: [.command, .shift])]
        registry.bindings[.closeWorkspace] = [KeyBinding(
            characters: nil, keyCode: 51, modifiers: [.command, .shift])]  // 51 = backspace

        // Sidebar
        registry.bindings[.toggleSidebar] = [
            KeyBinding(characters: "s", keyCode: nil, modifiers: [.command, .shift]),
            KeyBinding(characters: "w", keyCode: nil, modifiers: [.command, .shift]),
        ]

        // Sections (space-sections feature)
        // `` Ctrl+` `` — keyCode 50 is the backtick key on US layouts.
        registry.bindings[.toggleTerminalSection] = [KeyBinding(
            characters: nil, keyCode: 50, modifiers: [.control])]
        // `` Cmd+Shift+` ``
        registry.bindings[.cycleSectionFocus] = [KeyBinding(
            characters: nil, keyCode: 50, modifiers: [.command, .shift])]

        // Debug
        registry.bindings[.toggleDebugOverlay] = [KeyBinding(
            characters: "p", keyCode: nil, modifiers: [.command, .shift])]

        registry.rebuildIndex()
        return registry
    }
}
