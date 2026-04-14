# SPEC: Migrate from libghostty-vt to Full Ghostty App/Surface API

**Based on:** WORK-276 requirements (ghostty app/surface API migration)
**Author:** CTO Agent
**Date:** 2026-03-26
**Version:** 1.1
**Status:** Validated

---

## 1. Overview

This spec defines the migration of tian from the low-level `libghostty-vt` library (VT-only parsing) plus custom Metal rendering to the full ghostty embedding API (`ghostty_app_t` / `ghostty_surface_t`). The full API handles PTY management, VT parsing, Metal rendering (font atlas, cursor, selection, scrollback, color themes), and scrollback internally. Tian's role simplifies to: providing an NSView with a CAMetalLayer for ghostty to render into, forwarding keyboard/mouse events to the surface, implementing clipboard callbacks, and handling the surface lifecycle.

This is a major architectural simplification. Approximately 11 source files (plus 5 renderer files and a C implementation) totaling 2,600+ lines of custom rendering, PTY, and bridge code are replaced by a thin wrapper around ghostty's surface API. The reference implementation is cmux (at `/tmp/cmux`), which demonstrates the integration pattern.

**Supersedes:** The Renderer, PTY, and Bridge layers from the M1 Terminal Fundamentals spec. The App and View layers are rewritten but retain their architectural role.

---

## 2. Current Architecture (What Exists Today)

### 2.1 File Inventory

| Directory | File | Lines | Purpose |
|-----------|------|-------|---------|
| App/ | TianApp.swift | 12 | SwiftUI app entry point |
| App/ | TerminalWindow.swift | 39 | Window with TerminalCore lifecycle |
| Core/ | TerminalCore.swift | 221 | Orchestrates PTY, VT bridge, snapshot handoff (includes TerminalBridge facade) |
| Core/ | PTYProcess.swift | 174 | POSIX PTY fork/exec, resize, terminate |
| Core/ | PTYFileHandle.swift | 74 | DispatchSource-based PTY read/write |
| Core/ | ANSIStripper.swift | 71 | ANSI escape sequence stripper |
| Core/ | pty_helpers.h | 12 | C header for fork, WIFEXITED macros |
| Core/ | pty_helpers.c | 31 | C implementation of fork wrapper, WIFEXITED/WEXITSTATUS, SIGCHLD handler |
| Bridge/ | GhosttyBridge.swift | 347 | Swift wrappers for ghostty_terminal, render_state, key_encoder |
| Bridge/ | GhosttyTypes.swift | 137 | GridPosition, CursorState, CellStyle, RGBColor, GhosttyError, etc. |
| Bridge/ | ghostty_helpers.h | 19 | C helpers for struct initialization (render_state_colors, style) |
| Renderer/ | TerminalRenderer.swift | 470 | Metal pipeline setup, triple-buffered rendering |
| Renderer/ | FontAtlas.swift | 314 | CoreText glyph rasterization + texture atlas |
| Renderer/ | CellBuffer.swift | 45 | TripleBuffer generic Metal buffer |
| Renderer/ | GridSnapshot.swift | 108 | Immutable snapshot of terminal grid state + NSAttributedString conversion |
| Renderer/ | ShaderTypes.h | 67 | Shared C structs for Metal shaders |
| Renderer/ | Shaders.metal | 194 | Background, text, cursor shader passes |
| View/ | TerminalContentView.swift | 58 | NSViewRepresentable, snapshot consumption timer |
| View/ | TerminalMetalView.swift | 360 | NSView + CAMetalLayer, keyboard input, IME, display link |
| Utilities/ | LargeStackThread.swift | 61 | pthread with 8MB stack for VT processing |
| Utilities/ | Logger.swift | 10 | os.Logger subsystem categories (pty, core, view, bridge, renderer) |
| Utilities/ | Colors.swift | 14 | NSColor.terminalBackground extension |
| Utilities/ | DefaultTheme.swift | 35 | Tokyo Night Storm hardcoded palette |
| Vendor/ | ghostty/lib/libghostty-vt.a | -- | Static library (VT-only) |
| Vendor/ | ghostty/include/ghostty/vt.h + subdirs | -- | C headers for VT API |

**Test Files (tianTests/):**

| File | Purpose |
|------|---------|
| ANSIStripperTests.swift | Tests for ANSIStripper (KEEP) |
| PTYProcessTests.swift | Tests for PTYProcess (DELETE) |
| PTYIntegrationTests.swift | Integration tests for PTY + shell (DELETE) |
| GhosttyBridgeTests.swift | Tests for GhosttyBridge wrappers (DELETE) |

### 2.2 Current Data Flow

1. **PTYProcess** forks a shell and provides master FD
2. **PTYFileHandle** reads from master FD via DispatchSource, fires callback
3. **TerminalCore** dispatches output to **LargeStackThread** (8MB stack)
4. On the large-stack thread: **TerminalBridge** (facade around GhosttyBridge objects) parses VT via `ghostty_terminal_vt_write()`
5. **GhosttyBridge.RenderState** extracts a **GridSnapshot** (cells, cursor, colors)
6. Snapshot is handed off via `OSAllocatedUnfairLock` to the render thread
7. **TerminalRenderer** consumes snapshot, builds Metal buffers (background colors, text instances via **FontAtlas**, cursor instances)
8. Three Metal render passes: background fill, instanced text quads, cursor quad
9. CADisplayLink drives frame presentation

### 2.3 Current Dependency

- **libghostty-vt.a** -- linked via `-lghostty-vt`, headers at `Vendor/ghostty/include/ghostty/vt.h`
- Bridging header imports: `ghostty/vt.h`, `pty_helpers.h`, `ghostty_helpers.h`, `ShaderTypes.h`

---

## 3. Target Architecture (What We're Moving To)

### 3.1 Core Concept

The full ghostty embedding API is a higher-level abstraction:

- **ghostty_app_t** -- Singleton application object. Owns config, manages surfaces, processes runtime callbacks (clipboard, close, wakeup). Created once at app launch.
- **ghostty_surface_t** -- Per-terminal-pane object. Owns the PTY, VT parser, Metal renderer, font atlas, cursor, selection, scrollback, and color themes. Renders directly into a CAMetalLayer provided by the host NSView.
- **ghostty_config_t** -- Configuration object for themes, fonts, keybindings, etc.

The host application's responsibilities reduce to:
1. Initialize ghostty (`ghostty_init`)
2. Create a `ghostty_app_t` with runtime callbacks
3. For each terminal pane, provide an NSView with a CAMetalLayer and create a `ghostty_surface_t` bound to it
4. Forward keyboard events via `ghostty_surface_key()`
5. Forward mouse events via `ghostty_surface_mouse_*()` functions
6. Implement clipboard read/write callbacks
7. Call `ghostty_app_tick()` on wakeup
8. Handle the action callback for title changes, close requests, bell, etc.
9. Track app-level focus via `ghostty_app_set_focus()` on app active/resign

### 3.2 Target File Layout

