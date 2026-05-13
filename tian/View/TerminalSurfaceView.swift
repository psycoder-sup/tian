import AppKit

/// Delegate for terminal surface view events that need to propagate to the view model.
@MainActor
protocol TerminalSurfaceViewDelegate: AnyObject {
    func terminalSurfaceViewRequestSplit(_ view: TerminalSurfaceView, direction: SplitDirection)
    func terminalSurfaceViewRequestClose(_ view: TerminalSurfaceView)
    func terminalSurfaceViewRequestFocusDirection(_ view: TerminalSurfaceView, direction: NavigationDirection)
    func terminalSurfaceViewDidFocus(_ view: TerminalSurfaceView)
}

/// NSView subclass hosting a CAMetalLayer for ghostty rendering.
/// Forwards keyboard, mouse, and IME events to the ghostty surface.
final class TerminalSurfaceView: NSView {
    weak var terminalSurface: GhosttyTerminalSurface?
    weak var delegate: TerminalSurfaceViewDelegate?

    /// Set by TerminalContentView to drive focus from the model.
    /// When flipped to true, schedules an async makeFirstResponder so the
    /// KVO notification on NSWindow.firstResponder doesn't fire inside a
    /// SwiftUI view-graph update (which would re-enter via FirstResponderObserver
    /// and hang the main thread — see crash log 2026-05-12).
    var shouldBeFocused: Bool = false {
        didSet {
            guard shouldBeFocused != oldValue, shouldBeFocused else { return }
            scheduleFocusRestoration()
        }
    }

    private var focusRestorationPending = false

    /// Initial working directory for the shell, set before the view enters a window.
    var initialWorkingDirectory: String?

    /// Environment variables to inject into the shell session (TIAN_* keys + PATH).
    var environmentVariables: [String: String] = [:]

    /// Restore command to replay into the shell on surface creation (e.g. "claude --resume <id>").
    var initialInput: String?

    /// When true, keyboard and mouse input is suppressed (pane is exited/failed).
    var isInputSuppressed: Bool = false

    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var trackingArea: NSTrackingArea?

