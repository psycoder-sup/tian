import AppKit

/// Per-terminal object wrapping a `ghostty_surface_t`.
/// Manages the surface lifecycle: creation, resize, focus, and teardown.
@MainActor
final class GhosttyTerminalSurface: @unchecked Sendable {
    let id = UUID()

    nonisolated(unsafe) private(set) var surface: ghostty_surface_t?
    nonisolated(unsafe) private var callbackContextRef: Unmanaged<SurfaceCallbackContext>?

    // MARK: - Surface Creation

    /// Create the ghostty surface and bind it to the given view.
    /// Must be called after the view is in a window.
    /// - Parameters:
    ///   - view: The NSView that hosts the surface.
    ///   - workingDirectory: Optional initial working directory for the shell.
    func createSurface(view: TerminalSurfaceView, workingDirectory: String? = nil, environmentVariables: [String: String] = [:], initialInput: String? = nil) {
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
        let created: ghostty_surface_t? = envVars.withUnsafeMutableBufferPointer { envBuffer in
            config.env_vars = envBuffer.baseAddress
            config.env_var_count = envBuffer.count
            return workingDirectory.withCString { cWd in
                config.working_directory = cWd
                return initialInput.withCString { cInput in
                    config.initial_input = cInput
                    return ghostty_surface_new(ghosttyApp, &config)
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

        let backingSize = view.convertToBacking(view.bounds).size
        if backingSize.width > 0 && backingSize.height > 0 {
            ghostty_surface_set_size(created, UInt32(backingSize.width), UInt32(backingSize.height))
        }

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
        guard let surface else { return }
        let command = text + "\n"
        command.withCString { cString in
            ghostty_surface_text(surface, cString, UInt(command.utf8.count))
        }
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
