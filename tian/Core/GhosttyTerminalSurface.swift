import AppKit

/// Per-terminal object wrapping a `ghostty_surface_t`.
/// Manages the surface lifecycle: creation, resize, focus, and teardown.
@MainActor
final class GhosttyTerminalSurface: @unchecked Sendable {
    let id = UUID()

    nonisolated(unsafe) private(set) var surface: ghostty_surface_t?
    nonisolated(unsafe) private var callbackContextRef: Unmanaged<SurfaceCallbackContext>?

    /// Default off-screen backing geometry (~120×40 cells) used when a surface is
    /// created for a view that hasn't been laid out yet (e.g. a background tab/space
    /// realized via `PaneViewModel.realizeSurface`). Ensures the PTY spawns at a
    /// usable size and `ghostty_surface_read_text` can resolve a selection; the real
    /// size replaces it on the first on-screen layout via `updateSurfaceSize`.
    static let defaultBackingWidth: UInt32 = 1680
    static let defaultBackingHeight: UInt32 = 1050

    // MARK: - Surface Creation

    /// Create the ghostty surface and bind it to the given view.
    /// Must be called after the view is in a window.
    /// - Parameters:
    ///   - view: The NSView that hosts the surface.
    ///   - workingDirectory: Optional initial working directory for the shell.
    func createSurface(view: TerminalSurfaceView, workingDirectory: String? = nil, environmentVariables: [String: String] = [:], initialInput: String? = nil, command: String? = nil, waitAfterCommand: Bool = false) {
        guard let ghosttyApp = GhosttyApp.shared.app else {
            Log.ghostty.error("Cannot create surface: GhosttyApp not initialized")
            return
        }
        guard surface == nil else {
            Log.ghostty.warning("Surface already created")
            return
        }

        var config = GhosttyApp.shared.newSurfaceConfig()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(view).toOpaque()
            )
        )

        let ctx = SurfaceCallbackContext(surfaceId: id, surfaceView: view, terminalSurface: self)
        let retained = Unmanaged.passRetained(ctx)
        self.callbackContextRef = retained
        config.userdata = retained.toOpaque()

        let scaleFactor = Double(view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0)
        config.scale_factor = scaleFactor
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        // Build C array of env vars. strdup keeps strings alive until defer { free }.
        var cStrings: [UnsafeMutablePointer<CChar>] = []
        defer { cStrings.forEach { free($0) } }

        var envVars: [ghostty_env_var_s] = []
        for (key, value) in environmentVariables {
            let cKey = strdup(key)!
            let cValue = strdup(value)!
            cStrings.append(cKey)
            cStrings.append(cValue)
            envVars.append(ghostty_env_var_s(key: cKey, value: cValue))
        }

        // Create surface inside withCString / withUnsafeMutableBufferPointer
        // so all C pointers stay alive for the duration of ghostty_surface_new.
        let clock = ContinuousClock()
        let surfaceStart = clock.now
        // Remote panes set `command` to an `ssh -tt …` line; ghostty runs it via
        // `/bin/sh -c` in place of the login shell. An empty string leaves
        // ghostty on its default login shell (the local case). `wait_after_command`
        // keeps the terminal readable after the remote session disconnects.
        config.wait_after_command = waitAfterCommand
        let commandString = command ?? ""
        let created: ghostty_surface_t? = envVars.withUnsafeMutableBufferPointer { envBuffer in
            config.env_vars = envBuffer.baseAddress
            config.env_var_count = envBuffer.count
            return workingDirectory.withCString { cWd in
                config.working_directory = cWd
                return initialInput.withCString { cInput in
                    config.initial_input = cInput
                    return commandString.withCString { cCommand in
                        config.command = cCommand
                        return ghostty_surface_new(ghosttyApp, &config)
                    }
                }
            }
        }
        let surfaceMs = Double((clock.now - surfaceStart).components.attoseconds) / 1e15

        guard let created else {
            Log.ghostty.error("ghostty_surface_new returned nil")
            retained.release()
            self.callbackContextRef = nil
            NotificationCenter.default.post(
                name: GhosttyApp.surfaceSpawnFailedNotification,
                object: nil,
                userInfo: ["surfaceId": id]
            )
            return
        }

        self.surface = created
        AppMetrics.shared.recordSurfaceCreation(durationMs: surfaceMs)

        // Post-creation setup (order matters, matching cmux pattern)
        let displayID = view.window?.screen?.displayID ?? NSScreen.main?.displayID ?? 0
        if displayID != 0 {
            ghostty_surface_set_display_id(created, displayID)
        }

        ghostty_surface_set_content_scale(created, scaleFactor, scaleFactor)

        // Always size the surface so the PTY spawns at usable dimensions. A view
        // that hasn't been laid out yet (off-screen realization) reports zero bounds;
        // fall back to a default geometry, which the first on-screen layout replaces.
        let backingSize = view.convertToBacking(view.bounds).size
        let width = backingSize.width > 0 ? UInt32(backingSize.width) : Self.defaultBackingWidth
        let height = backingSize.height > 0 ? UInt32(backingSize.height) : Self.defaultBackingHeight
        ghostty_surface_set_size(created, width, height)

        ghostty_surface_set_focus(created, true)

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ghostty_surface_set_color_scheme(created, isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)

        ghostty_surface_refresh(created)
    }

    // MARK: - Surface State

    func setFocus(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    func setSize(width: UInt32, height: UInt32) {
        guard let surface else { return }
        ghostty_surface_set_size(surface, width, height)
    }

    func setContentScale(x: Double, y: Double) {
        guard let surface else { return }
        ghostty_surface_set_content_scale(surface, x, y)
    }

    func setDisplayID(_ displayID: UInt32) {
        guard let surface, displayID != 0 else { return }
        ghostty_surface_set_display_id(surface, displayID)
    }

    func sendKey(_ event: ghostty_input_key_s) -> Bool {
        guard let surface else { return false }
        return ghostty_surface_key(surface, event)
    }

    func requestClose() {
        guard let surface else { return }
        ghostty_surface_request_close(surface)
    }

    // MARK: - Text Injection

    /// Types the given text into the terminal, appending a newline to simulate pressing Enter.
    /// - Precondition: `text` must not contain newline characters. Use multiple calls for multiple commands.
    func sendText(_ text: String) {
        assert(!text.contains("\n"), "sendText does not support embedded newlines; call once per command")
        injectText(text, submit: true)
    }

    /// Injects text into the terminal, exactly as if the user pasted it.
    ///
    /// Routed through `ghostty_surface_text`, which is ghostty's paste path: when the
    /// running program has bracketed-paste mode enabled (a shell's line editor, an
    /// interactive Claude session, vim, …) ghostty frames the text in
    /// `ESC[200~ … ESC[201~` itself, so multi-line content arrives as a single paste
    /// instead of running line by line; otherwise it filters newlines to `\r`. Do
    /// NOT pre-wrap the text in bracket markers — this path drops the `ESC` control
    /// byte and the literal `[200~` ends up in the buffer.
    /// - Parameters:
    ///   - text: The text to inject. May contain newlines.
    ///   - submit: When true, press Return afterwards (see `pressReturn`) to submit.
    func injectText(_ text: String, submit: Bool) {
        guard let surface else { return }
        if !text.isEmpty {
            text.withCString { cString in
                ghostty_surface_text(surface, cString, UInt(text.utf8.count))
            }
        }
        if submit { pressReturn() }
    }

    /// Simulates pressing the Return key (press + release) as a real key event.
    /// This is required to "submit" input to TUIs that use a keyboard protocol
    /// (e.g. an interactive Claude session): such apps treat a `\n`/`\r` byte
    /// injected via the text path as a literal newline in the input buffer, and
    /// only recognize a genuine Return *key event* as Enter. Ghostty encodes the
    /// key per the surface's negotiated mode (legacy `\r` or Kitty protocol), so
    /// this also submits to a cooked-mode shell (CR→NL via the tty).
    func pressReturn() {
        guard let surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.keycode = 36 // kVK_Return
        keyEvent.action = GHOSTTY_ACTION_PRESS
        _ = ghostty_surface_key(surface, keyEvent)
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        _ = ghostty_surface_key(surface, keyEvent)
    }

    // MARK: - Text Capture

    /// Reads the terminal's contents from the live screen/grid model.
    /// Works for non-visible/background panes because it reads the VT parser's
    /// screen (continuously fed by the PTY), not the GPU renderer.
    /// - Parameter fullScrollback: When true, read the entire scrollback plus
    ///   screen; when false, read only the visible viewport.
    /// - Returns: The captured text, or nil if there is no live surface.
    func readContents(fullScrollback: Bool) -> String? {
        guard let surface else { return nil }
        // For TOP_LEFT / BOTTOM_RIGHT coords the x/y fields are ignored; the tag
        // selects the span (SCREEN = full scrollback + screen, VIEWPORT = visible).
        let tag: ghostty_point_tag_e = fullScrollback ? GHOSTTY_POINT_SCREEN : GHOSTTY_POINT_VIEWPORT
        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(tag: tag, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: tag, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false
        )
        var text = ghostty_text_s()
        guard ghostty_surface_read_text(surface, selection, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let cText = text.text else { return "" }
        return String(cString: cText)
    }

    // MARK: - Cleanup

    func freeSurface() {
        if let surface {
            ghostty_surface_free(surface)
            self.surface = nil
        }
        if let ref = callbackContextRef {
            ref.release()
            self.callbackContextRef = nil
        }
    }

    deinit {
        // Safety: free if not already freed
        // Use nonisolated(unsafe) to access MainActor state in deinit
        let surface = self.surface
        let ref = self.callbackContextRef
        if let surface {
            ghostty_surface_free(surface)
        }
        if let ref {
            ref.release()
        }
    }
}

// MARK: - Optional String C String Helper

extension Optional where Wrapped == String {
    /// Calls `body` with a C string pointer for `.some`, or `nil` for `.none`.
    func withCString<T>(_ body: (UnsafePointer<Int8>?) throws -> T) rethrows -> T {
        if let string = self {
            return try string.withCString(body)
        } else {
            return try body(nil)
        }
    }
}
