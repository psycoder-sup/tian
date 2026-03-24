# SPEC: M6 -- Configuration and Customization

**Based on:** docs/feature/aterm/aterm-prd.md v1.4 (FR-26 through FR-31, FR-43 pane resize config)
**Author:** CTO Agent
**Date:** 2026-03-24
**Version:** 1.0
**Status:** Draft

---

## 1. Overview

Milestone 6 delivers aterm's user-facing configuration system. Users author one or more TOML files to define color themes, named profiles (font, colors, shell, working directory), custom keybindings, and global settings. The configuration follows a three-tier inheritance model (global defaults, workspace override, space override) so that a single file can control the entire app while allowing per-project visual identity. A file-watcher detects edits and applies changes live, without an app restart.

This spec covers the TOML schema, data models, parsing pipeline, profile resolution algorithm, keybinding system, theme model, file-watching mechanism, and integration points with M1-M5 components. It does not cover a GUI settings panel -- all configuration is file-driven per FR-26.

---

## 2. Configuration File Locations

### File Hierarchy

| Priority | Path | Purpose |
|----------|------|---------|
| 1 (highest) | `~/.config/aterm/config.toml` | Primary user configuration |
| 2 (fallback) | `~/Library/Application Support/aterm/config.toml` | macOS-conventional location |

The app checks for the XDG-style path first. If neither file exists, the app operates with compiled-in defaults. If both exist, only the XDG-style path is loaded (no merging across locations).

### Supporting Files

| Path | Purpose |
|------|---------|
| `~/.config/aterm/themes/` | Directory for user-defined theme TOML files (one file per theme) |
| `<App Bundle>/Resources/themes/` | Directory for bundled default themes shipped with the app |

Theme files are named `<theme-name>.toml`. User themes override bundled themes when names collide.

---

## 3. TOML Schema Design

### Top-Level Structure

The configuration file has the following top-level sections:

```
[global]                     -- Global defaults (font, shell, scrollback, etc.)
[global.keybindings]         -- Custom keybinding overrides

[theme.<name>]               -- Named color theme definitions (inline)

[profile.<name>]             -- Named profile definitions

[workspace.<name>]           -- Per-workspace overrides
[workspace.<name>.space.<name>]  -- Per-space overrides within a workspace
```

### Section: `[global]`

Global defaults that apply to all panes unless overridden by a profile assignment.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `font_family` | String | `"SF Mono"` | Font family name for terminal text |
| `font_size` | Float | `13.0` | Font size in points |
| `theme` | String | `"aterm-dark"` | Name of the color theme to use |
| `shell` | String | Value of `$SHELL` | Shell program path |
| `shell_args` | Array of String | `["--login"]` | Arguments passed to the shell |
| `working_directory` | String | `"$HOME"` | Default working directory for new panes |
| `scrollback_lines` | Integer | `10000` | Scrollback buffer size per pane |
| `cursor_style` | String | `"block"` | One of: `"block"`, `"underline"`, `"bar"` |
| `cursor_blink` | Boolean | `true` | Whether cursor blinks |
| `cursor_blink_interval_ms` | Integer | `530` | Blink interval in milliseconds |
| `window_opacity` | Float | `1.0` | Window background opacity (0.0 to 1.0) |
| `pane_split_ratio` | Float | `0.5` | Default ratio when splitting a pane (0.0 to 1.0) |
| `confirm_quit_with_processes` | Boolean | `true` | Show quit confirmation when foreground processes are running |

### Section: `[global.keybindings]`

Key-value pairs where keys are action names and values are key chord strings.