| Directory | File | Status | Purpose |
|-----------|------|--------|---------|
| App/ | TianApp.swift | MODIFY | Initialize GhosttyApp singleton in `.task` |
| App/ | TerminalWindow.swift | REWRITE | Simplified: create GhosttyTerminalSurface, host view |
| Core/ | GhosttyApp.swift | NEW | Singleton wrapping ghostty_app_t, runtime callbacks, tick |
| Core/ | GhosttyTerminalSurface.swift | NEW | Wraps ghostty_surface_t, lifecycle, focus, resize |
| Core/ | ANSIStripper.swift | KEEP | Utility, not related to rendering |
| Bridge/ | GhosttyBridge.swift | DELETE | Replaced by direct ghostty_surface_* calls |
| Bridge/ | GhosttyTypes.swift | DELETE | Types now internal to ghostty |
| Bridge/ | ghostty_helpers.h | DELETE | No longer needed |
| View/ | TerminalSurfaceView.swift | NEW (replaces TerminalMetalView.swift) | NSView + CAMetalLayer, keyboard/mouse forwarding |
| View/ | TerminalContentView.swift | REWRITE | Simplified NSViewRepresentable wiring |
| Utilities/ | Logger.swift | KEEP | Retain logging categories |
| Utilities/ | Colors.swift | MODIFY | Background color from ghostty config |
| Utilities/ | DefaultTheme.swift | DELETE | Ghostty handles themes via config |
| Utilities/ | LargeStackThread.swift | DELETE | Ghostty manages its own threads |
| Renderer/ | (entire directory) | DELETE | All rendering handled by ghostty |
| Core/ | PTYProcess.swift | DELETE | Ghostty manages PTY internally |
| Core/ | PTYFileHandle.swift | DELETE | Ghostty manages PTY I/O internally |
| Core/ | pty_helpers.h | DELETE | No longer needed |
| Core/ | pty_helpers.c | DELETE | No longer needed (C fork/WIFEXITED wrapper) |
| Core/ | TerminalCore.swift | DELETE | Replaced by GhosttyApp + GhosttyTerminalSurface |
| Vendor/ | ghostty/ | REPLACE | Replace libghostty-vt.a + vt.h with GhosttyKit.xcframework or libghostty.a + ghostty.h |

### 3.3 Target Data Flow

1. **GhosttyApp** calls `ghostty_init()` then creates `ghostty_app_t` with runtime config (callbacks for wakeup, clipboard, close, action)
2. **wakeup_cb** dispatches `ghostty_app_tick()` on main thread
3. **TerminalSurfaceView** provides CAMetalLayer via `makeBackingLayer()`
4. **GhosttyTerminalSurface** creates `ghostty_surface_t` passing the NSView pointer in `ghostty_surface_config_s.platform.macos.nsview`
5. Ghostty internally: spawns PTY, parses VT, renders into the Metal layer, manages font atlas, cursor, selection, scrollback
6. **TerminalSurfaceView** forwards `keyDown`/`keyUp` via `ghostty_surface_key()`, mouse via `ghostty_surface_mouse_*()`, scroll via `ghostty_surface_mouse_scroll()`
7. **TerminalSurfaceView** forwards resize via `ghostty_surface_set_size()` + `ghostty_surface_set_content_scale()`
8. **action_cb** handles title changes (`GHOSTTY_ACTION_SET_TITLE`), bell (`GHOSTTY_ACTION_RING_BELL`), close requests, config changes
9. **close_surface_cb** handles surface-initiated close (shell exit)
10. **clipboard callbacks** read/write NSPasteboard

---

## 4. API Mapping

### 4.1 Initialization (Current -> Target)

| Current | Target |
|---------|--------|
| N/A | `ghostty_init(argc, argv)` -- one-time library init. Returns `int`; compare with `GHOSTTY_SUCCESS` (value 0). Parameter types: `(uintptr_t, char**)`. |
| N/A | `ghostty_config_new()` + `ghostty_config_load_default_files()` + `ghostty_config_finalize()` |
| N/A | `ghostty_app_new(&runtime_config, config)` |

### 4.2 Terminal Lifecycle

| Current | Target |
|---------|--------|
| `PTYProcess(columns:rows:)` -- fork/exec shell | `ghostty_surface_new(app, &surface_config)` -- ghostty spawns PTY internally |
| `GhosttyBridge.Terminal(columns:rows:maxScrollback:)` | (included in surface creation) |
| `GhosttyBridge.RenderState()` | (included in surface creation) |
| `GhosttyBridge.KeyEncoder()` | (included in surface creation) |
| `ptyProcess.resize(columns:rows:)` | `ghostty_surface_set_size(surface, width_px, height_px)` (pixel-based, not cell-based) |
| `ptyProcess.terminate()` | `ghostty_surface_free(surface)` -- cmux uses direct free rather than request_close for host-initiated teardown. `ghostty_surface_request_close(surface)` exists for cases where the surface should go through the close confirmation flow. |

### 4.3 Input Handling

| Current | Target |
|---------|--------|
| `bridge.encodeKey(action:key:mods:text:)` then `fileHandle.write(data)` | `ghostty_surface_key(surface, key_event)` -- single call, ghostty handles encoding + PTY write |
| `core.sendInput(string)` then manual PTY write | `ghostty_surface_key()` with text field set, or via IME text path |
| Manual key code mapping (ghosttyKey from keyCode) | Same keycode mapping, but passed via `ghostty_input_key_s.keycode` (raw macOS keycode) |
| Manual modifier translation | `ghostty_surface_key_translation_mods()` for option-as-alt handling |

### 4.4 Input Event Structure

The `ghostty_input_key_s` struct replaces the separate action/key/mods parameters:

| Field | Type | Description |
|-------|------|-------------|
| action | ghostty_input_action_e | GHOSTTY_ACTION_PRESS, GHOSTTY_ACTION_RELEASE, or GHOSTTY_ACTION_REPEAT |
| mods | ghostty_input_mods_e | Modifier flags (GHOSTTY_MODS_SHIFT, GHOSTTY_MODS_CTRL, GHOSTTY_MODS_ALT, GHOSTTY_MODS_SUPER, GHOSTTY_MODS_CAPS) |
| consumed_mods | ghostty_input_mods_e | Modifiers consumed by text translation. Per cmux pattern: only shift and option should be included; ctrl and cmd are never consumed for text translation. |
| keycode | uint32_t | Raw macOS keycode (event.keyCode) |
| text | const char* | UTF-8 text produced by the key event (from `event.characters` or IME accumulator) |
| unshifted_codepoint | uint32_t | Codepoint without shift applied (from `event.charactersIgnoringModifiers`) |
| composing | bool | Whether this is an IME composition event. True when marked text is active or was just cleared. |

### 4.5 Mouse Input

| Current (stubs) | Target |
|-----------------|--------|
| `mouseDown` -- no-op | `ghostty_surface_mouse_pos()` + `ghostty_surface_mouse_button(GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, mods)` |
| `mouseDragged` -- no-op | `ghostty_surface_mouse_pos()` |
| `mouseUp` -- no-op | `ghostty_surface_mouse_button(GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, mods)` |
| `scrollWheel` -- no-op | `ghostty_surface_mouse_scroll(surface, x, y, scroll_mods)` -- NOTE: the third parameter is `ghostty_input_scroll_mods_t` (a packed int), not `ghostty_input_mods_e`. See section 8.3 for details. |

Mouse coordinates use the view's coordinate system: x from left, y from top of NSView bounds (Y must be flipped: `bounds.height - point.y`).

### 4.6 Rendering

| Current | Target |
|---------|--------|
| Custom Metal pipeline (3 passes: bg, text, cursor) | Ghostty renders internally -- no application rendering code |
| FontAtlas (CoreText rasterization, shelf packing) | Ghostty manages font atlas internally |
| GridSnapshot extraction via render_state API | No snapshot extraction -- ghostty draws directly |
| CADisplayLink driving `renderer.render(in: metalLayer)` | Ghostty manages its own CVDisplayLink/vsync |
| Triple-buffered Metal buffers | Ghostty manages its own buffer strategy |

### 4.7 Resize

| Current | Target |
|---------|--------|
| `renderer.updateScreenSize(size, scaleFactor)` computes grid columns/rows from cell size | `ghostty_surface_set_size(surface, width_px, height_px)` -- ghostty computes grid internally |
| `renderer.currentGridSize` drives `core.resize(columns:rows:)` which calls `ghostty_terminal_resize()` + `ioctl(TIOCSWINSZ)` | `ghostty_surface_set_content_scale(surface, x, y)` for Retina; size is pixel-based |
| Grid padding (4pt) applied manually | Ghostty config `window-padding-x`, `window-padding-y` |

