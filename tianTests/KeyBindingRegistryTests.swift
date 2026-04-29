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
        let event = keyEvent(keyCode: 17 /* T */, characters: "t", modifiers: [.command])
        #expect(KeyBindingRegistry.shared.action(for: event) == .newTab)
    }

    @Test func keyCodeBindingResolves() {
        let event = keyEvent(keyCode: 124 /* Right */, characters: "\u{F703}", modifiers: [.command, .shift])
        #expect(KeyBindingRegistry.shared.action(for: event) == .nextSpace)
    }

    @Test func cmdDigitSpecialCase() {
        let event = keyEvent(keyCode: 18 /* 1 */, characters: "1", modifiers: [.command])
        #expect(KeyBindingRegistry.shared.action(for: event) == .goToTab(1))
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
        let event = keyEvent(keyCode: 124, characters: "\u{F703}", modifiers: modifiers)
        #expect(KeyBindingRegistry.shared.action(for: event) == .nextSpace)
    }
}