| Key (action name) | Type | Default | Description |
|-------------------|------|---------|-------------|
| `workspace_create` | String | `"cmd+shift+n"` | Create new workspace |
| `workspace_switch` | String | `"cmd+shift+w"` | Open workspace switcher (fuzzy search overlay) |
| `workspace_close` | String | `"cmd+shift+backspace"` | Close current workspace |
| `space_create` | String | `"cmd+shift+t"` | Create new space |
| `space_next` | String | `"cmd+shift+right"` | Switch to next space |
| `space_prev` | String | `"cmd+shift+left"` | Switch to previous space |
| `tab_create` | String | `"cmd+t"` | Create new tab |
| `tab_next` | String | `"cmd+shift+]"` | Switch to next tab |
| `tab_prev` | String | `"cmd+shift+["` | Switch to previous tab |
| `tab_goto_N` | String | `"cmd+<N>"` | Switch to tab N (1-9) |
| `pane_split_horizontal` | String | `"cmd+shift+d"` | Split pane horizontally (left/right) |
| `pane_split_vertical` | String | `"cmd+shift+e"` | Split pane vertically (top/bottom) |
| `pane_focus_up` | String | `"cmd+alt+up"` | Move focus to pane above |
| `pane_focus_down` | String | `"cmd+alt+down"` | Move focus to pane below |
| `pane_focus_left` | String | `"cmd+alt+left"` | Move focus to pane left |
| `pane_focus_right` | String | `"cmd+alt+right"` | Move focus to pane right |
| `pane_close` | String | `"cmd+w"` | Close focused pane. Cascading: last pane closes tab, last tab closes space, last space closes workspace, last workspace quits app. |
| `copy` | String | `"cmd+c"` | Copy selection to clipboard |
| `paste` | String | `"cmd+v"` | Paste from clipboard |
| `find` | String | `"cmd+f"` | Open find-in-scrollback |
| `reload_config` | String | `"cmd+shift+,"` | Manually reload configuration |

Note: Pane resize has no default keyboard shortcuts -- resize is mouse drag-handle only (per M2). Users may add custom resize bindings if desired by configuring `pane_resize_up`, `pane_resize_down`, `pane_resize_left`, `pane_resize_right` actions. There is no dedicated `tab_close` or `space_close` shortcut; closing is always via `pane_close` (Cmd+W) with cascading behavior.

Key chord format: Modifiers and key name joined by `+`. Modifiers are `cmd`, `ctrl`, `alt` (Option), `shift`. Key names use lowercase letters, digits, or named keys (`up`, `down`, `left`, `right`, `backspace`, `tab`, `return`, `escape`, `space`, `delete`, `home`, `end`, `pageup`, `pagedown`, `f1`-`f20`, and punctuation characters).

### Section: `[theme.<name>]`

Named color themes can be defined inline in the main config or as standalone files in the themes directory. The schema is identical either way.

| Key | Type | Description |
|-----|------|-------------|
| `foreground` | String (hex) | Default text color, e.g. `"#c0caf5"` |
| `background` | String (hex) | Default background color |
| `cursor` | String (hex) | Cursor color |
| `cursor_text` | String (hex) | Text color under cursor |
| `selection` | String (hex) | Selection highlight color |
| `selection_text` | String (hex) | Text color within selection |
| `black` | String (hex) | ANSI color 0 |
| `red` | String (hex) | ANSI color 1 |
| `green` | String (hex) | ANSI color 2 |
| `yellow` | String (hex) | ANSI color 3 |
| `blue` | String (hex) | ANSI color 4 |
| `magenta` | String (hex) | ANSI color 5 |
| `cyan` | String (hex) | ANSI color 6 |
| `white` | String (hex) | ANSI color 7 |
| `bright_black` | String (hex) | ANSI color 8 |
| `bright_red` | String (hex) | ANSI color 9 |
| `bright_green` | String (hex) | ANSI color 10 |
| `bright_yellow` | String (hex) | ANSI color 11 |
| `bright_blue` | String (hex) | ANSI color 12 |
| `bright_magenta` | String (hex) | ANSI color 13 |
| `bright_cyan` | String (hex) | ANSI color 14 |
| `bright_white` | String (hex) | ANSI color 15 |
| `palette` | Array of String (hex) | Optional extended 256-color palette override (indices 16-255). If omitted, standard xterm palette is used. |

Standalone theme files are plain TOML with these keys at the top level (no `[theme.<name>]` wrapper needed -- the filename is the theme name).

### Section: `[profile.<name>]`

Named profiles bundle a subset of rendering and shell settings. Any key omitted falls through to global defaults.

| Key | Type | Description |
|-----|------|-------------|
| `font_family` | String | Font family override |
| `font_size` | Float | Font size override |
| `theme` | String | Theme name override |
| `shell` | String | Shell program override |
| `shell_args` | Array of String | Shell arguments override |
| `working_directory` | String | Working directory override |
| `cursor_style` | String | Cursor style override |
| `cursor_blink` | Boolean | Cursor blink override |
| `scrollback_lines` | Integer | Scrollback buffer size override |

### Section: `[workspace.<name>]`

Per-workspace overrides. The workspace name must match the workspace's display name exactly.

| Key | Type | Description |
|-----|------|-------------|
| `profile` | String | Name of a defined profile to apply to this workspace |
| `working_directory` | String | Default working directory for this workspace |

