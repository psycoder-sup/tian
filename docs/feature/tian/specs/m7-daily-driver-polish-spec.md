# SPEC: M7 -- Daily Driver Polish

**Based on:** docs/feature/tian/tian-prd.md v1.4
**Author:** CTO Agent
**Date:** 2026-03-24
**Version:** 1.0
**Status:** Draft

---

## 1. Overview

Milestone 7 is the final polish pass that resolves remaining rough edges blocking daily use of tian. It spans six capabilities: find-in-scrollback search (FR-35), native macOS full-screen mode (FR-37), shell exit/crash behavior (FR-25), edge case hardening (shell crashes, permission errors, unusual terminal sequences), VoiceOver accessibility for workspace navigation UI (FR-41), WCAG contrast compliance (FR-42), and performance profiling and optimization. All work in M7 depends on the M1-M6 infrastructure being complete and stable.

This spec assumes the following M1-M6 components exist and are functional: PTY management and shell spawning (M1), pane split tree (M2), tab bar and space bar UI (M3), workspace switcher and multi-window support (M4), session persistence and restore (M5), configuration system with TOML profiles, themes, and keybindings (M6).

---

## 2. Find-in-Scrollback Search (FR-35)

### 2.1 Architecture

The search system consists of three layers:

1. **Search Engine** -- operates on the scrollback buffer text owned by each pane's terminal state (backed by libghostty-vt). Responsible for matching, result indexing, and navigation.
2. **Search Overlay View** -- a SwiftUI overlay rendered on top of the active pane's Metal terminal view. Contains a text field and match count indicator.
3. **Search Coordinator** -- mediates between the overlay UI and the search engine; manages state transitions (open, search, navigate, close).

### 2.2 Search Engine

**Location:** A new `SearchEngine` class within the terminal/pane services layer.

**Responsibilities:**
- Accept a plain-text query string and search direction (forward/backward).
- Extract the full scrollback text from the pane's terminal state via libghostty-vt's C ABI. The extraction method depends on what libghostty-vt exposes -- if it provides a line-by-line text accessor, iterate lines; if it provides a bulk text dump, use that. The engine must handle the visible screen region as part of the searchable content (scrollback + visible = full buffer).
- Perform case-insensitive substring matching by default. Support a toggle for case-sensitive matching.
- Produce an ordered list of match results, each identified by (line index, column start, column end).
- Track the "current match index" for next/previous navigation.
- When the user modifies the query, re-run the search incrementally if possible, or fully if not.

**Performance considerations:**
- The scrollback buffer can be up to the configured limit (default 10,000 lines). For a typical 200-column terminal, this is ~2MB of text. Substring search over this size is fast enough to run synchronously on each keystroke on modern hardware.
- If profiling in Phase 4 reveals search latency above 16ms (one frame), introduce a debounce of 50ms on keystroke input before triggering search.

### 2.3 Search Overlay View

**Trigger:** User presses the configured keybinding (default: Cmd+F). The keybinding must be registered in the M6 keybinding system as action `find_in_scrollback`.

**Layout:** The overlay appears as a floating bar at the top-right of the active pane (not the window -- the pane). It overlays the terminal content and does not resize the terminal grid. It contains:

| Element | Description |
|---------|-------------|
| Search text field | Single-line, auto-focused on open. Placeholder text: "Find..." |
| Match count label | Shows "N of M" where N is the current match index (1-based) and M is the total match count. Shows "No results" when M is 0. |
| Previous button | Navigate to previous match (also: Shift+Enter or Shift+Cmd+G) |
| Next button | Navigate to next match (also: Enter or Cmd+G) |
| Case sensitivity toggle | Button or checkbox. Default: case-insensitive. |
| Close button | Dismiss overlay (also: Escape) |

**Behavior:**
- Opening the search overlay does not steal the terminal's keyboard input except for the search field itself. The terminal remains visible but input goes to the search field.
- If text is currently selected in the pane when Cmd+F is pressed, pre-populate the search field with the selected text.
- Closing the overlay (Escape or close button) returns keyboard focus to the terminal pane.
- The overlay must not interfere with the Metal rendering pipeline -- it is a SwiftUI view layered above the Metal view using a ZStack or overlay modifier.

### 2.4 Match Highlighting

When search results exist, the renderer must highlight all matches in the visible portion of the scrollback:

- **All matches:** Rendered with a distinct background color. Use the theme's `search_match_background` color (new theme key, default: semi-transparent yellow, e.g., RGBA 255, 255, 0, 0.3).
- **Current match:** Rendered with a brighter/more opaque variant of the match color. Use the theme's `search_match_active_background` (default: RGBA 255, 200, 0, 0.6).

The highlight rendering must be integrated into the Metal cell rendering pipeline. The approach: before rendering the cell grid for a visible frame, the renderer checks which cells fall within a match range and applies the highlight background color as an additional attribute. This is conceptually similar to how selection highlighting works (which should exist from M1 FR-32).

### 2.5 Scroll-to-Match