    // MARK: - Layer Setup
    // NOTE: Do NOT override makeBackingLayer or set wantsLayer here.
    // Ghostty's Metal renderer creates its own IOSurfaceLayer and assigns it
    // to this view's `layer` property, then sets `wantsLayer = true` to make
    // it a layer-hosting view. Pre-setting wantsLayer would make it layer-backed
    // instead, causing ghostty's layer assignment to be ignored.

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }

        // Create surface when view is attached to a window
        if let terminalSurface, terminalSurface.surface == nil {
            terminalSurface.createSurface(view: self, workingDirectory: initialWorkingDirectory, environmentVariables: environmentVariables, initialInput: initialInput)
        }

        updateSurfaceSize()
        updateTrackingAreas()

        // Restore focus after SwiftUI view recreation (container destroyed/recreated).
        // Deferred via scheduleFocusRestoration so we never call makeFirstResponder
        // synchronously from a SwiftUI lifecycle path.
        if shouldBeFocused {
            scheduleFocusRestoration()
        }
    }

    /// Defers `window.makeFirstResponder(self)` to the next runloop tick.
    /// Synchronous calls during a SwiftUI view-graph update trigger KVO that
    /// SwiftUI's FirstResponderObserver turns into another graph update, creating
    /// a feedback loop. The async hop ensures the KVO notification fires after
    /// the active transaction completes.
    private func scheduleFocusRestoration() {
        guard !focusRestorationPending else { return }
        focusRestorationPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.focusRestorationPending = false
            guard self.shouldBeFocused,
                  let window = self.window,
                  window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard superview != nil, terminalSurface?.surface != nil else { return }

        // When the view is re-parented (e.g., SwiftUI recreated the container
        // during a tree mutation), defer a size update + refresh until after
        // the layout pass has settled.
        DispatchQueue.main.async { [weak self] in
            guard let self, let surface = self.terminalSurface?.surface else { return }
            self.updateSurfaceSize()
            self.updateTrackingAreas()
            ghostty_surface_refresh(surface)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        guard let surface = terminalSurface?.surface else { return }

        // Sync contentsScale so the compositor doesn't rescale Metal output.
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }

        let scale = window?.backingScaleFactor ?? 2.0
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        updateSurfaceSize()

        if let displayID = window?.screen?.displayID, displayID != 0 {
            ghostty_surface_set_display_id(surface, displayID)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateSurfaceSize()
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        updateSurfaceSize()
    }

    private func updateSurfaceSize() {
        guard let surface = terminalSurface?.surface else { return }
        let backingSize = convertToBacking(bounds).size
        guard backingSize.width > 0 && backingSize.height > 0 else { return }
        ghostty_surface_set_size(surface, UInt32(backingSize.width), UInt32(backingSize.height))
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            terminalSurface?.setFocus(true)
            if let displayID = window?.screen?.displayID {
                terminalSurface?.setDisplayID(displayID)
            }
            delegate?.terminalSurfaceViewDidFocus(self)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            terminalSurface?.setFocus(false)
        }
        return result
    }

    // MARK: - Tracking Areas

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        self.trackingArea = area
        super.updateTrackingAreas()
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else {
            super.keyDown(with: event)
            return
        }

        // Fast path: Ctrl-modified keys bypass IME
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) && !flags.contains(.command) && !flags.contains(.option) && !hasMarkedText() {
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
            keyEvent.keycode = UInt32(event.keyCode)
            keyEvent.mods = modsFromEvent(event)
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.composing = false
            keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)

            let text = event.charactersIgnoringModifiers ?? event.characters ?? ""
            let handled: Bool
            if let firstScalar = text.unicodeScalars.first,
               firstScalar.value >= 0x20,
               !(firstScalar.value >= 0xF700 && firstScalar.value <= 0xF8FF) {
                handled = text.withCString { ptr in
                    keyEvent.text = ptr
                    return ghostty_surface_key(surface, keyEvent)
                }
            } else {
                keyEvent.text = nil
                handled = ghostty_surface_key(surface, keyEvent)
            }
            if handled { return }
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS

        // Translate mods for option-as-alt
        let translationModsGhostty = ghostty_surface_key_translation_mods(surface, modsFromEvent(event))
        var translationMods = event.modifierFlags
        applyTranslatedMods(ghosttyMods: translationModsGhostty, to: &translationMods)

        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event
        }

        // IME interpretation
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }
        let markedTextBefore = markedText.length > 0
        interpretKeyEvents([translationEvent])
        syncPreedit(clearIfNeeded: markedTextBefore)

        // Build key event
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = consumedMods(from: translationMods)
        keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)
        keyEvent.composing = markedText.length > 0 || markedTextBefore

        let accumulatedText = keyTextAccumulator ?? []
        if !accumulatedText.isEmpty {
            keyEvent.composing = false
            for text in accumulatedText {
                text.withCString { ptr in
                    keyEvent.text = ptr
                    _ = ghostty_surface_key(surface, keyEvent)
                }
            }
        } else {
            let text = textForKeyEvent(event)
            // Only send text if the first byte is a printable character (>= 0x20).
            // Control characters are encoded by Ghostty itself via the keycode.
            if let text, !text.isEmpty,
               let firstByte = text.utf8.first, firstByte >= 0x20 {
                text.withCString { ptr in
                    keyEvent.text = ptr
                    _ = ghostty_surface_key(surface, keyEvent)
                }
            } else {
                keyEvent.text = nil
                _ = ghostty_surface_key(surface, keyEvent)
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else {
            super.keyUp(with: event)
            return
        }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.text = nil
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }
        let isPress: Bool
        switch Int(event.keyCode) {
        case 56, 60: isPress = event.modifierFlags.contains(.shift)
        case 59, 62: isPress = event.modifierFlags.contains(.control)
        case 58, 61: isPress = event.modifierFlags.contains(.option)
        case 55, 54: isPress = event.modifierFlags.contains(.command)
        case 57:     isPress = event.modifierFlags.contains(.capsLock)
        case 63:     isPress = event.modifierFlags.contains(.function)
        default:     isPress = true
        }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = isPress ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.text = nil
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        // Only the focused pane (first responder) should handle key equivalents.
        // performKeyEquivalent is dispatched to ALL views in the hierarchy,
        // not just the first responder — without this guard, the first pane
        // in subview order would incorrectly handle shortcuts.
        guard window?.firstResponder === self else { return false }

        // Cmd+W always works, even when input is suppressed (exited/failed pane)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           chars == "w" && flags == [.command] {
            delegate?.terminalSurfaceViewRequestClose(self)
            return true
        }

        guard !isInputSuppressed else { return false }

        // Check split shortcuts before ghostty
        if let chars = event.charactersIgnoringModifiers?.lowercased() {
            if chars == "d" && flags == [.command, .shift] {
                delegate?.terminalSurfaceViewRequestSplit(self, direction: .horizontal)
                return true
            }
            if chars == "e" && flags == [.command, .shift] {
                delegate?.terminalSurfaceViewRequestSplit(self, direction: .vertical)
                return true
            }
        }

        // Cmd+Option+Arrow: directional focus navigation
        // Arrow keys include .numericPad and .function flags, so check containment
        if flags.contains([.command, .option]) {
            let direction: NavigationDirection?
            switch event.keyCode {
            case 123: direction = .left
            case 124: direction = .right
            case 125: direction = .down
            case 126: direction = .up
            default: direction = nil
            }
            if let direction {
                delegate?.terminalSurfaceViewRequestFocusDirection(self, direction: direction)
                return true
            }
        }

        // Let tian-level shortcuts (workspace, space, sidebar) propagate
        // to the menu bar or window event monitor instead of ghostty.
        if KeyBindingRegistry.shared.action(for: event) != nil {
            return false
        }

        guard let surface = terminalSurface?.surface else { return false }

        // Check if this event matches a Ghostty keybinding
        var keyEvent = ghosttyKeyEvent(for: event)
        let text = textForKeyEvent(event) ?? ""
        var bindingFlags = ghostty_binding_flags_e(0)
        let isBinding = text.withCString { ptr in
            keyEvent.text = ptr
            return ghostty_surface_key_is_binding(surface, keyEvent, &bindingFlags)
        }

        if isBinding {
            keyDown(with: event)
            return true
        }

        return false
    }

    override func doCommand(by selector: Selector) {
        // Prevent system beep on unhandled key commands
    }

    // MARK: - Mouse Input

    private func sendMousePos(_ event: NSEvent, surface: ghostty_surface_t) {
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, modsFromEvent(event))
    }

    override func mouseDown(with event: NSEvent) {
        // Click-to-focus: grab first responder on click even when suppressed
        if let window, window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }
        // Only update position on first click to prevent cursor jump during double-click selection
        if event.clickCount == 1 {
            sendMousePos(event, surface: surface)
        }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, modsFromEvent(event))
    }

    override func mouseUp(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }
        sendMousePos(event, surface: surface)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, modsFromEvent(event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }
        sendMousePos(event, surface: surface)
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }
        sendMousePos(event, surface: surface)
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard event.buttonNumber == 2, let surface = terminalSurface?.surface else { return }
        sendMousePos(event, surface: surface)
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }
        sendMousePos(event, surface: surface)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, modsFromEvent(event))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }
        if !ghostty_surface_mouse_captured(surface) {
            super.rightMouseDown(with: event)
            return
        }
        sendMousePos(event, surface: surface)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, modsFromEvent(event))
    }

    override func rightMouseUp(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }
        if !ghostty_surface_mouse_captured(surface) {
            super.rightMouseUp(with: event)
            return
        }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, modsFromEvent(event))
    }

    override func otherMouseDown(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard event.buttonNumber == 2, let surface = terminalSurface?.surface else { return }
        sendMousePos(event, surface: surface)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_MIDDLE, modsFromEvent(event))
    }

    override func otherMouseUp(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard event.buttonNumber == 2, let surface = terminalSurface?.surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE, modsFromEvent(event))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let surface = terminalSurface?.surface else { return nil }
        if ghostty_surface_mouse_captured(surface) { return nil }
        return super.menu(for: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard !isInputSuppressed else { return }
        guard let surface = terminalSurface?.surface else { return }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas
        if precision {
            x *= 2
            y *= 2
        }

        var mods: Int32 = 0
        if precision { mods |= 1 }

        let momentum: Int32
        switch event.momentumPhase {
        case .began: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue)
        case .stationary: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_STATIONARY.rawValue)
        case .changed: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue)
        case .ended: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue)
        case .cancelled: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue)
        case .mayBegin: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN.rawValue)
        default: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_NONE.rawValue)
        }
        mods |= momentum << 1

        ghostty_surface_mouse_scroll(surface, x, y, ghostty_input_scroll_mods_t(mods))
    }

}