### 4.8 Runtime Callbacks

The `ghostty_runtime_config_s` struct defines the callback interface between ghostty and the host:

| Field | Type / Signature | Purpose |
|-------|------------------|---------|
| userdata | `void*` | Opaque pointer passed to callbacks. Set to GhosttyApp instance. |
| supports_selection_clipboard | `bool` | Set to `true` to enable selection clipboard (OSC 52 selection). |
| wakeup_cb | `void(void* userdata)` | Ghostty needs the host to call `ghostty_app_tick()`. Dispatch to main thread. |
| action_cb | `bool(ghostty_app_t, ghostty_target_s, ghostty_action_s)` | Handle ghostty actions: title changes, bell, close, config changes, color changes, cell size, etc. Return true if handled. |
| read_clipboard_cb | `void(void* userdata, ghostty_clipboard_e, void* state)` | Read from NSPasteboard, call `ghostty_surface_complete_clipboard_request()` with result |
| confirm_read_clipboard_cb | `void(void* userdata, const char*, void* state, ghostty_clipboard_request_e)` | Confirm clipboard read (for OSC 52). Call `ghostty_surface_complete_clipboard_request()`. |
| write_clipboard_cb | `void(void*, ghostty_clipboard_e, const ghostty_clipboard_content_s*, size_t, bool)` | Write string to NSPasteboard. Content is an array of `ghostty_clipboard_content_s` items with MIME types. |
| close_surface_cb | `void(void* userdata, bool needs_confirm)` | Shell exited or surface close requested. Remove the terminal pane. |

### 4.9 Action Callback Actions (Subset Needed for M1)

| Action Tag | When Fired | Host Response |
|------------|------------|---------------|
| GHOSTTY_ACTION_SET_TITLE | Shell sets window title | Update window title |
| GHOSTTY_ACTION_RING_BELL | BEL character received | Play system alert sound |
| GHOSTTY_ACTION_CELL_SIZE | Cell metrics changed (font change) | Could adjust padding/layout |
| GHOSTTY_ACTION_COLOR_CHANGE | Background/foreground color changed | Update window background color |
| GHOSTTY_ACTION_CONFIG_CHANGE | Config reloaded | Refresh UI state |
| GHOSTTY_ACTION_RELOAD_CONFIG | Config reload requested | Reload config and refresh UI |
| GHOSTTY_ACTION_SHOW_CHILD_EXITED | Child process exited | Show exit status or close |
| GHOSTTY_ACTION_MOUSE_SHAPE | Cursor shape change | Set NSCursor |
| GHOSTTY_ACTION_RENDER | Surface needs redraw | Optionally call `ghostty_surface_draw()` (cmux does not handle this -- ghostty manages rendering internally via CVDisplayLink) |
| GHOSTTY_ACTION_PWD | Working directory changed | Track for future use |
| GHOSTTY_ACTION_DESKTOP_NOTIFICATION | OSC notification | Show desktop notification |

---

## 5. Detailed File Changes

### 5.1 Files to DELETE (16 files)

These files are entirely replaced by ghostty internals:

| File | Reason |
|------|--------|
| Renderer/FontAtlas.swift | Ghostty manages font atlas |
| Renderer/Shaders.metal | Ghostty owns Metal shaders |
| Renderer/ShaderTypes.h | Ghostty owns shader types |
| Renderer/TerminalRenderer.swift | Ghostty owns rendering pipeline |
| Renderer/CellBuffer.swift | Ghostty owns Metal buffers |
| Renderer/GridSnapshot.swift | No snapshot extraction needed |
| Core/PTYProcess.swift | Ghostty spawns and manages PTY |
| Core/PTYFileHandle.swift | Ghostty handles PTY I/O |
| Core/pty_helpers.h | No manual PTY fork needed |
| Core/pty_helpers.c | No manual PTY fork needed (C implementation of fork wrapper) |
| Core/TerminalCore.swift | Replaced by GhosttyApp + GhosttyTerminalSurface |
| Utilities/LargeStackThread.swift | Ghostty manages its own thread stack |
| Utilities/DefaultTheme.swift | Ghostty handles themes via config file |
| Bridge/GhosttyBridge.swift | Replaced by direct surface API calls |
| Bridge/GhosttyTypes.swift | Types now internal to ghostty or simplified |
| Bridge/ghostty_helpers.h | No render_state struct initialization needed |

**Test files to DELETE (3 files):**

| File | Reason |
|------|--------|
| tianTests/PTYProcessTests.swift | PTYProcess is being deleted |
| tianTests/PTYIntegrationTests.swift | PTY integration layer is being deleted |
| tianTests/GhosttyBridgeTests.swift | GhosttyBridge is being deleted |

### 5.2 Files to CREATE (3 files)

#### 5.2.1 Core/GhosttyApp.swift

Singleton class managing the ghostty application lifecycle.

**Responsibilities:**
- Unset `NO_COLOR` env var if present before initialization (matching cmux pattern to ensure terminal color support)
- Call `ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)` once at startup; compare result with `GHOSTTY_SUCCESS`
- Create and own `ghostty_config_t` (load default files, finalize)
- Create and own `ghostty_app_t` with `ghostty_runtime_config_s`
- Set `runtimeConfig.supports_selection_clipboard = true`
- Implement wakeup callback: dispatch `ghostty_app_tick()` to main thread
- Implement clipboard read callback: read from NSPasteboard, complete clipboard request on the requesting surface
- Implement clipboard write callback: iterate content array, prefer `text/plain` MIME type, write to NSPasteboard
- Implement close_surface callback: post notification that surface should be removed
- Implement action callback: dispatch to appropriate handler based on action tag
- Track background color from config for window background
- Provide public method to create surface configs for new terminals via `ghostty_surface_config_new()`
- Track app-level focus via `ghostty_app_set_focus()` on `NSApplication.didBecomeActiveNotification` / `didResignActiveNotification`
- Track system color scheme via `ghostty_app_set_color_scheme()`