When the user navigates to a match (next/previous), the terminal viewport must scroll to make the matched line visible. Center the matched line vertically in the viewport if it is currently off-screen. If the match is already visible, do not scroll.

### 2.6 New Configuration Keys

These keys are added to the theme definition in the TOML configuration (extends M6 theme schema):

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `search_match_background` | Color (hex string) | `"#FFFF004D"` | Background for non-active matches |
| `search_match_active_background` | Color (hex string) | `"#FFC80099"` | Background for the active/current match |

### 2.7 New Keybinding Actions

Registered in the M6 keybinding system:

| Action name | Default binding | Description |
|-------------|----------------|-------------|
| `find_in_scrollback` | Cmd+F | Open search overlay for active pane |
| `find_next` | Cmd+G | Navigate to next match (when overlay is open) |
| `find_previous` | Shift+Cmd+G | Navigate to previous match (when overlay is open) |

---

## 3. Native macOS Full-Screen Support (FR-37)

### 3.1 Approach

SwiftUI windows on macOS support native full-screen out of the box when the window's style allows it. The implementation requires:

1. Ensure the main window scene does not disable the full-screen button. In SwiftUI, this means the `WindowGroup` or `Window` scene must not apply `.windowResizability` constraints that prevent full-screen, and must not set `.windowStyle(.hiddenTitleBar)` in a way that removes the traffic light buttons.
2. The green "zoom" button in the title bar must trigger native full-screen (the default macOS behavior). No custom full-screen implementation.
3. Add a menu item under the "View" menu: "Enter Full Screen" / "Exit Full Screen" with the standard shortcut (Ctrl+Cmd+F, which macOS provides automatically for full-screen-capable windows).

### 3.2 Layout Adaptation

When entering full-screen, the window occupies the entire screen (or a macOS Space). The following must adapt correctly:

| Component | Full-screen behavior |
|-----------|---------------------|
| Title bar / workspace indicator | If using a toolbar-style title bar, it auto-hides with the menu bar in full-screen (standard macOS behavior). The workspace indicator must remain accessible when the title bar is revealed (mouse to top edge). |
| Space bar | Remains visible at all times. Does not auto-hide. |
| Tab bar | Remains visible at all times. Does not auto-hide. |
| Pane content area | Expands to fill remaining space. Terminal grids must receive SIGWINCH and update `$COLUMNS` / `$LINES`. |
| Search overlay | Continues to render correctly relative to the active pane. |

### 3.3 Multi-Window Full-Screen

Since each window displays one workspace (FR-36), multiple windows can independently enter full-screen. Each occupies its own macOS Space. No special handling is needed -- this is default macOS behavior for multiple windows.

### 3.4 Keyboard Shortcut

The standard macOS full-screen toggle (Ctrl+Cmd+F) is provided by the system when the window supports full-screen. No custom keybinding registration is needed in the M6 system. However, if the user has overridden Ctrl+Cmd+F in the keybinding configuration, the custom binding takes precedence.

### 3.5 Persistence

Full-screen state per window should be persisted in the session state JSON (M5). When restoring, if a window was in full-screen, restore it to full-screen. Add a boolean field `is_fullscreen` to the workspace's window state in the persistence schema.

**New field in persistence schema (extends M5 workspace window state):**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `is_fullscreen` | Boolean | `false` | Whether the window was in full-screen mode when the session was saved |

---

## 4. Shell Exit/Crash Behavior (FR-25)

### 4.1 Exit Monitoring

Each pane's PTY manager must monitor the child shell process for termination. When the child process exits (detected via `waitpid` or a dispatch source on the process), the PTY manager captures:

- The exit status (from `WEXITSTATUS` macro if `WIFEXITED` is true)
- Whether the process was signaled (from `WIFSIGNALED` / `WTERMSIG`)

### 4.2 Behavior by Exit Condition

| Condition | Behavior |
|-----------|----------|
| Exit code 0 (clean exit) | Pane closes automatically. Cascading close per FR-05: last pane closes tab, last tab closes space, last space closes workspace, last workspace quits app (M5 quit flow serializes state first). |
| Exit code non-zero | Pane remains open. Terminal output is preserved. An exit status banner is displayed below the last line of output. |
| Process killed by signal | Pane remains open. Terminal output is preserved. A signal banner is displayed. |
| PTY read error (EIO, etc.) | Treated as a crash. Pane remains open with an error banner. |

### 4.3 Exit Status Banner

When a pane remains open after a non-zero exit or signal, display a banner rendered within the terminal viewport (not as a SwiftUI overlay). The banner is appended to the terminal content as styled text.

**Banner content by condition:**

| Condition | Banner text |
|-----------|-------------|
| Non-zero exit | `[Process exited with code {N}]` |
| Killed by signal | `[Process terminated by signal {N} ({signal_name})]` where `signal_name` is the human-readable name (e.g., SIGKILL, SIGSEGV) |
| PTY error | `[Connection to process lost: {error_description}]` |

**Banner styling:**
- Text color: theme's `exit_banner_foreground` (new theme key, default: a muted gray, e.g., `#888888`)
- Background: theme's `exit_banner_background` (new theme key, default: none / transparent)
- Centered horizontally within the terminal width
- One blank line separating the last terminal output from the banner