### Section: `[workspace.<name>.space.<name>]`

Per-space overrides within a workspace. The space name must match exactly.

| Key | Type | Description |
|-----|------|-------------|
| `profile` | String | Name of a defined profile to apply to this space |
| `working_directory` | String | Default working directory for this space |

---

## 4. Profile Inheritance and Resolution

### Inheritance Chain

When a pane needs its effective configuration, the system resolves values through this chain (first non-nil wins):

1. **Space-level profile** -- if the pane's space has a `[workspace.X.space.Y]` entry with a `profile`, look up that profile's value
2. **Space-level working directory** -- direct `working_directory` on the space entry
3. **Workspace-level profile** -- if the pane's workspace has a `[workspace.X]` entry with a `profile`, look up that profile's value
4. **Workspace-level working directory** -- direct `working_directory` on the workspace entry
5. **Global defaults** -- values from `[global]`
6. **Compiled-in defaults** -- hardcoded fallbacks in the app binary

Each configuration key is resolved independently. A space-level profile might override `font_family` but leave `theme` unset, in which case `theme` continues falling through to workspace-level, then global.

### Resolution Algorithm

The configuration manager exposes a single method that takes a workspace name and space name and returns a fully resolved configuration struct with every key populated. The resolution performs a per-key merge in the order above. The result is cached and invalidated on config reload.

### Resolution Data Flow

User edits config.toml, then file watcher fires, then TOML is re-parsed, then all resolution caches are invalidated, then each visible pane queries its resolved config, then the renderer and PTY settings are updated to reflect new values.

---

## 5. Data Models

### ConfigDocument

The top-level parsed representation of the entire configuration file.

| Field | Type | Description |
|-------|------|-------------|
| `global` | GlobalConfig | Global settings |
| `keybindings` | Dictionary of String to String | Action name to key chord string |
| `themes` | Dictionary of String to ThemeConfig | Inline-defined themes, keyed by name |
| `profiles` | Dictionary of String to ProfileConfig | Named profiles |
| `workspaces` | Dictionary of String to WorkspaceConfig | Per-workspace overrides |

### GlobalConfig

| Field | Type | Description |
|-------|------|-------------|
| `fontFamily` | String? | Font family |
| `fontSize` | Float? | Font size |
| `theme` | String? | Active theme name |
| `shell` | String? | Shell path |
| `shellArgs` | Array of String? | Shell arguments |
| `workingDirectory` | String? | Default working directory |
| `scrollbackLines` | Int? | Scrollback buffer size |
| `cursorStyle` | CursorStyle? | Cursor style enum |
| `cursorBlink` | Bool? | Cursor blink toggle |
| `cursorBlinkIntervalMs` | Int? | Blink interval |
| `windowOpacity` | Float? | Window opacity |
| `paneSplitRatio` | Float? | Default split ratio |
| `confirmQuitWithProcesses` | Bool? | Quit confirmation toggle |

All fields are optional to distinguish "not set" from "set to default". The compiled-in defaults fill any gaps.

### ProfileConfig

Same fields as GlobalConfig minus `windowOpacity`, `paneSplitRatio`, and `confirmQuitWithProcesses` (those are global-only, not profile-scoped).

### ThemeConfig

| Field | Type | Description |
|-------|------|-------------|
| `foreground` | HexColor | Default text color |
| `background` | HexColor | Default background color |
| `cursor` | HexColor | Cursor color |
| `cursorText` | HexColor | Text color under cursor |
| `selection` | HexColor | Selection highlight color |
| `selectionText` | HexColor | Selection text color |
| `ansiColors` | Array of HexColor (length 16) | ANSI colors 0-15 (black, red, green, yellow, blue, magenta, cyan, white, then bright variants) |
| `palette` | Array of HexColor? (length 240) | Optional extended palette (indices 16-255) |

`HexColor` is a value type wrapping a validated 6- or 8-character hex string, parsed into RGBA components for GPU consumption.

### WorkspaceConfig

| Field | Type | Description |
|-------|------|-------------|
| `profile` | String? | Profile name reference |
| `workingDirectory` | String? | Working directory override |
| `spaces` | Dictionary of String to SpaceConfig | Per-space overrides |

### SpaceConfig

| Field | Type | Description |
|-------|------|-------------|
| `profile` | String? | Profile name reference |
| `workingDirectory` | String? | Working directory override |

### ResolvedPaneConfig

