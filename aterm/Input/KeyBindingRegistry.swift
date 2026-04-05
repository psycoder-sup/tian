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

    func matches(event: NSEvent) -> Bool {
        let eventFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // For arrow keys, flags include .numericPad and .function — use .contains()
        guard eventFlags.contains(modifiers) else { return false }
        // Strip out numericPad and function for non-arrow comparisons
        let extraFlags = eventFlags.subtracting(modifiers).subtracting([.numericPad, .function])
        if !extraFlags.isEmpty { return false }

        if let keyCode {
            return event.keyCode == keyCode
        }
        if let characters {
            return event.charactersIgnoringModifiers?.lowercased() == characters
        }
        return false
    }
}

struct KeyBindingRegistry {
    private var bindings: [KeyAction: [KeyBinding]] = [:]

    static let shared = KeyBindingRegistry.defaults()

    /// Look up which action an event maps to, if any.
    func action(for event: NSEvent) -> KeyAction? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Check Cmd+digit (special case: multiple actions share similar modifiers)
        if flags == [.command],
           let chars = event.charactersIgnoringModifiers,
           let digit = Int(chars), digit >= 0, digit <= 9 {
            return digit == 0 ? .focusSidebar : .goToTab(digit)
        }

        for (action, actionBindings) in bindings {
            for binding in actionBindings {
                if binding.matches(event: event) {
                    return action
                }
            }
        }
        return nil
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
        // Cmd+Shift+Right (keyCode 124) / Cmd+Shift+Left (keyCode 123)
        registry.bindings[.nextSpace] = [KeyBinding(
            characters: nil, keyCode: 124, modifiers: [.command, .shift])]
        registry.bindings[.previousSpace] = [KeyBinding(
            characters: nil, keyCode: 123, modifiers: [.command, .shift])]
        registry.bindings[.newSpace] = [KeyBinding(
            characters: "t", keyCode: nil, modifiers: [.command, .shift])]

        // Workspace operations
        registry.bindings[.newWorkspace] = [KeyBinding(
            characters: "n", keyCode: nil, modifiers: [.command, .shift])]
        registry.bindings[.closeWorkspace] = [KeyBinding(
            characters: nil, keyCode: 51, modifiers: [.command, .shift])]  // 51 = backspace

        // Sidebar
        registry.bindings[.toggleSidebar] = [
            KeyBinding(characters: "s", keyCode: nil, modifiers: [.command, .shift]),
            KeyBinding(characters: "w", keyCode: nil, modifiers: [.command, .shift]),
        ]

        // Debug
        registry.bindings[.toggleDebugOverlay] = [KeyBinding(
            characters: "p", keyCode: nil, modifiers: [.command, .shift])]

        return registry
    }
}