### 4.4 Pane State After Exit

When a pane is in the "exited" state:
- The pane is still part of the split tree and occupies its space.
- The user can scroll through the scrollback buffer.
- The user can search (Cmd+F) through the scrollback.
- The user can select and copy text.
- Keyboard input is not forwarded to a PTY (there is no process).
- The user closes the pane via the normal close-pane keybinding or action.
- An optional "Restart Shell" action (keybinding: configurable, no default) spawns a fresh shell in the same working directory, replacing the exited state.

### 4.5 New Keybinding Actions

| Action name | Default binding | Description |
|-------------|----------------|-------------|
| `restart_shell` | None (user must configure) | Restart a fresh shell in an exited pane |

### 4.6 New Configuration / Theme Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `exit_banner_foreground` | Color (hex string) | `"#888888"` | Text color for exit/crash banners |
| `exit_banner_background` | Color (hex string) | `"#00000000"` | Background color for exit/crash banners |

### 4.7 Persistence Interaction

When saving session state (M5), panes in the "exited" state are saved with a flag indicating they are exited, their last working directory, and their exit code. On restore, exited panes are restored in the exited state (showing the exit banner) rather than spawning a new shell. This preserves the user's awareness that something went wrong.

**New fields in persistence schema (extends M5 pane state):**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `is_exited` | Boolean | `false` | Whether the pane's process has exited |
| `exit_code` | Integer or null | `null` | The exit code if exited, null if still running or killed by signal |
| `exit_signal` | Integer or null | `null` | The signal number if killed by signal, null otherwise |

---

## 5. Edge Case Handling

### 5.1 Shell Spawn Failures

When a pane attempts to spawn a shell and fails (e.g., shell binary not found, permission denied, `posix_spawn` / `forkpty` failure):

| Failure | Detection | User-facing behavior |
|---------|-----------|---------------------|
| Shell binary not found | `posix_spawn` returns `ENOENT` or shell path doesn't exist | Pane displays: `[Failed to start shell: {path} not found]` |
| Permission denied | `posix_spawn` returns `EACCES` | Pane displays: `[Failed to start shell: permission denied for {path}]` |
| PTY allocation failure | `forkpty` / `openpty` returns error | Pane displays: `[Failed to allocate terminal: {strerror}]` |
| Resource exhaustion | `EMFILE`, `ENOMEM`, etc. | Pane displays: `[Failed to start shell: {strerror}]` |

In all cases, the pane enters the "exited" state (same as Section 4.4) and allows the user to close or retry via `restart_shell`.

### 5.2 Shell Crash During Operation

If the shell process dies unexpectedly while the pane is active (e.g., SIGSEGV in the shell itself):

- The PTY read loop will encounter `EIO` on the file descriptor.
- The `waitpid` dispatch source will fire with the signal information.
- The pane transitions to the "exited" state with the signal banner from Section 4.3.
- Terminal output up to the crash point is preserved in scrollback.

### 5.3 Unusual Terminal Sequences

libghostty-vt handles VT parsing. The edge cases to handle at the tian integration layer:

| Sequence type | Handling |
|---------------|----------|
| Unrecognized escape sequences | libghostty-vt ignores them (no rendering artifact). tian logs a debug-level message with the raw bytes for troubleshooting. |
| Extremely long lines (>10,000 columns) | libghostty-vt should handle wrapping. tian must not allocate unbounded memory for a single line in the renderer -- the Metal renderer already works on a visible-cell basis and should not be affected. |
| Rapid output flooding (e.g., `cat /dev/urandom`) | The PTY read loop must batch reads and coalesce rendering. The Metal renderer should already frame-limit at display refresh rate. If not, ensure the render loop is driven by `CVDisplayLink` or `CADisplayLink` and processes accumulated state per frame, not per read. |
| OSC sequences (window title, clipboard, etc.) | Window title changes (OSC 2) should update the pane's title if a pane title display is implemented. Clipboard writes (OSC 52) should be supported -- write to the system pasteboard. Unknown OSC sequences are ignored. |
| Alternate screen buffer (e.g., vim, less) | Handled by libghostty-vt. When the alternate screen is active, scrollback search should search the main buffer, not the alternate screen. When the alternate screen is deactivated, the main buffer content returns. |

### 5.4 Permission Errors During Operation

| Scenario | Detection | Handling |
|----------|-----------|---------|
| Working directory deleted while pane is open | Shell handles this (typically prints an error). No tian action needed. |
| PTY write fails (`EPIPE`, `EIO`) | Write to PTY fd returns error | Stop forwarding keyboard input. Transition to exited state when `waitpid` fires. |
| Disk full during session save (M5) | Serialization write fails | Log the error. Proceed with quit (do not block). On next launch, start with default workspace (existing M5 behavior per FR-23). |

---

## 6. VoiceOver Accessibility (FR-41)

### 6.1 Approach