**Key Design Decisions:**
- Singleton pattern (matches cmux's `GhosttyApp.shared`). Only one ghostty_app_t per process.
- The `userdata` pointer in the runtime config points to the GhosttyApp instance (via `Unmanaged.passUnretained(self).toOpaque()`).
- The `userdata` pointer in surface configs points to a per-surface callback context object that carries the surface identity back to the host in callbacks.
- The tick function must be called on the main thread. The wakeup callback dispatches to main.

**Error Handling:**
- If `ghostty_init()` fails (returns non-zero), log error and set app to nil state. TianApp shows error UI.
- If `ghostty_config_new()` fails, attempt fallback with empty config (matching cmux pattern).
- If `ghostty_app_new()` fails with primary config, free primary config, create a fallback config (new + finalize only, no load_default_files), retry `ghostty_app_new()` with fallback.

#### 5.2.2 Core/GhosttyTerminalSurface.swift

Per-terminal object wrapping `ghostty_surface_t`.

**Responsibilities:**
- Hold `ghostty_surface_t` pointer
- Create surface via `ghostty_surface_new()` when attached to a view
- Set initial display ID, content scale, size, focus state (in that order, matching cmux pattern)
- Call `ghostty_surface_refresh()` after creation to kick initial draw
- Set color scheme via `ghostty_surface_set_color_scheme()` based on system appearance
- Provide methods: `setFocus(Bool)`, `setSize(width:height:)`, `setContentScale(x:y:)`, `requestClose()`
- Forward key events via `ghostty_surface_key()`
- Forward mouse events via `ghostty_surface_mouse_pos/button/scroll()`
- Forward IME preedit via `ghostty_surface_preedit()`
- Forward IME point query via `ghostty_surface_ime_point()`
- Clean up on deinit: `ghostty_surface_free()`
- Manage a callback context object (`Unmanaged<SurfaceCallbackContext>`) that is passed as `surface_config.userdata`

**Lifecycle:**
1. Created by TerminalWindow
2. Surface view attaches -> `createSurface()` called
3. View appears in window -> set display ID, content scale, size, focus, color scheme; call `ghostty_surface_refresh()`
4. View resizes -> `ghostty_surface_set_size()`, `ghostty_surface_set_content_scale()`
5. Shell exits -> `close_surface_cb` fires -> surface is freed

**SurfaceCallbackContext:**
A reference-counted context class, retained by the surface config's userdata. Contains:
- Surface ID (UUID)
- Weak reference to the GhosttyTerminalSurface
- Weak reference to the TerminalSurfaceView

This allows the runtime callbacks (which receive only a void* userdata) to safely resolve back to the Swift surface and view objects. The context is created with `Unmanaged.passRetained()` and released explicitly on surface teardown.

#### 5.2.3 View/TerminalSurfaceView.swift

NSView subclass that hosts the ghostty surface's Metal rendering.

**Responsibilities:**
- Override `makeBackingLayer()` to return a CAMetalLayer with `.bgra8Unorm` pixel format, `isOpaque = false`, `framebufferOnly = false` (matching cmux's GhosttyNSView -- framebufferOnly must be false for background opacity/blur compositing)
- Forward `keyDown(with:)` to `ghostty_surface_key()` with the `ghostty_input_key_s` struct
- Forward `keyUp(with:)` to `ghostty_surface_key()` with GHOSTTY_ACTION_RELEASE action
- Forward `flagsChanged(with:)` for modifier key tracking
- Forward `mouseDown/Up/Dragged`, `rightMouseDown/Up`, `otherMouseDown/Up` (middle button), `scrollWheel` to the appropriate `ghostty_surface_mouse_*()` functions
- Forward mouse enter/exit for hover tracking (send position (-1, -1) on mouseExited)
- Implement `NSTextInputClient` for IME support, calling `ghostty_surface_preedit()` for marked text and `ghostty_surface_key()` for committed text
- Track and report size changes via `ghostty_surface_set_size()` in backing pixel coordinates
- Use `ghostty_surface_key_translation_mods()` for option-as-alt translation
- Handle first responder management
- Implement `NSScreen.displayID` extension (reads from `deviceDescription["NSScreenNumber"]` with type coercion fallbacks for UInt32, Int, NSNumber) since this is not a standard AppKit property

**Key Differences from Current TerminalMetalView:**
- No display link management (ghostty owns vsync/CVDisplayLink)
- No renderer reference (ghostty renders directly)
- No manual grid size calculation (ghostty computes internally)
- `ghostty_surface_key()` replaces the separate key encoder + PTY write path
- Mouse events are actually forwarded (currently stubs)
- IME uses `ghostty_surface_preedit()` instead of local marked text state
- Middle mouse button and right mouse button events forwarded
- `ghostty_surface_mouse_captured()` used to conditionally suppress right-click context menu

### 5.3 Files to MODIFY

#### 5.3.1 App/TianApp.swift

**Changes:**
- Add `.task` block to initialize `GhosttyApp.shared` before window appears
- The app-level focus and color scheme tracking is handled inside GhosttyApp.swift via notification observers

#### 5.3.2 App/TerminalWindow.swift

**Changes:**
- Replace `TerminalCore` with `GhosttyTerminalSurface`
- Pass surface to `TerminalContentView`
- Handle surface close (shell exit) via notification from GhosttyApp's close callback
- Set window title based on SET_TITLE action callback

#### 5.3.3 View/TerminalContentView.swift

**Changes:**
- Remove snapshot consumption timer (Coordinator.startSnapshotConsumption)
- Remove reference to TerminalRenderer
- Create `TerminalSurfaceView` instead of `TerminalMetalView`
- Wire surface attachment: pass `GhosttyTerminalSurface` to the view

#### 5.3.4 Utilities/Colors.swift

**Changes:**
- Derive background color from `GhosttyApp.shared.defaultBackgroundColor` instead of `DefaultTheme`

#### 5.3.5 Utilities/Logger.swift

**Changes:**
- Remove `renderer` and `pty` categories (no longer needed)
- Remove `bridge` category or rename to `ghostty`
- Keep `core` and `view` categories

#### 5.3.6 tian-Bridging-Header.h

**Changes:**
- Replace `#import <ghostty/vt.h>` with `#import "ghostty.h"`
- Remove `#import "Core/pty_helpers.h"`
- Remove `#import "Bridge/ghostty_helpers.h"`
- Remove `#import "Renderer/ShaderTypes.h"`

### 5.4 Files to KEEP (unchanged)

| File | Reason |
|------|--------|
| Core/ANSIStripper.swift | General utility, not related to rendering |
| tianTests/ANSIStripperTests.swift | Tests remain valid, utility not changed |

---

## 6. Build System Changes

### 6.1 Vendor Library Replacement

**Current state:**
- `tian/Vendor/ghostty/lib/libghostty-vt.a` -- static library
- `tian/Vendor/ghostty/include/ghostty/vt.h` + sub-headers -- C API
- Xcode: HEADER_SEARCH_PATHS includes `$(SRCROOT)/tian/Vendor/ghostty/include`
- Xcode: LIBRARY_SEARCH_PATHS includes `$(SRCROOT)/tian/Vendor/ghostty/lib`
- Xcode: OTHER_LDFLAGS includes `-lghostty-vt`

**Target state (Option A -- xcframework, recommended):**
- `tian/Vendor/GhosttyKit.xcframework` -- pre-built xcframework (matching cmux's approach)
- `tian/Vendor/ghostty.h` -- single header file (copied from the full ghostty API header)
- Xcode: Add `GhosttyKit.xcframework` to "Frameworks, Libraries, and Embedded Content" (link and embed)
- Xcode: HEADER_SEARCH_PATHS includes `$(SRCROOT)/tian/Vendor` (for ghostty.h)
- Remove old LIBRARY_SEARCH_PATHS and `-lghostty-vt` from OTHER_LDFLAGS

**Target state (Option B -- static library):**
- `tian/Vendor/ghostty/lib/libghostty.a` -- static library (full API)
- `tian/Vendor/ghostty.h` -- single header
- Xcode: Update LIBRARY_SEARCH_PATHS, change `-lghostty-vt` to `-lghostty`
- Additional link flags may be needed for Metal framework, IOSurface

**Recommendation:** Option A (xcframework) because it encapsulates framework dependencies and matches the cmux reference. The `.ghostty-src` directory already present in the tian repo (a shallow clone of the Ghostty source) can be used to build the xcframework.

### 6.2 Bridging Header

The bridging header (`tian/tian-Bridging-Header.h`) must be updated:

| Current Import | Target Import |
|----------------|---------------|
| `#import "Core/pty_helpers.h"` | (remove) |
| `#import <ghostty/vt.h>` | `#import "ghostty.h"` |
| `#import "Bridge/ghostty_helpers.h"` | (remove) |
| `#import "Renderer/ShaderTypes.h"` | (remove) |

### 6.3 Metal Shader Compilation

Currently the Xcode project compiles `Shaders.metal` and creates a default Metal library. After removing `Shaders.metal`, the Metal compilation step should be removed from the build settings. Ghostty ships its own Metal shaders internally within the library.

### 6.4 Xcode Project File Changes

The `tian.xcodeproj/project.pbxproj` requires:
- Remove all deleted source files from PBXBuildFile, PBXFileReference, and PBXGroup sections (including pty_helpers.c)
- Remove deleted test files from PBXBuildFile, PBXFileReference, and test target groups
- Add new source files (GhosttyApp.swift, GhosttyTerminalSurface.swift, TerminalSurfaceView.swift)
- Replace the vendor library reference
- Update HEADER_SEARCH_PATHS, LIBRARY_SEARCH_PATHS, OTHER_LDFLAGS
- Remove Shaders.metal from the Metal compilation sources

---

## 7. Callback and Delegate Patterns

### 7.1 Callback Context Pattern

Ghostty callbacks receive a `void* userdata` pointer. To safely bridge back to Swift objects:

1. **App-level userdata:** The `ghostty_runtime_config_s.userdata` points to the GhosttyApp singleton (via `Unmanaged.passUnretained(self).toOpaque()`). This is safe because the app outlives all callbacks.

2. **Surface-level userdata:** Each `ghostty_surface_config_s.userdata` points to a `SurfaceCallbackContext` instance (via `Unmanaged.passRetained(...).toOpaque()`). The retained reference ensures the context survives as long as the surface exists. On surface teardown, the retained reference is released via `callbackContext.release()`.

3. **Resolving in callbacks:** The read_clipboard_cb and write_clipboard_cb receive the surface's userdata (not the app's). The callback casts back to `SurfaceCallbackContext` via a static helper method (e.g., `GhosttyApp.callbackContext(from: userdata)`) and accesses the surface/view weakly. The clipboard callbacks should also verify the runtime surface is still the same one that initiated the request (matching cmux's `requestSurface` pattern).

### 7.2 Action Dispatch

The `action_cb` receives a `ghostty_target_s` (which identifies whether the action targets the app or a specific surface) and a `ghostty_action_s` (which contains a tag and union payload). The GhosttyApp.handleAction method should dispatch on the action tag:

**Important:** Check `target.tag` first. If `target.tag != GHOSTTY_TARGET_SURFACE`, handle app-level actions (RELOAD_CONFIG, CONFIG_CHANGE, COLOR_CHANGE, RING_BELL, DESKTOP_NOTIFICATION). If `target.tag == GHOSTTY_TARGET_SURFACE`, resolve the surface via `ghostty_surface_userdata(target.target.surface)`.

**Actions to handle initially:**
- `GHOSTTY_ACTION_SET_TITLE` -- Extract title string, post notification with surface ID and title
- `GHOSTTY_ACTION_RING_BELL` -- Call `NSSound.beep()`
- `GHOSTTY_ACTION_COLOR_CHANGE` (kind == GHOSTTY_ACTION_COLOR_KIND_BACKGROUND) -- Update window background color
- `GHOSTTY_ACTION_CELL_SIZE` -- Track cell size for future layout calculations
- `GHOSTTY_ACTION_MOUSE_SHAPE` -- Set appropriate NSCursor
- `GHOSTTY_ACTION_SHOW_CHILD_EXITED` -- Trigger surface close (dispatch async to avoid re-entrant close during callback). Always return true so Ghostty doesn't print "Press any key..." fallback.
- `GHOSTTY_ACTION_RELOAD_CONFIG` -- Reload config, update background
- `GHOSTTY_ACTION_CONFIG_CHANGE` -- Update background from new config

**Actions to ignore initially (but return true):**
- `GHOSTTY_ACTION_NEW_TAB`, `GHOSTTY_ACTION_NEW_SPLIT`, etc. -- Not implemented until M2/M3
- `GHOSTTY_ACTION_TOGGLE_FULLSCREEN`, `GHOSTTY_ACTION_TOGGLE_MAXIMIZE` -- Not in M1 scope

**Note:** `GHOSTTY_ACTION_RENDER` is present in the API but cmux does NOT handle it. Ghostty manages rendering internally via CVDisplayLink. Returning false (unhandled) is appropriate.

### 7.3 Wakeup and Tick

The `wakeup_cb` fires from ghostty's internal thread when it needs the host to process actions. The callback must dispatch `ghostty_app_tick()` to the main thread:

The tick function processes all pending actions and renders dirty surfaces. It should be called:
1. When wakeup_cb fires (dispatched to main)
2. Optionally on a timer for catch-up (cmux does not use a timer; wakeup-driven only)

### 7.4 Clipboard Flow

**Paste (read):**
1. Ghostty calls `read_clipboard_cb(userdata, location, state)` from its internal thread
2. Callback dispatches to main thread
3. Resolve the requesting surface from the callback context; capture a reference to verify it hasn't been replaced
4. Read clipboard: use `GhosttyPasteboardHelper.pasteboard(for: location)` pattern -- `GHOSTTY_CLIPBOARD_STANDARD` maps to `.general`, `GHOSTTY_CLIPBOARD_SELECTION` maps to a custom named pasteboard
5. Read `pasteboard.string(forType: .string)`
6. Calls `ghostty_surface_complete_clipboard_request(surface, cString, state, false)` on main thread -- verify the surface pointer still matches the original request surface

**Copy (write):**
1. Ghostty calls `write_clipboard_cb(userdata, location, content, len, confirm)`
2. Iterate the content buffer (array of `ghostty_clipboard_content_s` with `.mime` and `.data` fields)
3. Prefer `text/plain` MIME type; fall back to first non-nil entry
4. Write to appropriate NSPasteboard

---

## 8. Input Handling Details

### 8.1 Keyboard Events

The keyDown handler on TerminalSurfaceView must:

1. **Fast path for Ctrl-modified keys** (Ctrl+C, Ctrl+D, etc.): When `event.modifierFlags` contains `.control` but not `.command` or `.option`, and no marked text is active, bypass IME and send directly to `ghostty_surface_key()`. Build a `ghostty_input_key_s` struct:
   - `action` = `event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS`
   - `keycode` = `UInt32(event.keyCode)` -- raw macOS virtual keycode
   - `mods` = translated from `event.modifierFlags` using the modifier mapping
   - `consumed_mods` = `GHOSTTY_MODS_NONE` (ctrl keys don't consume mods for text)
   - `text` = `event.charactersIgnoringModifiers` or `event.characters`
   - `unshifted_codepoint` = first codepoint from `event.charactersIgnoringModifiers`
   - `composing` = false
   - If `ghostty_surface_key()` returns true (handled), done. If false, fall through to interpretKeyEvents.

2. **Normal path:** Use `ghostty_surface_key_translation_mods()` to translate modifiers according to ghostty's `macos-option-as-alt` config. If translation changes the modifiers, synthesize a new NSEvent with translated modifiers using `NSEvent.keyEvent(with:...)` for `interpretKeyEvents`.

3. **IME handling:** Call `interpretKeyEvents([translationEvent])`. This triggers the NSTextInputClient methods:
   - `insertText()` accumulates committed text
   - `setMarkedText()` updates preedit state
   After interpretation, call `syncPreedit()` to forward marked text to `ghostty_surface_preedit(surface, ptr, len)`.

4. **Build and send key event:** After interpretKeyEvents, build `ghostty_input_key_s`:
   - `composing` = true if marked text is active or was just cleared
   - If accumulated text exists from insertText, set `composing = false` and send each accumulated text via `ghostty_surface_key()` with `text` set
   - Otherwise, get text from `event.characters` and send to `ghostty_surface_key()`

5. **Cmd shortcuts:** Let the system handle them (call `super.keyDown(with: event)`)

### 8.2 IME (Input Method Editor)

The NSTextInputClient protocol implementation changes from the current pattern:

| Method | Current Behavior | Target Behavior |
|--------|-----------------|-----------------|
| `insertText(_:replacementRange:)` | Calls `onInput?(text)` | Accumulates text in `keyTextAccumulator` array for batch sending via `ghostty_surface_key()` after interpretKeyEvents returns |
| `setMarkedText(_:selectedRange:replacementRange:)` | Stores locally in `_markedText` | Stores locally (preedit sync happens after interpretKeyEvents via `syncPreedit()`) |
| `unmarkText()` | Clears `_markedText` | Clears locally (preedit sync happens after interpretKeyEvents via `syncPreedit()`) |
| `firstRect(forCharacterRange:actualRange:)` | Uses FontAtlas cell size | Uses `ghostty_surface_ime_point(surface, &x, &y, &w, &h)` for accurate cursor position. Note: ghostty returns top-left origin Y; convert to bottom-left for AppKit: `frame.size.height - y`. |

**syncPreedit implementation:**
- If `markedText.length > 0`: call `ghostty_surface_preedit(surface, cString, len)` where len is the UTF-8 byte count excluding null terminator
- If `markedText.length == 0` and clearIfNeeded: call `ghostty_surface_preedit(surface, nil, 0)` to clear preedit

### 8.3 Mouse Events

TerminalSurfaceView must forward all mouse events. Coordinates use NSView convention (origin bottom-left). The cmux reference shows the pattern:
- `ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, mods)` -- Y is flipped from NSView bottom-left to top-left
- `ghostty_surface_mouse_button(surface, state, button, mods)` -- returns bool (whether ghostty consumed it)
- `ghostty_surface_mouse_scroll(surface, x, y, scroll_mods)` -- for scroll wheel events
- `ghostty_surface_mouse_captured(surface)` -- check if mouse is captured by the terminal app (for right-click menu suppression)
- Send `ghostty_surface_mouse_pos(surface, -1, -1, mods)` on `mouseExited` to indicate the mouse has left the view

**Scroll mods structure (`ghostty_input_scroll_mods_t`):**
This is a packed `Int32`, NOT a standard modifier enum. The structure is:
- Bit 0: `precision` flag (1 if `event.hasPreciseScrollingDeltas` is true, i.e., trackpad)
- Bits 1+: momentum phase (shifted left by 1), using `ghostty_input_mouse_momentum_e` values

When `hasPreciseScrollingDeltas` is true, multiply both `scrollingDeltaX` and `scrollingDeltaY` by 2 before passing to ghostty.

**Mouse buttons handled:**
- Left: `mouseDown/Up/Dragged` with `GHOSTTY_MOUSE_LEFT`
- Right: `rightMouseDown/Up/Dragged` with `GHOSTTY_MOUSE_RIGHT`
- Middle: `otherMouseDown/Up/Dragged` (buttonNumber == 2) with `GHOSTTY_MOUSE_MIDDLE`

### 8.4 Key Mapping Simplification

The current code maps macOS keycodes to ghostty-vt key enums (e.g., `case 0: return GHOSTTY_KEY_A`). With the full API, this mapping is no longer needed in the host -- ghostty accepts raw macOS keycodes directly via `ghostty_input_key_s.keycode`. The key enum types are the same (GHOSTTY_KEY_A, etc.) but are now used internally by ghostty, not by the host.

However, the modifier mapping (NSEvent.ModifierFlags to ghostty_input_mods_e) is still needed and uses the same logic. The mapping in cmux:
- `.shift` -> `GHOSTTY_MODS_SHIFT`
- `.control` -> `GHOSTTY_MODS_CTRL`
- `.option` -> `GHOSTTY_MODS_ALT`
- `.command` -> `GHOSTTY_MODS_SUPER`

Note: `.capsLock` is NOT mapped in cmux's `modsFromEvent`, unlike the current tian code which maps it to `GHOSTTY_MODS_CAPS_LOCK` (which should be `GHOSTTY_MODS_CAPS`).

---

## 9. Surface Configuration

### 9.1 ghostty_surface_config_s Fields

When creating a surface, start with `ghostty_surface_config_new()` to get a default-initialized struct, then set:

| Field | Value | Notes |
|-------|-------|-------|
| platform_tag | GHOSTTY_PLATFORM_MACOS | Always macOS |
| platform.macos.nsview | Unmanaged.passUnretained(view).toOpaque() | The NSView that hosts the Metal layer. Use `ghostty_platform_u(macos: ghostty_platform_macos_s(nsview: ...))` |
| userdata | Unmanaged.passRetained(callbackContext).toOpaque() | Per-surface callback context |
| scale_factor | window.backingScaleFactor | Retina scaling (layer scale) |
| font_size | 0.0 (use config default) | Or specific size if overridden |
| working_directory | nil (use default) | Or specific path (set within withCString closure) |
| command | nil (use default shell) | Or specific command (set within withCString closure) |
| env_vars | nil | Or custom environment variables (ghostty_env_var_s array) |
| env_var_count | 0 | Number of env vars |
| initial_input | nil | |
| wait_after_command | false | |
| context | GHOSTTY_SURFACE_CONTEXT_WINDOW | For single-window terminal |

### 9.2 Post-Creation Setup

After `ghostty_surface_new()` returns a non-nil surface:

1. Set display ID: `ghostty_surface_set_display_id(surface, displayID)` -- needed for CVDisplayLink vsync. Get displayID from `window.screen?.displayID ?? NSScreen.main?.displayID`. The `displayID` property is a custom extension on NSScreen that reads from `deviceDescription["NSScreenNumber"]`.
2. Set content scale: `ghostty_surface_set_content_scale(surface, scaleFactor, scaleFactor)`
3. Set initial size: `ghostty_surface_set_size(surface, wpx, hpx)` -- backing pixel dimensions from `view.convertToBacking()`
4. Set focus: `ghostty_surface_set_focus(surface, true)` -- always sync unconditionally, don't rely on ghostty's default
5. Set color scheme: `ghostty_surface_set_color_scheme(surface, .dark)` (or based on system appearance)
6. Kick initial draw: `ghostty_surface_refresh(surface)` -- prevents blank frame on some startup paths

---

## 10. Configuration

### 10.1 Ghostty Config Loading

Ghostty has its own config system. The host loads config via:
1. `ghostty_config_new()` -- allocate
2. `ghostty_config_load_default_files(config)` -- load from `~/.config/ghostty/config`
3. `ghostty_config_finalize(config)` -- validate and resolve
4. Pass to `ghostty_app_new()`

For M1, the default ghostty config file controls font, colors, theme, and keybindings. No tian-specific config layer is needed.

### 10.2 Reading Config Values

Use `ghostty_config_get(config, &value, key, key_len)` to read specific values. Useful for:
- Background color (for window background synchronization)
- Font family/size (for UI display)
- Background opacity

### 10.3 Theme Handling

The hardcoded `DefaultTheme` (Tokyo Night Storm) is removed. Users configure their theme via the ghostty config file (e.g., `theme = tokyo-night-storm`). Ghostty ships hundreds of built-in themes. The window background color is derived from the config's background color via the action callback.

---

## 11. Performance Considerations

### 11.1 Improvements from Migration

- **Rendering quality:** Ghostty's renderer is production-grade with sub-pixel anti-aliasing, proper glyph positioning, ligature support, and GPU-accelerated rendering. The current custom renderer lacks these.
- **Memory efficiency:** Ghostty's internal font atlas uses a more sophisticated caching strategy than the current shelf-packing approach.
- **Thread management:** Ghostty's internal thread pool replaces the custom LargeStackThread and eliminates the snapshot lock contention between the VT processing thread and render thread.
- **Scrollback performance:** Ghostty implements efficient scrollback with lazy rendering, versus the current approach of re-extracting the full grid on every change.

### 11.2 Considerations

- **Library size:** The full ghostty library is significantly larger than libghostty-vt (includes Metal shaders, font subsystem, PTY management). Expect 5-15MB increase in binary size.
- **Startup time:** `ghostty_init()` initializes the rendering subsystem and may take 50-100ms. Ensure this happens before the first window appears (in TianApp's .task block).
- **Memory baseline:** Each surface allocates its own font atlas, scrollback buffer, and Metal resources. Baseline per-surface memory is higher than the current shared-renderer approach.

---

## 12. Migration and Deployment

### 12.1 Build the GhosttyKit Library

The `.ghostty-src` directory in the tian repo contains a shallow clone of the Ghostty source. To build the full library:

1. Navigate to `.ghostty-src`
2. Build libghostty for macOS arm64 using the Ghostty build system (Zig)
3. Package as an xcframework or copy the static library and header
4. Place in `tian/Vendor/`

Alternatively, use a pre-built GhosttyKit.xcframework from the Ghostty releases or build it from source using the Ghostty macOS Xcode project.

### 12.2 Migration Order

The migration must be atomic -- the old and new systems cannot coexist because they use different ghostty libraries with incompatible APIs. The recommended order within a single branch:

1. **Add the new vendor library** (GhosttyKit.xcframework or libghostty.a + ghostty.h)
2. **Create GhosttyApp.swift** with initialization and callbacks
3. **Create GhosttyTerminalSurface.swift** with surface lifecycle
4. **Create TerminalSurfaceView.swift** with input forwarding
5. **Rewrite TerminalContentView.swift** and TerminalWindow.swift
6. **Update TianApp.swift** to initialize GhosttyApp
7. **Update the bridging header**
8. **Delete all obsoleted files** (including pty_helpers.c and test files)
9. **Remove old vendor library**
10. **Update Xcode project** (add/remove files, update build settings)

### 12.3 Rollback Strategy

Since this is a complete replacement of the core layer:
- The migration should be done on a feature branch
- The old code (pre-migration commit) is the rollback point
- No feature flag is practical for this change -- the two APIs are fundamentally incompatible
- Regression testing against the pre-migration branch validates correctness

---

## 13. Implementation Phases

### Phase 1: Foundation (GhosttyApp + Surface Lifecycle)

**Goal:** Replace the entire PTY, VT, and rendering stack. A terminal that launches a shell, displays output, and accepts keyboard input.

**Tasks:**
1. Build and integrate the full ghostty library
2. Implement GhosttyApp.swift (init, config, app creation, wakeup/tick, app focus tracking, minimal action handling)
3. Implement GhosttyTerminalSurface.swift (surface creation, size, scale, focus, display ID, color scheme, refresh)
4. Implement TerminalSurfaceView.swift (CAMetalLayer with correct properties, keyboard forwarding via ghostty_surface_key, NSScreen.displayID extension)
5. Rewrite TerminalContentView.swift (simplified NSViewRepresentable)
6. Rewrite TerminalWindow.swift (use GhosttyTerminalSurface)
7. Update TianApp.swift (initialize GhosttyApp)
8. Delete all obsoleted files (16 source files + 3 test files)
9. Update bridging header and build settings

**Acceptance criteria:**
- Shell launches and displays prompt
- Typing produces visible output
- Commands execute (ls, echo, etc.)
- Terminal resizes correctly with the window
- Cursor blinks and moves correctly
- Colors display correctly (ANSI 16-color, 256-color, true color)
- Ctrl+C, Ctrl+D work
- Scrollback works (scroll wheel)

### Phase 2: Complete Input (Mouse + IME)

**Goal:** Full input handling including mouse events and CJK IME.

**Tasks:**
1. Implement all mouse event forwarding (click, drag, scroll with proper scroll_mods packing, right-click, middle-click)
2. Implement ghostty_surface_mouse_captured() for right-click menu suppression
3. Implement NSTextInputClient with syncPreedit pattern (ghostty_surface_preedit)
4. Implement firstRect using ghostty_surface_ime_point with Y-coordinate flip
5. Handle option-as-alt via ghostty_surface_key_translation_mods with NSEvent synthesis
6. Implement keyTextAccumulator pattern for batched IME text insertion

**Acceptance criteria:**
- Mouse selection works in terminal
- Mouse-aware apps (vim, htop, less) respond to clicks
- CJK input methods work correctly
- Option+key produces correct characters based on ghostty config

### Phase 3: Clipboard + Actions

**Goal:** Full clipboard integration and action handling.

**Tasks:**
1. Implement read_clipboard_cb with surface verification pattern
2. Implement write_clipboard_cb with MIME-type content iteration
3. Implement confirm_read_clipboard_cb for OSC 52
4. Handle GHOSTTY_ACTION_SET_TITLE (window title)
5. Handle GHOSTTY_ACTION_RING_BELL
6. Handle GHOSTTY_ACTION_COLOR_CHANGE (window background sync)
7. Handle GHOSTTY_ACTION_SHOW_CHILD_EXITED (async close to avoid re-entrant teardown)
8. Handle GHOSTTY_ACTION_MOUSE_SHAPE (cursor shape)
9. Handle GHOSTTY_ACTION_RELOAD_CONFIG and GHOSTTY_ACTION_CONFIG_CHANGE

**Acceptance criteria:**
- Cmd+C/Cmd+V copies/pastes (via ghostty keybindings, not manual)
- Terminal selection copies to clipboard
- Window title updates based on shell (e.g., running command)
- BEL character produces system sound
- Window background matches ghostty theme
- Shell exit shows appropriate behavior (closes pane, no "Press any key" prompt)

---

## 14. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| GhosttyKit.xcframework not available for tian's macOS 26 target | Blocking | Low | Build from source using `.ghostty-src`. The Ghostty build system supports macOS targets. |
| ghostty.h API differences between Ghostty versions | High | Medium | Pin to a specific Ghostty commit/tag. The `.ghostty-src` provides version control. Verify header matches built library. |
| Metal layer configuration mismatch (ghostty expects specific layer properties) | Medium | Medium | Match cmux's GhosttyNSView.makeBackingLayer() exactly: bgra8Unorm, framebufferOnly=false, isOpaque=false. |
| Display link / vsync issues on first frame | Medium | Medium | Set display ID immediately after surface creation (before resize). Call `ghostty_surface_refresh()` after setup. Match cmux's pattern of falling back to NSScreen.main if window screen is nil. |
| Callback lifetime issues (use-after-free on surface teardown) | High | Medium | Use the SurfaceCallbackContext pattern with weak references. Release the retained context on surface free. Guard all callback context access with nil checks. Verify surface pointer matches request surface in clipboard callbacks. |
| Large binary size increase from full ghostty library | Low | High | Expected and acceptable for M1. Optimize later if needed. |
| Config file format unfamiliar to users | Low | Low | Document ghostty config location (~/.config/ghostty/config) and key settings. Ship a default config for tian. |
| ghostty_surface_key() returns false for keys it doesn't handle | Medium | Low | Fall through to interpretKeyEvents for IME processing, matching cmux's pattern. |
| NSScreen.displayID not a standard property | Low | Low | Implement as extension reading from `deviceDescription["NSScreenNumber"]` with type coercion fallbacks, matching cmux pattern. |
| Scroll mods packed struct misuse | Medium | Medium | Use `ghostty_input_scroll_mods_t` (packed Int32) with precision bit 0 and momentum phase bits 1+. Do NOT pass `ghostty_input_mods_e`. |

---

## 15. Testing Approach

### 15.1 Manual Testing Checklist

1. **Basic I/O:** Launch shell, type commands, verify output
2. **Special keys:** Enter, Tab, Backspace, Delete, Arrow keys, Home/End, Page Up/Down, Escape
3. **Modifiers:** Ctrl+C (SIGINT), Ctrl+D (EOF), Ctrl+Z (SIGTSTP), Ctrl+L (clear)
4. **TUI apps:** vim, htop, less, tmux -- verify rendering and input
5. **Colors:** Run a color test script (256-color, true-color gradients)
6. **Unicode:** Wide characters (CJK), combining characters, emoji
7. **Resize:** Resize window, verify terminal reflows correctly
8. **Scrollback:** Scroll up/down, verify content preservation
9. **Mouse:** Click in vim/less, scroll in mouse-aware apps
10. **Selection:** Select text with mouse drag, verify selection highlight
11. **Copy/Paste:** Cmd+C copies selection, Cmd+V pastes
12. **Theme:** Apply different ghostty themes, verify colors update
13. **Cursor:** Verify block/bar/underline cursor styles, blinking
14. **Shell exit:** Exit shell (exit command, Ctrl+D), verify cleanup (no "Press any key" prompt)
15. **Retina:** Test on Retina display, verify crisp text rendering

### 15.2 Automated Tests

- **GhosttyApp initialization:** Verify ghostty_init and app creation succeed
- **Surface lifecycle:** Create surface, verify non-nil, free surface
- **ANSIStripper:** Existing tests remain valid (utility not changed)
- **Key event construction:** Unit test ghostty_input_key_s struct building from NSEvent mock data

### 15.3 Regression Testing

Compare rendering quality and behavior against:
1. The current tian (pre-migration)
2. The standalone Ghostty terminal app
3. The cmux terminal

---

## 16. Open Technical Questions

| Question | Context | Impact if Unresolved |
|----------|---------|---------------------|
| Should tian build GhosttyKit from .ghostty-src or use a pre-built artifact? | The .ghostty-src directory exists but building requires Zig toolchain. Pre-built xcframeworks are available from Ghostty releases. | Build system complexity vs. reproducibility. Recommend building from source for version control. |
| What GHOSTTY_RESOURCES_DIR should tian set? | Ghostty uses this env var for shell integration scripts, terminfo, etc. cmux bundles these in its app bundle. | Shell integration (ghostty shell features) won't work without correct resources. Copy resources from .ghostty-src to app bundle. |
| Should tian ship a default ghostty config or rely on user's existing config? | Users who already use Ghostty will have a config. New users won't. | New users get Ghostty defaults (which may differ from the Tokyo Night Storm theme currently hardcoded). Consider shipping a default tian config. |
| How to handle GHOSTTY_ACTION_NEW_TAB and GHOSTTY_ACTION_NEW_SPLIT before M2/M3? | Ghostty may fire these actions based on keybindings in the user's config. | Return false (unhandled) so ghostty falls back. Or return true to silently consume. |
| Should env vars like TERM_PROGRAM be set to "tian" or "ghostty"? | Ghostty sets TERM_PROGRAM=ghostty internally. tian may want its own identity. | Shell scripts checking TERM_PROGRAM may behave unexpectedly. Can be overridden via surface config env_vars. |
| Should capsLock be mapped to GHOSTTY_MODS_CAPS? | Current tian code maps `.capsLock` to modifier flags but cmux's `modsFromEvent` does NOT map capsLock. The ghostty header defines `GHOSTTY_MODS_CAPS`. | Minor input handling difference. Follow cmux's pattern (omit capsLock) unless there's a reason to include it. |

---

## 17. Validation Notes

**Validation performed on:** 2026-03-26
**Validated against:** tian codebase at `/Users/psycoder/00_Code/00_Personal_Project/tian` and cmux reference at `/tmp/cmux`

### Corrections Made

1. **Missing file: Core/pty_helpers.c** -- A 31-line C implementation file was completely missing from the file inventory (section 2.1) and deletion list (section 5.1). Added to both.

2. **File count in section 5.1** -- Heading said "11 files" but listed 15 files. Corrected to 16 files (including newly added pty_helpers.c).

3. **Line counts** -- Systematically corrected all line counts. The original spec was off by one for most files (likely not counting trailing newlines). Each count now matches the actual file as read via `cat -n`.

4. **Missing test files** -- Added `tianTests/PTYProcessTests.swift`, `tianTests/PTYIntegrationTests.swift`, and `tianTests/GhosttyBridgeTests.swift` to the deletion list. These test files test code being removed and need cleanup.

5. **ghostty_surface_mouse_scroll parameter type** -- Section 4.5 and 8.3 originally described the scroll mods parameter as `mods` (suggesting `ghostty_input_mods_e`). Corrected to `ghostty_input_scroll_mods_t` which is a packed `Int32` containing a precision flag (bit 0) and momentum phase (bits 1+). Added detailed documentation of the packing format.

6. **Missing ghostty_app_set_focus()** -- The spec did not mention `ghostty_app_set_focus()` which cmux calls on app activation/deactivation. Added to GhosttyApp responsibilities and section 3.1.

7. **Missing ghostty_surface_refresh()** -- cmux calls `ghostty_surface_refresh()` after surface creation to kick an initial draw. Added to post-creation setup (section 9.2) and surface lifecycle.

8. **Missing supports_selection_clipboard** -- The `ghostty_runtime_config_s.supports_selection_clipboard` field was not documented. Added to section 4.8.

9. **Missing ghostty_surface_config_new()** -- cmux uses `ghostty_surface_config_new()` to get a default-initialized config struct. Added to section 9.1.

10. **NSScreen.displayID is not standard** -- Added note that this requires a custom extension reading from `deviceDescription["NSScreenNumber"]` with type coercion, matching the cmux implementation.

11. **GHOSTTY_ACTION_RENDER handling** -- Clarified that cmux does NOT handle GHOSTTY_ACTION_RENDER. Ghostty manages rendering internally via CVDisplayLink.

12. **Clipboard write_cb content iteration** -- Clarified that the content parameter is an array of `ghostty_clipboard_content_s` items with MIME types, and the implementation should prefer `text/plain`.

13. **GHOSTTY_ACTION_SHOW_CHILD_EXITED async handling** -- Added note from cmux pattern: close must be dispatched async to avoid re-entrant close during the action callback, and always return true to suppress ghostty's "Press any key..." fallback.

14. **consumed_mods behavior** -- Clarified per cmux: only shift and option are ever set in consumed_mods; ctrl and cmd are never consumed for text translation.

15. **Action dispatch target checking** -- Added guidance to check `target.tag` before resolving surface, handling app-level vs surface-level actions differently.

16. **makeBackingLayer properties** -- Corrected: `framebufferOnly` must be `false` (not `true` as in current tian). Current tian sets `framebufferOnly = true` but the ghostty API requires `false` for background opacity/blur compositing.

17. **TerminalCore.swift description** -- Corrected to note that it's 221 lines and includes the TerminalBridge facade class, not just the TerminalCore class.

18. **IME pattern** -- Updated to describe cmux's actual pattern: keyTextAccumulator for batched text insertion, syncPreedit as post-interpretKeyEvents step rather than inline.

### Verified as Correct

- All API function names verified against `/tmp/cmux/ghostty.h`: `ghostty_init`, `ghostty_config_new`, `ghostty_config_load_default_files`, `ghostty_config_finalize`, `ghostty_app_new`, `ghostty_app_tick`, `ghostty_surface_new`, `ghostty_surface_free`, `ghostty_surface_key`, `ghostty_surface_mouse_pos`, `ghostty_surface_mouse_button`, `ghostty_surface_mouse_captured`, `ghostty_surface_preedit`, `ghostty_surface_ime_point`, `ghostty_surface_set_size`, `ghostty_surface_set_content_scale`, `ghostty_surface_set_focus`, `ghostty_surface_set_display_id`, `ghostty_surface_set_color_scheme`, `ghostty_surface_key_translation_mods`, `ghostty_surface_complete_clipboard_request`, `ghostty_surface_request_close`
- `ghostty_input_key_s` struct fields verified against header: action, mods, consumed_mods, keycode, text, unshifted_codepoint, composing
- `ghostty_runtime_config_s` struct fields verified against header
- `ghostty_surface_config_s` struct fields verified against header
- All GHOSTTY_ACTION_* enum values verified against header
- Callback context pattern (Unmanaged.passRetained for surface, Unmanaged.passUnretained for app) matches cmux
- All files listed for deletion exist in the actual codebase
- All files listed for modification exist in the actual codebase
- Current data flow description matches actual code structure
- Implementation phases are properly sequenced with no circular dependencies