The fully resolved configuration for a single pane -- every field is non-optional.

| Field | Type | Description |
|-------|------|-------------|
| `fontFamily` | String | Resolved font family |
| `fontSize` | Float | Resolved font size |
| `theme` | ThemeConfig | Resolved theme (fully populated) |
| `shell` | String | Resolved shell path |
| `shellArgs` | Array of String | Resolved shell arguments |
| `workingDirectory` | String | Resolved working directory |
| `scrollbackLines` | Int | Resolved scrollback size |
| `cursorStyle` | CursorStyle | Resolved cursor style |
| `cursorBlink` | Bool | Resolved cursor blink |
| `cursorBlinkIntervalMs` | Int | Resolved blink interval |

### KeybindingMap

| Field | Type | Description |
|-------|------|-------------|
| `bindings` | Dictionary of KeyChord to ActionIdentifier | Maps parsed key chords to action identifiers |

`KeyChord` is a value type containing a set of modifier flags (cmd, ctrl, alt, shift) and a key identifier. `ActionIdentifier` is a string enum matching the action names from the keybinding table.

### CursorStyle

An enum with cases: `block`, `underline`, `bar`.

---

## 6. TOML Parsing Pipeline

### Library Choice

Use **TOMLKit** (github.com/LebJe/TOMLKit) via Swift Package Manager. Rationale:

- Supports both encoding and decoding (important if the app ever needs to write config, e.g., generating a default file)
- Full Codable protocol support, enabling direct decoding into the data model structs
- Actively maintained with 18+ releases
- Supports TOML 1.0
- Cross-platform (macOS, Linux, Windows) though only macOS matters here

Alternative considered: **TOMLDecoder** (github.com/dduan/TOMLDecoder) -- faster benchmarks, TOML 1.1, but decode-only (no encoding). If encoding is never needed, this is also a good choice. The engineering team should evaluate both and choose based on compile-time impact and API ergonomics.

### Parsing Pipeline

1. **Locate config file** -- Check XDG path, then macOS Application Support path. If neither exists, use compiled-in defaults only.
2. **Read file contents** -- Read the TOML file as a UTF-8 string.
3. **Decode into ConfigDocument** -- Use TOMLKit's `TOMLDecoder` to decode into the `ConfigDocument` struct via Codable conformance. Custom `CodingKeys` handle the snake_case TOML keys to camelCase Swift mapping.
4. **Load external themes** -- Scan both the user themes directory and the bundled themes directory. For each `.toml` file, decode into `ThemeConfig`. User themes override bundled themes by name.
5. **Merge themes** -- Combine inline themes from the config document with external theme files into a single theme registry.
6. **Validate** -- Run validation rules (see below). Collect all errors rather than failing on the first.
7. **Build keybinding map** -- Parse each key chord string into a `KeyChord` value, merge with defaults (user bindings override defaults, unmentioned actions keep default bindings).
8. **Publish** -- Store the validated `ConfigDocument` and theme registry in the `ConfigurationManager` and notify observers.

### Validation Rules

| Rule | Error behavior |
|------|---------------|
| Theme referenced by `global.theme` or a profile's `theme` must exist in the theme registry | Warning log, fall back to built-in default theme |
| Profile referenced by a workspace or space config must exist in the profiles dictionary | Warning log, ignore the profile assignment |
| Hex color strings must be valid 6-digit or 8-digit hex (with `#` prefix) | Warning log, use magenta (`#FF00FF`) as a visible sentinel |
| Font family must be a name resolvable by Core Text | Warning log, fall back to `"SF Mono"` |
| `font_size` must be between 6.0 and 72.0 | Clamp to range |
| `scrollback_lines` must be between 0 and 1,000,000 | Clamp to range |
| `window_opacity` must be between 0.0 and 1.0 | Clamp to range |
| `pane_split_ratio` must be between 0.1 and 0.9 | Clamp to range |
| `cursor_style` must be one of `"block"`, `"underline"`, `"bar"` | Warning log, fall back to `"block"` |
| Key chord strings must parse into valid modifier+key combinations | Warning log, skip the binding (action retains default) |
| Duplicate key chords (two actions bound to the same chord) | Warning log, last-defined wins |
| Shell path must be an absolute path or resolvable via `$PATH` | Warning log, fall back to `/bin/zsh` |

All validation warnings are logged to the debug log and, on first occurrence after reload, shown as a transient notification in the app (e.g., a brief overlay message "Config warning: theme 'dracula' not found, using default").