SwiftUI provides built-in accessibility modifiers that map to the macOS Accessibility API consumed by VoiceOver. Each interactive UI element in the workspace navigation chrome must have appropriate accessibility properties.

### 6.2 Space Bar Accessibility

The space bar is a horizontal row of space items (buttons/tabs).

| Element | Accessibility role | Accessibility label | Accessibility hint | Additional traits |
|---------|-------------------|--------------------|--------------------|-------------------|
| Space bar container | `tabList` | "Spaces in {workspace_name}" | None | None |
| Individual space item | `tab` | "{space_name}" | "Double-tap to switch to space" | `.isSelected` if this is the active space |
| Space close button (if visible) | `button` | "Close space {space_name}" | "Double-tap to close this space" | None |

### 6.3 Tab Bar Accessibility

| Element | Accessibility role | Accessibility label | Accessibility hint | Additional traits |
|---------|-------------------|--------------------|--------------------|-------------------|
| Tab bar container | `tabList` | "Tabs in space {space_name}" | None | None |
| Individual tab item | `tab` | "Tab {N}: {tab_title_or_number}" | "Double-tap to switch to tab" | `.isSelected` if active |
| Tab close button | `button` | "Close tab {N}" | "Double-tap to close this tab" | None |
| New tab button | `button` | "New tab" | "Double-tap to create a new tab" | None |

### 6.4 Workspace Indicator

| Element | Accessibility role | Accessibility label | Accessibility hint |
|---------|-------------------|--------------------|--------------------|
| Workspace indicator | `button` | "Current workspace: {workspace_name}" | "Double-tap to open workspace switcher" |

### 6.5 Workspace Switcher Overlay

| Element | Accessibility role | Accessibility label | Accessibility hint |
|---------|-------------------|--------------------|--------------------|
| Switcher container | `dialog` | "Workspace switcher" | None |
| Search field | `searchField` | "Search workspaces" | "Type to filter workspaces" |
| Workspace list item | `button` | "{workspace_name}" | "Double-tap to switch to this workspace" |

### 6.6 Pane Focus

| Element | Accessibility role | Accessibility label | Accessibility hint |
|---------|-------------------|--------------------|--------------------|
| Pane container | `group` | "Terminal pane {N} of {total}" | None |
| Active pane | Same as above | Same, with additional announcement | VoiceOver should announce when focus moves to a different pane via the directional pane navigation shortcuts |

### 6.7 Search Overlay Accessibility

| Element | Accessibility role | Accessibility label | Accessibility hint |
|---------|-------------------|--------------------|--------------------|
| Search overlay container | `group` | "Find in scrollback" | None |
| Search field | `searchField` | "Search text" | "Type to search terminal output" |
| Match count | `staticText` | "{N} of {M} matches" or "No matches" | None |
| Next button | `button` | "Next match" | None |
| Previous button | `button` | "Previous match" | None |
| Case toggle | `toggleButton` | "Case sensitive" | "Double-tap to toggle case sensitivity" |
| Close button | `button` | "Close search" | None |

### 6.8 VoiceOver Announcements

Use `AccessibilityNotification.Announcement` (or `NSAccessibility.post(notification:)`) for dynamic state changes:

| Event | Announcement text |
|-------|-------------------|
| Workspace switched | "Switched to workspace {name}" |
| Space switched | "Switched to space {name}" |
| Tab switched | "Switched to tab {N}" |
| Pane focus changed | "Pane {N} of {total}" |
| Search match navigation | "Match {N} of {M}" |
| Process exited | "Process exited with code {N}" or "Process terminated by signal {name}" |

---

## 7. WCAG Contrast Compliance (FR-42)

### 7.1 Scope

All UI chrome elements must meet WCAG 2.1 AA minimum contrast ratios:
- **4.5:1** for normal text (below 18pt regular / 14pt bold)
- **3:1** for large text (18pt+ regular or 14pt+ bold) and UI components (icons, borders, focus indicators)

This applies to: space bar, tab bar, workspace indicator, exit status banners, search overlay, and any status text.

### 7.2 Audit Strategy

For each bundled theme (defined in M6), validate:

| UI Element | Foreground | Background | Required Ratio | Check |
|------------|-----------|------------|----------------|-------|
| Space bar item (inactive) | Space text color | Space bar background | 4.5:1 | Compute from theme values |
| Space bar item (active) | Active space text color | Active space background | 4.5:1 | Compute from theme values |
| Tab bar item (inactive) | Tab text color | Tab bar background | 4.5:1 | Compute from theme values |
| Tab bar item (active) | Active tab text color | Active tab background | 4.5:1 | Compute from theme values |
| Workspace indicator text | Indicator text color | Title bar background | 4.5:1 | Compute from theme values |
| Exit banner text | `exit_banner_foreground` | Terminal background | 4.5:1 | Compute from theme values |
| Search overlay text | System text color | Overlay background | 4.5:1 | Compute from theme values |
| Search match count | System secondary text | Overlay background | 4.5:1 | Compute from theme values |

### 7.3 Implementation