// MARK: - NSTextInputClient

extension TerminalSurfaceView: @preconcurrency NSTextInputClient {
    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        guard markedText.length > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: 0, length: markedText.length)
    }

    func selectedRange() -> NSRange {
        NSRange(location: 0, length: 0)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString: markedText = NSMutableAttributedString(attributedString: v)
        case let v as String: markedText = NSMutableAttributedString(string: v)
        default: break
        }
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        if markedText.length > 0 {
            markedText.mutableString.setString("")
            syncPreedit()
        }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    func insertText(_ string: Any, replacementRange: NSRange) {
        var chars = ""
        switch string {
        case let v as NSAttributedString: chars = v.string
        case let v as String: chars = v
        default: return
        }

        unmarkText()
        guard !chars.isEmpty else { return }

        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(chars)
        } else {
            sendTextToSurface(chars)
        }
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        var x: Double = 0, y: Double = 0, w: Double = 10, h: Double = 20
        if let surface = terminalSurface?.surface {
            ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        }
        // Convert from ghostty top-left origin to AppKit bottom-left origin
        let viewRect = NSRect(x: x, y: frame.size.height - y, width: w, height: h)
        let winRect = convert(viewRect, to: nil)
        return window?.convertToScreen(winRect) ?? .zero
    }

}

// MARK: - Private Helpers