---

## 7. Keybinding System Architecture

### Overview

The keybinding system translates macOS keyboard events into aterm actions. It replaces any hardcoded keyboard handling from M1-M5 with a configurable, data-driven dispatch.

### Key Chord Parsing

The parser converts a string like `"cmd+shift+d"` into a `KeyChord` struct:
- Split on `+`
- Classify each segment as a modifier (`cmd`, `ctrl`, `alt`, `shift`) or a key name
- The last non-modifier segment is the key; all preceding segments are modifiers
- Reject chords with no key, duplicate modifiers, or unrecognized key names

### Dispatch Architecture

The keybinding system integrates into the SwiftUI/AppKit event handling chain:

1. **KeybindingDispatcher** -- A singleton that holds the current `KeybindingMap`. It is registered as a key event monitor at the application level (using `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`).
2. When a key-down event arrives, the dispatcher constructs a `KeyChord` from the event's modifier flags and key code.
3. It looks up the chord in the `KeybindingMap`. If found, it dispatches the corresponding `ActionIdentifier` to the **ActionRouter**.
4. The **ActionRouter** maps action identifiers to closures/methods on the appropriate managers (WorkspaceManager, PaneManager, etc. from M1-M5).
5. If the chord is not in the map, the event passes through to the terminal (normal key input).

### Conflict Resolution

- aterm keybindings take priority over terminal input. If `cmd+c` is bound to copy, the terminal never sees `cmd+c`.
- To send a chord to the terminal instead, the user must unbind it by setting the action to an empty string (e.g., `copy = ""`), which removes the binding and lets the key event pass through.
- System-level shortcuts (Cmd+Q, Cmd+H, Cmd+M) are handled by macOS before aterm sees them. The keybinding system does not override these.

### Reserved vs. Configurable Actions

All actions listed in the keybinding table (Section 3) are configurable. The set of action names is fixed (defined by the `ActionIdentifier` enum). Users cannot define new actions -- they can only rebind existing ones.

---

## 8. Theme System

### Theme Loading

Themes are loaded from three sources, in order of priority:

1. **Inline themes** in `config.toml` under `[theme.<name>]` (highest priority)
2. **User theme files** in `~/.config/aterm/themes/<name>.toml`
3. **Bundled theme files** in `<App Bundle>/Resources/themes/<name>.toml` (lowest priority)

When names collide, higher-priority sources win entirely (no per-key merging between theme sources).

### Bundled Themes

The app ships with at least two bundled themes:

| Theme Name | Style | Description |
|------------|-------|-------------|
| `aterm-dark` | Dark | Default dark theme, similar to Tokyo Night / One Dark aesthetic |
| `aterm-light` | Light | Default light theme for bright environments |

### Theme Validation

Every theme must define all 16 ANSI colors plus foreground, background, cursor, cursor_text, selection, and selection_text. If any required key is missing, the theme is rejected with a warning and the default theme is used instead. The optional `palette` array (extended 256 colors) falls back to the standard xterm extended palette if omitted.

### Theme Application

When the resolved theme changes for a pane (due to config reload or workspace/space switch):

1. The new theme's colors are uploaded to the Metal renderer's uniform buffer
2. The font atlas is not regenerated (themes do not affect fonts -- that is a separate profile concern)
3. The terminal's existing cell grid is re-rendered with the new colors on the next frame
4. The change is visually immediate (single frame latency)

---

## 9. File Watching and Live Reload

### Mechanism

Use `DispatchSource.makeFileSystemObjectSource` to monitor the active configuration file. This is a lightweight kernel-level notification (kqueue) that does not poll.

### Watched Paths

| Path | Events Watched | Purpose |
|------|---------------|---------|
| Config file (e.g., `~/.config/aterm/config.toml`) | `.write`, `.rename`, `.delete` | Detect config edits |
| User themes directory (`~/.config/aterm/themes/`) | `.write` | Detect theme file changes |

Note: `DispatchSource` monitors file descriptors, so if the file is deleted and recreated (common with some editors that use atomic writes via rename), the watcher must detect `.rename` or `.delete` and re-establish the watch on the new file.

### Reload Pipeline

1. File system event fires
2. Debounce: wait 200ms after the last event before processing (editors may write multiple times in quick succession)
3. Re-run the full parsing pipeline (Section 6)
4. Diff the new `ConfigDocument` against the previous one to determine what changed
5. For each change category, notify the appropriate subsystem:

| Change Category | Subsystem Notified | Effect |
|-----------------|-------------------|--------|
| Theme colors changed | Metal renderer | Re-upload color uniforms, re-render |
| Font changed | Font atlas builder | Rebuild font atlas, re-render all panes |
| Keybindings changed | KeybindingDispatcher | Replace keybinding map |
| Shell/args changed | (No immediate effect) | Applies to next pane spawn only |
| Working directory changed | (No immediate effect) | Applies to next pane spawn only |
| Cursor style/blink changed | Cursor renderer | Update cursor appearance |
| Scrollback size changed | (No immediate effect) | Applies to next pane spawn only |
| Window opacity changed | Window controller | Update window opacity |

6. If parsing fails entirely (syntax error), the previous valid configuration remains active. A warning is logged and a transient notification is shown.

### Manual Reload

The `reload_config` keybinding (default: `Cmd+Shift+,`) triggers the same reload pipeline immediately, bypassing the file watcher debounce.

---

## 10. Component Architecture

### Feature Directory Structure

Following conventional Swift/SwiftUI project layout:

```
Sources/aterm/
  Configuration/
    ConfigurationManager.swift      -- Central config manager, parsing, validation, caching
    ConfigDocument.swift             -- Top-level Codable model for the TOML file
    GlobalConfig.swift               -- Global config model
    ProfileConfig.swift              -- Profile config model
    ThemeConfig.swift                -- Theme color model
    WorkspaceConfig.swift            -- Workspace/space override models
    ResolvedPaneConfig.swift         -- Fully resolved config struct
    ConfigValidator.swift            -- Validation rules and error collection
    ConfigFileWatcher.swift          -- DispatchSource-based file monitor
    ConfigDefaults.swift             -- Compiled-in default values
  Keybinding/
    KeyChord.swift                   -- KeyChord value type (modifiers + key)
    KeyChordParser.swift             -- String-to-KeyChord parser
    KeybindingMap.swift              -- Chord-to-action lookup
    KeybindingDispatcher.swift       -- NSEvent monitor and dispatch
    ActionIdentifier.swift           -- Enum of all bindable actions
    ActionRouter.swift               -- Routes actions to manager methods
  Theme/
    ThemeRegistry.swift              -- Loads and indexes themes from all sources
    HexColor.swift                   -- Hex color parsing and RGBA conversion
Resources/
  themes/
    aterm-dark.toml                  -- Bundled dark theme
    aterm-light.toml                 -- Bundled light theme
  default-config.toml               -- Reference config file (not loaded; for user reference)
```

### ConfigurationManager

The `ConfigurationManager` is the central coordinator for all configuration concerns.

**Responsibilities:**
- Owns the current `ConfigDocument` and `ThemeRegistry`
- Runs the parsing pipeline on startup and on reload
- Exposes a method to resolve the effective `ResolvedPaneConfig` for a given workspace name + space name pair
- Caches resolved configs and invalidates them on reload
- Publishes change notifications via Combine (or Swift Concurrency AsyncSequence) so that SwiftUI views and renderers can react

**Integration with M1-M5 components:**
- The Metal renderer (M1) subscribes to theme and font changes
- The PTY spawner (M1) reads shell/args/working directory from resolved config at spawn time
- The pane manager (M2) reads `pane_split_ratio` from global config
- The workspace/space managers (M3-M4) do not need direct config integration -- they provide names that the config system uses for resolution
- The persistence system (M5) does not persist configuration -- config is always read from the TOML file

### ConfigFileWatcher

**Responsibilities:**
- Opens a file descriptor on the config file and themes directory
- Creates `DispatchSource` monitors for write/rename/delete events
- Implements debounce logic (200ms timer reset on each event)
- Handles atomic-write editors (detects rename/delete and re-establishes watch)
- Calls `ConfigurationManager.reload()` when debounce fires

---

## 11. Navigation and UI Integration

M6 does not introduce new screens or navigation routes. Configuration is entirely file-driven. However, two UI touchpoints exist:

### Transient Warning Notification

When a config reload produces validation warnings or parse errors, a transient overlay appears at the top of the active window. It shows for 5 seconds, then fades out. Content: a brief summary like "Config reloaded with 2 warnings" or "Config error: invalid TOML on line 42". The overlay is dismissible by clicking or pressing Escape.

### Debug Log Integration

All config parsing events (load, reload, warnings, errors) are written to the internal debug log (from M1 observability signals). A future debug overlay (M7) can display these.