1. **Build a contrast ratio utility function** that takes two colors (foreground, background) and returns the WCAG relative luminance contrast ratio. Formula: `(L1 + 0.05) / (L2 + 0.05)` where L1 is the lighter relative luminance and L2 is the darker.
2. **Add a debug assertion** (active in debug builds only) that runs at theme application time and logs a warning if any UI chrome color pair fails to meet the required ratio. This is a developer guardrail, not a runtime check.
3. **Audit and fix all bundled themes** as part of M7 development. Document the measured ratios for each theme.
4. **User-defined themes** are not validated at runtime (user's responsibility), but the contrast utility is available for a future "theme validator" tool.

---

## 8. Performance Profiling and Optimization (FR instrumentation signals)

### 8.1 Profiling Infrastructure

The PRD specifies five internal observability signals. M7 must implement collection, storage, and display for each.

| Signal | Collection method | Storage | Display |
|--------|------------------|---------|---------|
| Frame render time (ms) | Instrument the Metal render pass. Record the time from command buffer commit to completion (via `addCompletedHandler`). | Rolling buffer of last 300 frames (5 seconds at 60fps) | Debug overlay: current, average, P95, P99 |
| Shell spawn latency (ms) | Record wall-clock time from the "create pane" action to the first byte read from the PTY fd. | Per-pane, logged once at spawn | Debug overlay: last spawn latency |
| Restore time (ms) | Record wall-clock time from app launch start to all panes reporting "ready" (first shell prompt received or timeout). | Logged once per launch | Debug overlay: last restore time |
| Memory per pane | Query the scrollback buffer size (line count * estimated bytes per line) from libghostty-vt. Optionally, use `task_info` to get the process's total memory footprint. | Sampled every 5 seconds | Debug overlay: per-pane memory, total |
| Restore correctness (%) | Compare saved pane count, layout structure, and working directories against restored state. Log any mismatches with details. | Logged once per launch | Debug overlay: last restore correctness % |

### 8.2 Debug Overlay

A toggleable SwiftUI overlay (similar to a game engine's FPS counter) that displays the performance metrics.

**Trigger:** A keybinding action `toggle_debug_overlay` with no default binding (user must configure). Also accessible via a menu item: Debug > Performance Overlay.

**Layout:** Semi-transparent panel anchored to the bottom-left corner of the window. Does not interfere with terminal input. Displays:

| Line | Content |
|------|---------|
| 1 | `FPS: {current} | Frame: {avg}ms / P95: {p95}ms / P99: {p99}ms` |
| 2 | `Spawn: {last_spawn}ms | Restore: {last_restore}ms ({correctness}%)` |
| 3 | `Panes: {count} | Mem: {total_mb}MB ({per_pane_avg}MB/pane)` |

### 8.3 Performance Targets

From the PRD success metrics:

| Metric | Target | How to validate |
|--------|--------|-----------------|
| Frame render time | No perceptible drops at 60fps (< 16.6ms per frame) | P99 frame time < 16.6ms during normal use (typing, scrolling) |
| Shell spawn latency | < 200ms from action to usable pane | Measured by spawn latency signal |
| App restore time | < 1 second to interactive | Measured by restore time signal |
| Scroll smoothness | No visible stutter | Scroll through 10,000-line buffer while monitoring frame time P99 |

### 8.4 Optimization Strategies

If profiling reveals performance issues, the following optimizations should be investigated in priority order:

1. **Rendering hot path:** Ensure the Metal render pass only re-renders dirty regions (cells that changed since the last frame). If the current renderer re-renders the full grid every frame, add dirty-rect tracking.
2. **Scrollback memory:** If memory per pane is excessive, consider compressing scrollback lines that are far from the viewport (e.g., run-length encoding of attributes, or storing only text for lines beyond a threshold).
3. **PTY read coalescing:** Ensure the PTY read loop batches multiple reads into a single terminal state update and render pass. Do not re-render on every individual `read()` return.
4. **Font atlas efficiency:** Ensure glyphs are cached in the atlas and not re-rasterized. Monitor atlas texture size.
5. **Shell spawn:** If spawn latency exceeds 200ms, investigate: is the bottleneck `forkpty`, shell initialization (`.zshrc` etc.), or PTY setup? The first two are outside tian's control; the third can be optimized.

### 8.5 New Keybinding Actions

| Action name | Default binding | Description |
|-------------|----------------|-------------|
| `toggle_debug_overlay` | None (user must configure) | Toggle the performance debug overlay |

---

## 9. Component Architecture

### 9.1 Feature Directory Structure

The following new files and directories are added in M7, following the project's module organization. Exact paths will depend on the directory conventions established in M1-M6, but the logical grouping is:

```
Sources/tian/
  Features/
    Search/
      SearchEngine.swift           -- Scrollback text search logic
      SearchCoordinator.swift      -- State machine mediating UI and engine
      SearchOverlayView.swift      -- SwiftUI overlay with text field, controls
      SearchHighlightPass.swift    -- Metal render integration for match highlighting
    Performance/
      PerformanceCollector.swift   -- Collects all profiling signals
      FrameTimeTracker.swift       -- Metal frame timing via completion handlers
      SpawnLatencyTracker.swift    -- Pane spawn timing
      RestoreProfiler.swift        -- Launch restore timing and correctness
      DebugOverlayView.swift       -- SwiftUI performance overlay
    Accessibility/
      AccessibilityLabels.swift    -- Centralized label/hint string constants
  Extensions/
    Color+ContrastRatio.swift      -- WCAG contrast ratio utility
  Terminal/
    PaneExitState.swift            -- Exit state model (code, signal, banner text)
```

### 9.2 Modifications to Existing Components

| Existing component | Modification |
|-------------------|-------------|
| Pane view (M1/M2) | Add ZStack layer for search overlay. Add exit state banner rendering. Add accessibility labels. |
| Pane model (M1/M2) | Add `exitState` property (enum: running, exited with code, exited with signal, spawn failed). Add search state. |
| PTY manager (M1) | Add process exit monitoring with signal detection. Add spawn latency measurement. Add error classification for spawn failures. |
| Metal renderer (M1) | Add search highlight rendering pass. Add frame time measurement via completion handlers. |
| Space bar view (M3) | Add accessibility roles, labels, hints per Section 6.2. |
| Tab bar view (M3) | Add accessibility roles, labels, hints per Section 6.3. |
| Workspace switcher (M4) | Add accessibility roles, labels, hints per Section 6.5. |
| Workspace indicator (M4) | Add accessibility role, label, hint per Section 6.4. |
| Window scene (M4) | Ensure full-screen capability is not restricted. |
| Persistence schema (M5) | Add `is_fullscreen` to window state. Add `is_exited`, `exit_code`, `exit_signal` to pane state. Increment schema version. |
| Theme definition (M6) | Add `search_match_background`, `search_match_active_background`, `exit_banner_foreground`, `exit_banner_background` keys. |
| Keybinding registry (M6) | Register new actions: `find_in_scrollback`, `find_next`, `find_previous`, `restart_shell`, `toggle_debug_overlay`. |

---

## 10. Type Definitions

### 10.1 Search Types

| Type | Field | Type | Description |
|------|-------|------|-------------|
| `SearchMatch` | `lineIndex` | Int | Zero-based line index in the full buffer (scrollback + visible) |
| | `columnStart` | Int | Zero-based column of match start |
| | `columnEnd` | Int | Zero-based column of match end (exclusive) |
| `SearchState` | `query` | String | Current search query |
| | `matches` | Array of SearchMatch | All matches found |
| | `currentMatchIndex` | Int? | Index into `matches` for the active match, nil if no matches |
| | `isCaseSensitive` | Bool | Whether search is case-sensitive |
| | `isOverlayVisible` | Bool | Whether the search overlay is showing |

### 10.2 Pane Exit Types

| Type | Field | Type | Description |
|------|-------|------|-------------|
| `PaneExitState` (enum) | `.running` | -- | Process is alive |
| | `.exited(code: Int)` | -- | Process exited with given code |
| | `.signaled(signal: Int32, name: String)` | -- | Process killed by signal |
| | `.spawnFailed(error: String)` | -- | Shell failed to start |
| | `.lostConnection(error: String)` | -- | PTY connection lost |

### 10.3 Performance Types

| Type | Field | Type | Description |
|------|-------|------|-------------|
| `FrameTimeSample` | `timestamp` | TimeInterval | When the frame completed |
| | `durationMs` | Double | Frame render duration in milliseconds |
| `PerformanceSnapshot` | `frameTimeAvg` | Double | Average frame time over rolling window |
| | `frameTimeP95` | Double | 95th percentile frame time |
| | `frameTimeP99` | Double | 99th percentile frame time |
| | `currentFps` | Int | Frames per second (last 1 second) |
| | `lastSpawnLatencyMs` | Double? | Most recent pane spawn latency |
| | `lastRestoreTimeMs` | Double? | Most recent app restore time |
| | `restoreCorrectness` | Double? | Most recent restore correctness ratio (0.0 to 1.0) |
| | `paneCount` | Int | Active pane count |
| | `totalMemoryMB` | Double | Estimated total scrollback memory |

### 10.4 Persistence Schema Additions

Added to the existing M5 JSON schema (new version):

**Workspace window state (extended):**

| Field | Type | Description |
|-------|------|-------------|
| `is_fullscreen` | Bool | Whether the window was in full-screen |

**Pane state (extended):**

| Field | Type | Description |
|-------|------|-------------|
| `is_exited` | Bool | Whether the pane is in an exited state |
| `exit_code` | Int? | Exit code if exited normally with non-zero |
| `exit_signal` | Int? | Signal number if killed by signal |

---

## 11. Navigation

### 11.1 New Routes

M7 does not introduce new screens in the navigation sense. All new UI (search overlay, debug overlay, exit banner) is rendered as overlays or inline content within existing pane views.

### 11.2 New Interactions

| Interaction | Source | Target | Trigger |
|-------------|--------|--------|---------|
| Open search | Active pane | Search overlay (within pane) | Cmd+F |
| Close search | Search overlay | Active pane (focus returns) | Escape |
| Open debug overlay | Any state | Debug overlay (window-level) | User-configured binding |
| Enter full-screen | Window | macOS full-screen space | Green button / Ctrl+Cmd+F / menu |
| Restart shell | Exited pane | Same pane (new shell) | User-configured `restart_shell` binding |

---

## 12. Permissions and Security

### 12.1 No New Permissions Required

M7 features do not require any new entitlements or system permissions. Full-screen is a standard window capability. VoiceOver integration uses the standard Accessibility API that all SwiftUI apps participate in by default (no Accessibility entitlement needed from the app side -- VoiceOver works with standard controls). The app does not request the Accessibility permission for itself (per PRD Section 7: "Accessibility: not required in v1").

### 12.2 OSC 52 Clipboard Access

The edge case handling section mentions OSC 52 (clipboard write from terminal applications). If implemented, this allows a program running in the terminal to write to the system clipboard. This is standard behavior in most terminal emulators but should be noted as a potential security consideration. Mitigation: gate OSC 52 support behind a configuration option (default: enabled, matching industry standard).

**New configuration key:**

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `allow_osc52_clipboard` | Bool | `true` | Whether programs can write to clipboard via OSC 52 |

---

## 13. Performance Considerations

| Concern | Mitigation |
|---------|------------|
| Search over large scrollback (10,000+ lines) | Substring search over 2MB of text is typically < 5ms. Debounce at 50ms if profiling shows UI jank. |
| Search highlight rendering | Only highlight matches visible in the viewport. Do not process off-screen matches for rendering. |
| Frame time measurement overhead | `addCompletedHandler` on Metal command buffers has negligible overhead. |
| Memory sampling | 5-second interval is infrequent enough to have no impact. |
| VoiceOver announcements | Only fire announcements on explicit user actions (workspace/space/tab/pane switch). Do not announce on programmatic focus changes during restore. |
| Full-screen transition | macOS handles the animation. Ensure the terminal grid recomputes dimensions only once (on the final size, not intermediate animation frames). Listen for the window's `didEnterFullScreen` / `didExitFullScreen` notifications rather than reacting to every resize during the animation. |
| Exit state panes | Exited panes consume no PTY resources but still hold scrollback memory. This is acceptable -- the user explicitly keeps them open. |

---

## 14. Migration and Deployment

### 14.1 Persistence Schema Migration

M7 adds three fields to the pane state (`is_exited`, `exit_code`, `exit_signal`) and one field to the window state (`is_fullscreen`). The M5 persistence system uses a `"version"` field.

**Migration approach:**
- Increment the schema version (e.g., from the M5 version to M7's version).
- The deserializer must handle the absence of the new fields gracefully (treat missing `is_exited` as `false`, missing `is_fullscreen` as `false`, missing `exit_code`/`exit_signal` as `null`). This makes the migration backward-compatible -- no explicit migration code needed, just default-value handling.
- The serializer always writes the new fields.

### 14.2 Theme Schema Migration

New theme keys (`search_match_background`, `search_match_active_background`, `exit_banner_foreground`, `exit_banner_background`) must have hardcoded defaults so that existing user themes that lack these keys still work. The theme parser must provide fallback values for any missing keys.

### 14.3 Feature Flags

Since this is a personal tool with a single developer/user, formal feature flags are not necessary. However, the debug overlay should be gated behind a keybinding that has no default (user must opt in), which serves as a practical gate.

### 14.4 Rollback Plan

All M7 changes are additive:
- New persistence fields default to safe values, so rolling back to a pre-M7 build that ignores them is safe (unknown JSON keys are ignored by a well-written deserializer).
- New theme keys have defaults, so they degrade gracefully.
- The search overlay, debug overlay, and accessibility labels are new code paths that do not modify existing behavior when inactive.

---

## 15. Implementation Phases

### Phase 1: Shell Exit Behavior and Edge Case Hardening
**Goal:** Panes correctly handle process exit, crashes, and spawn failures.

**Scope:**
- Implement `PaneExitState` model and integrate into pane lifecycle
- Add process exit monitoring (`waitpid` dispatch source) to PTY manager
- Implement exit/signal/error banner rendering in the terminal view
- Handle shell spawn failures with user-facing error messages
- Add PTY error handling (EIO, EPIPE)
- Add `restart_shell` keybinding action
- Add `is_exited`, `exit_code`, `exit_signal` to persistence schema with defaults
- Add `exit_banner_foreground`, `exit_banner_background` to theme schema

**Testable independently:** Launch shells that exit with various codes, kill shells with signals, trigger spawn failures (invalid shell path), verify banners display correctly and panes remain interactive (scrollback, copy).

### Phase 2: Find-in-Scrollback Search
**Goal:** Users can search terminal output within any pane.

**Scope:**
- Implement `SearchEngine` with substring matching
- Implement `SearchOverlayView` with text field, match count, navigation controls
- Implement `SearchCoordinator` state machine
- Integrate search highlight rendering into the Metal pipeline
- Implement scroll-to-match behavior
- Register `find_in_scrollback`, `find_next`, `find_previous` keybinding actions
- Add `search_match_background`, `search_match_active_background` to theme schema
- Ensure search works in exited panes (Phase 1 dependency)

**Testable independently:** Open search in a pane with output, type queries, verify matches highlight, navigate between matches, verify scroll-to-match, test case sensitivity toggle, test with no matches, test with selected text pre-population.

### Phase 3: macOS Full-Screen and Accessibility
**Goal:** Full-screen works correctly; VoiceOver can navigate all workspace chrome.

**Scope:**
- Verify and enable native full-screen support on the window scene
- Handle layout adaptation for full-screen (SIGWINCH, title bar auto-hide)
- Persist `is_fullscreen` in session state
- Add VoiceOver labels, roles, and hints to space bar, tab bar, workspace indicator, workspace switcher, pane containers, and search overlay
- Add VoiceOver announcements for workspace/space/tab/pane switches and search navigation
- Add `allow_osc52_clipboard` configuration key

**Testable independently:** Enter/exit full-screen, verify terminal dimensions update, verify restore from full-screen state. Enable VoiceOver, navigate all workspace chrome, verify labels are spoken correctly.

### Phase 4: WCAG Contrast Audit and Performance Profiling
**Goal:** All bundled themes pass contrast requirements; performance metrics are collected and displayed.

**Scope:**
- Implement contrast ratio utility function
- Audit all bundled themes against WCAG 2.1 AA ratios; fix any failures
- Add debug assertions for contrast ratio violations
- Implement `PerformanceCollector` and all signal trackers (frame time, spawn latency, restore time, memory, restore correctness)
- Implement `DebugOverlayView`
- Register `toggle_debug_overlay` keybinding action
- Run performance profiling against targets; apply optimizations as needed

**Testable independently:** Run contrast utility against all themes, verify all pass. Toggle debug overlay, verify metrics display. Profile against performance targets with realistic workloads (10+ panes, 10,000-line scrollback, rapid output).

---

## 16. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| libghostty-vt does not expose a convenient API for extracting scrollback text for search | High -- search feature blocked | Medium | Investigate the C ABI early in Phase 2. Fallback: maintain a parallel text buffer in tian that mirrors libghostty-vt's scrollback line by line. |
| Metal render pipeline modifications for search highlighting introduce frame time regressions | Medium -- degrades rendering performance | Low | Search highlighting is structurally similar to selection highlighting (M1). Limit highlight processing to visible cells only. Profile before/after. |
| Full-screen SIGWINCH timing -- macOS animates the full-screen transition, causing multiple resize events | Low -- visual glitch during transition | Medium | Debounce SIGWINCH or defer terminal grid resize to `didEnterFullScreen` / `didExitFullScreen` rather than reacting to each intermediate size. |
| VoiceOver interaction with Metal-rendered terminal content | Medium -- terminal output may not be accessible to VoiceOver | High | Terminal content accessibility (reading terminal output via VoiceOver) is out of scope for M7 (FR-41 only covers workspace navigation UI). Document this as a known limitation. |
| Shell spawn latency exceeds 200ms target due to heavy shell init scripts (.zshrc) | Low -- outside tian's control | High | Measure and separate tian's spawn overhead from shell init time. Report both in the debug overlay. Document that shell init time is user-configurable. |
| Exited panes accumulating scrollback memory | Low -- user explicitly keeps them open | Low | Exited panes are no different from live panes in memory usage. Users can close them when done. |

---

## 17. Open Technical Questions

| # | Question | Context | Impact if unresolved |
|---|----------|---------|---------------------|
| 1 | What C API does libghostty-vt expose for reading scrollback buffer text? | Search engine needs to extract text from the terminal state. The exact function signatures and iteration model are unknown until the library is integrated. | Search implementation approach may need to change (parallel buffer vs. direct read). Must resolve before Phase 2 starts. |
| 2 | Does the M1 Metal renderer already support dirty-rect tracking, or does it re-render the full grid every frame? | Affects whether performance optimization in Phase 4 requires a renderer architecture change or just tuning. | If full-grid re-render: optimization may require significant renderer work. Assess during Phase 4. |
| 3 | How does the M1 selection highlighting work in the Metal pipeline? | Search highlighting should use the same mechanism. If selection is rendered as a separate pass or as a cell attribute, search should follow the same pattern. | Determines implementation approach for search highlighting. Resolve at start of Phase 2. |
| 4 | What is the persistence schema version after M5 and M6? | M7 needs to increment it. | Minor -- just need to know the current version number. |
| 5 | Should OSC 52 clipboard writes require user confirmation (like some terminals) or silently write? | Security consideration. Some terminals prompt, some silently allow, some disable by default. | Low -- defaulting to enabled (silent) matches most terminals. Can add confirmation later. |
| 6 | Should the search overlay support regex in addition to plain text? | Could be useful for developers, but adds complexity. | Low for v1 -- plain text search covers the primary use case. Regex can be added post-M7. |
