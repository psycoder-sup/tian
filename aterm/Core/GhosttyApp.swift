import AppKit

/// Singleton managing the ghostty application lifecycle.
/// Owns `ghostty_app_t`, runtime callbacks, config, and app-level state.
final class GhosttyApp: @unchecked Sendable {
    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    private(set) var defaultBackgroundColor: NSColor = .windowBackgroundColor
    private var appObservers: [NSObjectProtocol] = []

    // MARK: - Notifications

    /// Posted when a surface should close (shell exited).
    /// userInfo contains "surfaceId" (UUID).
    static let surfaceCloseNotification = Notification.Name("GhosttyApp.surfaceClose")

    /// Posted when a surface title changes.
    /// userInfo contains "surfaceId" (UUID) and "title" (String).
    static let surfaceTitleNotification = Notification.Name("GhosttyApp.surfaceTitle")

    /// Posted when a surface's working directory changes (OSC 7).
    /// userInfo contains "surfaceId" (UUID) and "pwd" (String).
    static let surfacePwdNotification = Notification.Name("GhosttyApp.surfacePwd")

    /// Posted when a surface's child process exits.
    /// userInfo contains "surfaceId" (UUID) and "exitCode" (UInt32).
    static let surfaceExitedNotification = Notification.Name("GhosttyApp.surfaceExited")

    /// Posted when a surface fails to spawn (ghostty_surface_new returned nil).
    /// userInfo contains "surfaceId" (UUID).
    static let surfaceSpawnFailedNotification = Notification.Name("GhosttyApp.surfaceSpawnFailed")

    // MARK: - Initialization

    private init() {
        initializeGhostty()
    }

