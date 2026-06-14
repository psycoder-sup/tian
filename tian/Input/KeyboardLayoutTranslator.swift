import AppKit
import Carbon.HIToolbox

/// Translates a physical virtual keycode into the character it produces on the
/// current **ASCII-capable** keyboard layout, ignoring the active input source.
///
/// macOS reports `event.charactersIgnoringModifiers` through the active input
/// source. With a non-Latin IME (Korean, Japanese, Chinese, Russian, …) the
/// **T** key reports a composed Hangul jamo, never `"t"`, so character-based
/// shortcut matching (Cmd+T, Cmd+W, …) misses entirely. Translating the keycode
/// through the ASCII-capable layout instead yields the Latin character for the
/// physical key — while still honoring Latin layout variants (AZERTY/Dvorak/
/// QWERTZ), since those *are* ASCII-capable.
///
/// This mirrors how Ghostty (and iTerm2/Alacritty) resolve keybindings.
@MainActor
final class KeyboardLayoutTranslator {
    static let shared = KeyboardLayoutTranslator()

    /// Cached `UCKeyboardLayout` bytes for the current ASCII-capable layout.
    /// `unshiftedCodepoint` runs on every keydown, so we avoid re-fetching the
    /// layout data per event and invalidate only when the input source changes.
    private var cachedLayoutData: Data?

    private init() {
        // The selected-keyboard-input-source notification is delivered on the
        // distributed center; refresh the cache whenever the source changes.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )
    }

    @objc private func inputSourceChanged() {
        cachedLayoutData = nil
    }

    /// The character produced by `keyCode` on the current ASCII-capable layout,
    /// lowercased. Returns `nil` for keys that have no character on that layout
    /// (arrows, function keys, etc.).
    func character(forKeyCode keyCode: UInt16) -> String? {
        guard let layoutData = layoutData() else { return nil }

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layoutPtr = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layoutPtr,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,                                  // no modifiers — base (unshifted) character
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).lowercased()
    }

    /// The first Unicode scalar value produced by `keyCode` on the current
    /// ASCII-capable layout, for Ghostty's `unshifted_codepoint`. Returns `nil`
    /// when the key has no character (caller should fall back).
    func unicodeScalar(forKeyCode keyCode: UInt16) -> UInt32? {
        guard let scalar = character(forKeyCode: keyCode)?.unicodeScalars.first else { return nil }
        return scalar.value
    }

    private func layoutData() -> Data? {
        if let cachedLayoutData { return cachedLayoutData }

        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(rawPtr).takeUnretainedValue() as Data
        cachedLayoutData = data
        return data
    }
}