private extension TerminalSurfaceView {
    func sendTextToSurface(_ text: String) {
        guard let surface = terminalSurface?.surface else { return }
        text.withCString { ptr in
            var keyEvent = ghostty_input_key_s()
            keyEvent.action = GHOSTTY_ACTION_PRESS
            keyEvent.keycode = 0
            keyEvent.mods = GHOSTTY_MODS_NONE
            keyEvent.consumed_mods = GHOSTTY_MODS_NONE
            keyEvent.text = ptr
            keyEvent.composing = false
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface = terminalSurface?.surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            str.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(str.utf8.count))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    func modsFromEvent(_ event: NSEvent) -> ghostty_input_mods_e {
        var mods: UInt32 = 0
        let flags = event.modifierFlags
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    func consumedMods(from flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = 0
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        // Control and Command are never consumed for text translation
        return ghostty_input_mods_e(rawValue: mods)
    }

    func unshiftedCodepoint(from event: NSEvent) -> UInt32 {
        // Use characters(byApplyingModifiers: []) instead of charactersIgnoringModifiers
        // because the latter changes behavior with ctrl pressed.
        guard event.type == .keyDown || event.type == .keyUp,
              let chars = event.characters(byApplyingModifiers: []),
              let scalar = chars.unicodeScalars.first else { return 0 }
        return scalar.value
    }

    func textForKeyEvent(_ event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }

        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            // Control characters (< 0x20): return the character without control
            // modifier applied. Ghostty handles control character encoding internally.
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }

            // Function keys live in the Unicode PUA range — arrow keys, F1–F12,
            // Home, End, Page Up/Down, etc.  Return nil so Ghostty uses the
            // physical keycode to generate the correct escape sequence.
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }

    func ghosttyKeyEvent(for event: NSEvent) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.unshifted_codepoint = unshiftedCodepoint(from: event)
        keyEvent.composing = false
        return keyEvent
    }

    func applyTranslatedMods(ghosttyMods: ghostty_input_mods_e, to flags: inout NSEvent.ModifierFlags) {
        let mapping: [(NSEvent.ModifierFlags, ghostty_input_mods_e)] = [
            (.shift, GHOSTTY_MODS_SHIFT),
            (.control, GHOSTTY_MODS_CTRL),
            (.option, GHOSTTY_MODS_ALT),
            (.command, GHOSTTY_MODS_SUPER),
        ]
        for (flag, ghosttyFlag) in mapping {
            if (ghosttyMods.rawValue & ghosttyFlag.rawValue) != 0 {
                flags.insert(flag)
            } else {
                flags.remove(flag)
            }
        }
    }
}

// MARK: - NSScreen DisplayID Extension

extension NSScreen {
    var displayID: UInt32? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let v = deviceDescription[key] as? UInt32 { return v }
        if let v = deviceDescription[key] as? Int { return UInt32(v) }
        if let v = deviceDescription[key] as? NSNumber { return v.uint32Value }
        return nil
    }
}