    private func initializeGhostty() {
        // Ensure TUI apps can use colors even if NO_COLOR is set
        if getenv("NO_COLOR") != nil {
            unsetenv("NO_COLOR")
        }

        let clock = ContinuousClock()
        let initStart = clock.now
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        let initMs = Double((clock.now - initStart).components.attoseconds) / 1e15
        guard result == GHOSTTY_SUCCESS else {
            Log.ghostty.error("ghostty_init failed: \(result)")
            return
        }

        // Load config
        guard let primaryConfig = ghostty_config_new() else {
            Log.ghostty.error("Failed to create ghostty config")
            return
        }
        ghostty_config_load_default_files(primaryConfig)
        ghostty_config_finalize(primaryConfig)
        updateDefaultBackground(from: primaryConfig)

        // Runtime config with callbacks
        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = true

        runtimeConfig.wakeup_cb = { _ in
            DispatchQueue.main.async {
                GhosttyApp.shared.tick()
            }
        }

        runtimeConfig.action_cb = { _, target, action in
            return GhosttyApp.shared.handleAction(target: target, action: action)
        }

        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            guard let ctx = GhosttyApp.callbackContext(from: userdata),
                  let surface = ctx.runtimeSurface else { return false }

            nonisolated(unsafe) let capturedState = state
            DispatchQueue.main.async {
                guard ctx.runtimeSurface == surface else { return }
                let pasteboard = GhosttyApp.pasteboard(for: location)
                let text = pasteboard?.string(forType: .string) ?? ""
                text.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, capturedState, false)
                }
            }
            return true
        }

        runtimeConfig.confirm_read_clipboard_cb = { userdata, content, state, _ in
            guard let content else { return }
            guard let ctx = GhosttyApp.callbackContext(from: userdata),
                  let surface = ctx.runtimeSurface else { return }
            let contentStr = String(cString: content)
            nonisolated(unsafe) let capturedState = state
            DispatchQueue.main.async {
                guard ctx.runtimeSurface == surface else { return }
                contentStr.withCString { ptr in
                    ghostty_surface_complete_clipboard_request(surface, ptr, capturedState, true)
                }
            }
        }

        runtimeConfig.write_clipboard_cb = { _, location, content, len, _ in
            guard let content, len > 0 else { return }
            let buffer = UnsafeBufferPointer(start: content, count: Int(len))

            var fallback: String?
            for item in buffer {
                guard let dataPtr = item.data else { continue }
                let value = String(cString: dataPtr)
                if let mimePtr = item.mime {
                    let mime = String(cString: mimePtr)
                    if mime.hasPrefix("text/plain") {
                        GhosttyApp.writeString(value, to: location)
                        return
                    }
                }
                if fallback == nil { fallback = value }
            }
            if let fallback { GhosttyApp.writeString(fallback, to: location) }
        }

        runtimeConfig.close_surface_cb = { userdata, _ in
            guard let ctx = GhosttyApp.callbackContext(from: userdata) else { return }
            let surfaceId = ctx.surfaceId
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: GhosttyApp.surfaceCloseNotification,
                    object: nil,
                    userInfo: ["surfaceId": surfaceId]
                )
            }
        }

        // Create the app
        let appNewStart = clock.now
        if let created = ghostty_app_new(&runtimeConfig, primaryConfig) {
            let appNewMs = Double((clock.now - appNewStart).components.attoseconds) / 1e15
            self.app = created
            self.config = primaryConfig
            MainActor.assumeIsolated {
                AppMetrics.shared.recordGhosttyInit(initMs: initMs, appNewMs: appNewMs)
            }
        } else {
            Log.ghostty.warning("ghostty_app_new failed with primary config, trying fallback")
            ghostty_config_free(primaryConfig)

            // Fallback: empty config
            guard let fallbackConfig = ghostty_config_new() else { return }
            ghostty_config_finalize(fallbackConfig)
            if let created = ghostty_app_new(&runtimeConfig, fallbackConfig) {
                let appNewMs = Double((clock.now - appNewStart).components.attoseconds) / 1e15
                self.app = created
                self.config = fallbackConfig
                MainActor.assumeIsolated {
                    AppMetrics.shared.recordGhosttyInit(initMs: initMs, appNewMs: appNewMs)
                }
            } else {
                Log.ghostty.error("ghostty_app_new failed with fallback config")
                ghostty_config_free(fallbackConfig)
            }
        }

        // Track app focus
        let activateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let app = self?.app else { return }
            ghostty_app_set_focus(app, true)
        }
        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let app = self?.app else { return }
            ghostty_app_set_focus(app, false)
        }
        appObservers = [activateObserver, resignObserver]

        // Set initial color scheme (NSApp may be nil during early init)
        if let app, let nsApp = NSApp {
            let isDark = nsApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ghostty_app_set_color_scheme(app, isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT)
        }
    }

    // MARK: - Tick

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    // MARK: - Surface Config

    func newSurfaceConfig() -> ghostty_surface_config_s {
        ghostty_surface_config_new()
    }

    // MARK: - Action Handling

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        // App-level actions
        if target.tag == GHOSTTY_TARGET_APP {
            switch action.tag {
            case GHOSTTY_ACTION_RELOAD_CONFIG:
                reloadConfig()
                return true
            case GHOSTTY_ACTION_CONFIG_CHANGE:
                if let newConfig = action.action.config_change.config {
                    updateDefaultBackground(from: newConfig)
                }
                return true
            case GHOSTTY_ACTION_COLOR_CHANGE:
                let cc = action.action.color_change
                if cc.kind == GHOSTTY_ACTION_COLOR_KIND_BACKGROUND {
                    defaultBackgroundColor = NSColor(ghosttyRGB: (cc.r, cc.g, cc.b))
                }
                return true
            case GHOSTTY_ACTION_RING_BELL:
                NSSound.beep()
                return true
            default:
                return false
            }
        }

        // Surface-level actions
        guard target.tag == GHOSTTY_TARGET_SURFACE else { return false }
        guard let surfacePtr = target.target.surface else { return false }
        guard let ctx = GhosttyApp.callbackContext(
            from: ghostty_surface_userdata(surfacePtr)
        ) else { return false }

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            if let titlePtr = action.action.set_title.title {
                let title = String(cString: titlePtr)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: GhosttyApp.surfaceTitleNotification,
                        object: nil,
                        userInfo: ["surfaceId": ctx.surfaceId, "title": title]
                    )
                }
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            NSSound.beep()
            return true

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            // Must dispatch async to avoid re-entrant close during callback
            let surfaceId = ctx.surfaceId
            let exitCode = action.action.child_exited.exit_code
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: GhosttyApp.surfaceExitedNotification,
                    object: nil,
                    userInfo: ["surfaceId": surfaceId, "exitCode": exitCode]
                )
            }
            return true  // Return true to suppress "Press any key..." fallback

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            let shape = action.action.mouse_shape
            DispatchQueue.main.async {
                switch shape {
                case GHOSTTY_MOUSE_SHAPE_DEFAULT: NSCursor.arrow.set()
                case GHOSTTY_MOUSE_SHAPE_TEXT: NSCursor.iBeam.set()
                case GHOSTTY_MOUSE_SHAPE_POINTER: NSCursor.pointingHand.set()
                case GHOSTTY_MOUSE_SHAPE_CROSSHAIR: NSCursor.crosshair.set()
                default: NSCursor.arrow.set()
                }
            }
            return true

        case GHOSTTY_ACTION_COLOR_CHANGE:
            return true

        case GHOSTTY_ACTION_CONFIG_CHANGE:
            return true

        case GHOSTTY_ACTION_CELL_SIZE:
            return true

        case GHOSTTY_ACTION_PWD:
            if let pwdPtr = action.action.pwd.pwd {
                let pwd = String(cString: pwdPtr)
                let surfaceId = ctx.surfaceId
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: GhosttyApp.surfacePwdNotification,
                        object: nil,
                        userInfo: ["surfaceId": surfaceId, "pwd": pwd]
                    )
                }
            }
            return true

        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            return true

        default:
            // Return true for known-but-unimplemented actions to suppress ghostty fallback
            return true
        }
    }

    // MARK: - Config

    private func reloadConfig() {
        guard let newConfig = ghostty_config_new() else { return }
        ghostty_config_load_default_files(newConfig)
        ghostty_config_finalize(newConfig)
        if let app {
            ghostty_app_update_config(app, newConfig)
        }
        if let oldConfig = self.config {
            ghostty_config_free(oldConfig)
        }
        self.config = newConfig
        updateDefaultBackground(from: newConfig)
    }

    private func updateDefaultBackground(from config: ghostty_config_t) {
        var color = ghostty_config_color_s()
        let key = "background"
        if ghostty_config_get(config, &color, key, UInt(key.count)) {
            defaultBackgroundColor = NSColor(ghosttyRGB: (color.r, color.g, color.b))
        }
    }

    // MARK: - Callback Context

    static func callbackContext(from userdata: UnsafeMutableRawPointer?) -> SurfaceCallbackContext? {
        guard let userdata else { return nil }
        return Unmanaged<SurfaceCallbackContext>.fromOpaque(userdata).takeUnretainedValue()
    }

    // MARK: - Clipboard Helpers

    private static func pasteboard(for location: ghostty_clipboard_e) -> NSPasteboard? {
        switch location {
        case GHOSTTY_CLIPBOARD_STANDARD:
            return .general
        case GHOSTTY_CLIPBOARD_SELECTION:
            return NSPasteboard(name: NSPasteboard.Name("selection"))
        default:
            return .general
        }
    }

    private static func writeString(_ string: String, to location: ghostty_clipboard_e) {
        guard let pasteboard = pasteboard(for: location) else { return }
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    // MARK: - Cleanup

    deinit {
        for observer in appObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
    }
}

// MARK: - Surface Callback Context

/// Carries surface identity back to the host in ghostty callbacks.
/// Passed as userdata in surface configs via Unmanaged.passRetained().
final class SurfaceCallbackContext: @unchecked Sendable {
    let surfaceId: UUID
    weak var surfaceView: TerminalSurfaceView?
    weak var terminalSurface: GhosttyTerminalSurface?

    nonisolated var runtimeSurface: ghostty_surface_t? {
        terminalSurface?.surface
    }

    init(surfaceId: UUID, surfaceView: TerminalSurfaceView, terminalSurface: GhosttyTerminalSurface) {
        self.surfaceId = surfaceId
        self.surfaceView = surfaceView
        self.terminalSurface = terminalSurface
    }
}