---

## 12. Default Config File Generation

On first launch, if no config file exists, the app does NOT auto-create one. Instead:
- The app operates with compiled-in defaults
- A bundled `default-config.toml` reference file is included in the app bundle's Resources, containing all keys with their defaults and explanatory comments
- Users can copy this file to `~/.config/aterm/config.toml` to begin customizing

This avoids the app unexpectedly writing to the user's filesystem and ensures the config file, when it exists, is entirely user-authored.

---

## 13. Integration Points with M1-M5

| Component | M6 Integration |
|-----------|---------------|
| **PTY spawner (M1)** | Reads `shell`, `shell_args`, `working_directory` from `ResolvedPaneConfig` at pane spawn time. Currently these are likely hardcoded or read from environment; M6 replaces that with config-driven values. |
| **Metal renderer (M1)** | Subscribes to theme changes from `ConfigurationManager`. On change, uploads new color uniforms. Subscribes to font changes; on change, rebuilds font atlas. |
| **Font atlas (M1)** | Accepts `fontFamily` and `fontSize` from resolved config. Font atlas rebuild is expensive -- the renderer should diff old vs. new font settings and skip rebuild if unchanged. |
| **Cursor renderer (M1)** | Reads `cursorStyle`, `cursorBlink`, `cursorBlinkIntervalMs` from resolved config. Subscribes to changes. |
| **Pane splitting (M2)** | Reads `pane_split_ratio` from global config for default ratio. |
| **Pane resize (M2, FR-43)** | Resize percentages are runtime state, not config-driven. But the config can set the initial default via `pane_split_ratio`. |
| **Keyboard handling (M1-M4)** | All hardcoded keyboard shortcut handling from M1-M4 must be refactored to go through the `KeybindingDispatcher`. This is the largest integration cost of M6. |
| **Scrollback buffer (M1)** | Reads `scrollback_lines` from resolved config at pane creation. Does not resize existing buffers on config change (applies to new panes only). |
| **Persistence (M5)** | Persistence serializes workspace/space names. These names are used as keys in the config's workspace/space override sections. If a user renames a workspace, the config override for the old name becomes orphaned. This is acceptable -- the user updates their config file manually. |

---

## 14. Performance Considerations

| Concern | Approach |
|---------|----------|
| Config parsing latency | TOML parsing of a typical config file (under 500 lines) takes under 5ms. Not a concern. |
| Font atlas rebuild | Expensive (50-200ms). Only triggered when `font_family` or `font_size` actually changes. Diffing prevents unnecessary rebuilds. Rebuild happens on a background thread; the renderer uses the old atlas until the new one is ready. |
| Theme color upload | Trivial -- a small uniform buffer update. Single-frame latency. |
| Resolved config caching | Cache resolved configs keyed by (workspace name, space name) pair. Invalidate entire cache on reload. Cache is small (one entry per active workspace-space combination). |
| File watcher overhead | `DispatchSource` is kernel-event-driven, zero CPU cost when idle. |
| Debounce | 200ms debounce prevents rapid-fire reloads when an editor does multiple writes. |

---

## 15. Migration and Deployment

### No Database Migration

M6 introduces no database or persistence schema changes. Configuration is read-only from TOML files.

### Deployment Checklist

1. Add TOMLKit (or TOMLDecoder) as a Swift Package Manager dependency
2. Add bundled theme TOML files to the app bundle's Resources
3. Add the reference `default-config.toml` to the app bundle's Resources
4. Refactor all hardcoded keybinding handling from M1-M4 to route through `KeybindingDispatcher`
5. Update the PTY spawner to read shell/args/working directory from `ConfigurationManager`
6. Update the Metal renderer to subscribe to config changes
7. Update cursor rendering to be config-driven

### Rollback

