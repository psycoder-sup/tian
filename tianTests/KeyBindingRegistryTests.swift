import Testing
import AppKit
@testable import tian

@MainActor
struct KeyBindingRegistryTests {

    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    @Test func charactersBindingResolves() {
        // Cmd+N creates a session (Cmd+T is intentionally unbound).
        let event = keyEvent(keyCode: 45 /* N */, characters: "n", modifiers: [.command])
        #expect(KeyBindingRegistry.shared.action(for: event) == .newSession)
    }

    @Test func cmdRMapsToRenameSession() {
        // Cmd+R enters inline-rename on the active session's sidebar row.
        let event = keyEvent(keyCode: 15 /* R */, characters: "r", modifiers: [.command])
        #expect(KeyBindingRegistry.shared.action(for: event) == .renameSession)
    }

    @Test func nonLatinImeResolvesByPhysicalKey() {
        // Under a Korean (or other non-Latin) IME, the N key reports a composed
        // character for charactersIgnoringModifiers; the binding must still
        // resolve via the ASCII-capable layout translation of the keycode.
        // Guard on the host layout mapping keyCode 45 -> "n" (true for US/ABC
        // and other QWERTY-derived ASCII-capable layouts) to avoid false
        // failures on exotic dev/CI layouts.
        guard KeyboardLayoutTranslator.shared.character(forKeyCode: 45) == "n" else { return }
        let event = keyEvent(keyCode: 45 /* N */, characters: "ㅜ", modifiers: [.command])
        #expect(KeyBindingRegistry.shared.action(for: event) == .newSession)
    }

    @Test func cmdTVariantsAreUnbound() {
        // Cmd+T (no shift) must fall through to the shell, not the tab family
        // that no longer exists.
        let cmdT = keyEvent(keyCode: 17 /* T */, characters: "t", modifiers: [.command])
        #expect(KeyBindingRegistry.shared.action(for: cmdT) == nil)
        // Cmd+Shift+T — the former new-session binding — is now unbound too;
        // new session moved to Cmd+N.
        let cmdShiftT = keyEvent(keyCode: 17 /* T */, characters: "t", modifiers: [.command, .shift])
        #expect(KeyBindingRegistry.shared.action(for: cmdShiftT) == nil)
    }

    @Test func keyCodeBindingResolves() {
        let event = keyEvent(keyCode: 125 /* Down */, characters: "\u{F701}", modifiers: [.command, .shift])
        #expect(KeyBindingRegistry.shared.action(for: event) == .nextSession)
    }

    @Test func cmdDigitSpecialCase() {
        let event = keyEvent(keyCode: 18 /* 1 */, characters: "1", modifiers: [.command])
        #expect(KeyBindingRegistry.shared.action(for: event) == .goToSession(1))
    }

    @Test func cmdZeroFocusesSidebar() {
        let event = keyEvent(keyCode: 29 /* 0 */, characters: "0", modifiers: [.command])
        #expect(KeyBindingRegistry.shared.action(for: event) == .focusSidebar)
    }

    @Test func multipleBindingsResolveSameAction() {
        let s = keyEvent(keyCode: 1, characters: "s", modifiers: [.command, .shift])
        let w = keyEvent(keyCode: 13, characters: "w", modifiers: [.command, .shift])
        #expect(KeyBindingRegistry.shared.action(for: s) == .toggleSidebar)
        #expect(KeyBindingRegistry.shared.action(for: w) == .toggleSidebar)
    }

    @Test func unboundChordReturnsNil() {
        let event = keyEvent(keyCode: 6 /* Z */, characters: "z", modifiers: [.command, .option])
        #expect(KeyBindingRegistry.shared.action(for: event) == nil)
    }

    @Test func numericPadFlagDoesNotBlockMatch() {
        // Arrow keys carry .numericPad in event flags; chord matching must tolerate it.
        let modifiers: NSEvent.ModifierFlags = [.command, .shift, .numericPad]
        let event = keyEvent(keyCode: 125, characters: "\u{F701}", modifiers: modifiers)
        #expect(KeyBindingRegistry.shared.action(for: event) == .nextSession)
    }
}

@MainActor
struct KeyBindingRegistryPhase3Tests {

    // FR-09 — Ctrl+` dispatches `.toggleTerminalPanel`.
    @Test func ctrlBacktickMapsToToggleTerminalPanel() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero, modifierFlags: .control,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "`", charactersIgnoringModifiers: "`",
            isARepeat: false, keyCode: 50
        ))
        #expect(KeyBindingRegistry.shared.action(for: event) == .toggleTerminalPanel)
    }

    // FR-20 key binding — Cmd+Shift+` dispatches `.cycleFocusArea`.
    @Test func cmdShiftBacktickMapsToCycleFocusArea() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "~", charactersIgnoringModifiers: "`",
            isARepeat: false, keyCode: 50
        ))
        #expect(KeyBindingRegistry.shared.action(for: event) == .cycleFocusArea)
    }

    // FR-20 alternate binding — Cmd+' also dispatches `.cycleFocusArea`.
    @Test func cmdApostropheMapsToCycleFocusArea() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "'", charactersIgnoringModifiers: "'",
            isARepeat: false, keyCode: 39
        ))
        #expect(KeyBindingRegistry.shared.action(for: event) == .cycleFocusArea)
    }
}