Since configuration is purely additive and file-driven, rollback is straightforward: revert the code changes. No data migration rollback needed. User config files are harmless if the app ignores them (older version without M6 simply won't read them).

---

## 16. Implementation Phases

### Phase 1: Config Parsing Foundation

- Implement `ConfigDocument` and all sub-models with Codable conformance
- Implement `ConfigurationManager` with startup loading (no file watching yet)
- Implement `ConfigValidator` with all validation rules
- Implement `ConfigDefaults` with compiled-in defaults
- Implement `ResolvedPaneConfig` and the profile inheritance resolution algorithm
- Add TOMLKit as an SPM dependency
- Write unit tests for parsing, validation, and resolution

**Deliverable:** Config file is read at startup and resolved configs are available. No live reload yet.

### Phase 2: Theme System

- Implement `ThemeConfig`, `HexColor`, and `ThemeRegistry`
- Create bundled `aterm-dark.toml` and `aterm-light.toml` theme files
- Integrate theme loading from both inline config and external theme files
- Connect `ThemeRegistry` to the Metal renderer's color uniforms
- Wire up theme from resolved config to each pane's renderer

**Deliverable:** Themes are loadable and applied to terminal rendering. Users can define custom themes.

### Phase 3: Keybinding System

- Implement `KeyChord`, `KeyChordParser`, `ActionIdentifier`, `KeybindingMap`
- Implement `KeybindingDispatcher` with `NSEvent` local monitor
- Implement `ActionRouter` connecting actions to M1-M5 managers
- Refactor all existing hardcoded keyboard shortcuts to go through the dispatcher
- Wire up keybinding loading from config

**Deliverable:** All keyboard shortcuts are configurable. Existing shortcuts still work with defaults.

### Phase 4: Live Reload

- Implement `ConfigFileWatcher` with `DispatchSource`
- Implement debounce logic and atomic-write-safe re-watching
- Implement the reload pipeline (re-parse, diff, notify subsystems)
- Implement the manual reload keybinding
- Implement the transient warning notification overlay
- Connect font changes to font atlas rebuild
- Connect cursor config changes to cursor renderer

**Deliverable:** Full live reload. Edit the TOML file, save, and see changes reflected immediately.

---

## 17. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Refactoring M1-M4 keyboard handling to go through the dispatcher introduces regressions | High -- breaks core navigation | Medium | Implement the dispatcher with the existing default bindings first, run all M1-M4 tests, then add configurability. Phase 3 should have extensive integration tests. |
| Font atlas rebuild on config change causes visible flicker or stall | Medium -- bad UX during config editing | Low | Rebuild atlas on background thread, swap atomically. Keep old atlas alive until new one is ready. |
| Editors that use atomic writes (write to temp, rename) break the file watcher | Medium -- live reload stops working silently | Medium | Watch for `.rename` and `.delete` events. On either, close the old source, wait briefly for the new file to appear, re-open and re-watch. Test with vim, VS Code, and nano specifically. |
| TOMLKit dependency adds significant compile time or binary size | Low | Low | TOMLKit wraps toml++ (C++). Compile cost is a one-time SPM build. Binary size impact is minimal. If unacceptable, switch to TOMLDecoder (pure Swift, smaller). |
| User config file has syntax errors and app refuses to start | High -- blocks app usage | Low | On startup, if parsing fails, log the error and proceed with compiled-in defaults. Never block app launch on config errors. |
| Workspace/space rename in the UI orphans config overrides | Low -- config stops applying to renamed entity | Medium | Acceptable in v1. Document that config keys must match workspace/space names. A future enhancement could add identifier-based matching. |

---

## 18. Open Technical Questions

| Question | Context | Impact if Unresolved |
|----------|---------|---------------------|
| Should TOMLKit or TOMLDecoder be the parsing library? | TOMLKit supports encoding+decoding, TOMLDecoder is faster and supports TOML 1.1. Both work. | Low -- either works. Engineering team should prototype both and decide based on API feel and compile-time cost. |
| Should the app generate a default config file on first launch? | Current spec says no (user copies reference file manually). Some users expect config scaffolding. | Low -- can be added later. The compiled-in defaults ensure the app is usable without a config file. |
| How should config errors be surfaced beyond the transient notification? | A persistent "config has errors" indicator vs. only transient notification. | Low -- transient notification plus debug log is sufficient for v1. A dedicated config error view can be added in M7. |
| Should the config support `include` directives for splitting config across files? | Power users may want modular configs. TOML has no native include mechanism. | Low -- defer to post-v1. Users can put themes in separate files already. |
| What happens to in-flight terminal output during a font atlas rebuild? | Atlas rebuild takes 50-200ms. Terminal output continues arriving. | Medium -- if the old atlas is kept alive during rebuild, rendering continues uninterrupted. Must verify this works with the Metal renderer's resource management. |
| Should profiles be assignable per-tab or per-pane, not just per-workspace/space? | PRD says workspace and space level (FR-29). Per-tab/per-pane would add granularity but complexity. | Low -- follow the PRD. Per-tab/per-pane can be added later if needed. |
