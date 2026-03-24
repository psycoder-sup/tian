# PRD: aterm

**Author:** psycoder
**Date:** 2026-03-24
**Version:** 1.4
**Status:** Approved

**Tech Stack:** Swift + SwiftUI (app chrome), libghostty-vt (VT parsing, C ABI), Metal (GPU rendering), POSIX PTY, macOS 26+
**macOS 26+ rationale:** Targets whatever the developer is running; no backwards compatibility burden (personal tool).

---

## 1. Overview

aterm is a fast, lightweight, GPU-accelerated terminal emulator for macOS. It introduces a 4-level workspace hierarchy (Workspace > Space > Tab > Pane) designed for developers who work across multiple projects and git worktrees simultaneously. Sessions persist across app launches, eliminating the need for external session managers like tmux.

---

## 2. Problem Statement

**User Pain Point:** Developers who work across multiple projects and branches simultaneously lack a terminal that organizes sessions by project context. They resort to tmux for session management, losing native macOS integration (keyboard shortcuts, window management, system services). Existing GPU-accelerated terminals like Ghostty lack workspace organization and session persistence.

**Current Workaround:** tmux sessions + terminal emulator. This requires maintaining tmux configuration, learning a separate keybinding system (prefix keys), and gives up native macOS behaviors. Alternatively, developers use many ungrouped terminal windows/tabs and rely on mental mapping to track which terminal belongs to which project.

**Business Opportunity:** Personal productivity tool. Success is measured by whether aterm fully replaces the developer's current terminal setup for daily use.

---

## 3. Goals & Non-Goals

### Goals

- **G1:** Provide a fully functional 4-level workspace hierarchy (Workspace > Space > Tab > Pane) that maps to real development workflows (projects, branches, tasks).
- **G2:** Persist and restore all session state across app launches -- layout, working directories, and running shell sessions.
- **G3:** Deliver GPU-accelerated terminal rendering that feels instant (no perceptible lag on normal operations, smooth scrolling through large output).
- **G4:** Provide chord-based keyboard navigation (Cmd+Shift+...) for all workspace operations so the user never needs to reach for the mouse.
- **G5:** Offer greater customizability than Ghostty -- user-configurable themes, profiles, and keybindings.

### Non-Goals (v1)

- **NG1:** Plugin/extension system.
- **NG2:** Telemetry or analytics collection.
- **NG3:** Linux or Windows support.
- **NG4:** Collaboration or remote session sharing.
- **NG5:** Built-in multiplexer protocol (tmux control mode integration).
- **NG6:** App Store distribution (developer-only usage initially).
- **NG7:** Automatic git branch detection (spaces are manually created in v1).
- **NG8:** Image protocol support (sixel, iTerm2 inline images) -- not required for v1.
- **NG9:** Export/import of named workspace configurations (post-v1).

---

## 4. User Stories

| # | As a... | I want to... | So that... |
|---|---------|--------------|------------|
| 1 | developer | create a named workspace for each project I work on | my terminal sessions are organized by project rather than a flat list of tabs |
| 2 | developer | create spaces within a workspace for different branches or worktrees | I can context-switch between branches without losing my terminal state |
| 3 | developer | split panes horizontally and vertically within a tab | I can view multiple terminal sessions side-by-side (e.g., editor + server + logs) |
| 4 | developer | quit the app and relaunch it with all my workspaces, spaces, tabs, panes, and working directories restored | I never lose my terminal layout or have to rebuild it manually |
| 5 | developer | navigate between workspaces, spaces, tabs, and panes entirely via keyboard | I maintain flow without reaching for the mouse |
| 6 | developer | assign a profile (font, color scheme, shell) to a workspace or space | different projects can have distinct visual identities |
| 7 | developer | see which workspace and space I am currently in at a glance | I always know my project and branch context |
| 8 | developer | configure keybindings to match my preferences | the shortcuts feel natural to my muscle memory |
| 9 | developer | scroll back through terminal output smoothly | I can review build output, logs, and command history without jank |
| 10 | developer | rename, reorder, and close workspaces, spaces, tabs, and panes | I can keep my workspace hierarchy tidy as my work evolves |
| 11 | developer | set a default working directory for a workspace or space | new tabs/panes open in the right project directory automatically |
| 12 | developer | select and copy text from the terminal | I can grab output for use elsewhere |

---

## 5. Functional Requirements

### Workspace Management

**FR-01:** The app must support creating, renaming, reordering (via drag-and-drop), and deleting named workspaces.

**FR-02:** Each workspace must support creating, renaming, reordering (via drag-and-drop), and deleting named spaces within it.

**FR-03:** Each space must support creating, closing, and reordering tabs within it.

**FR-04:** Each tab must support splitting into panes -- both horizontal and vertical splits -- and closing individual panes. Splits are nestable: a split region can be further split in either direction, forming a recursive tree of panes.

**FR-05:** When a pane is closed and it is the last pane in a tab, the tab closes. When the last tab in a space closes, the space closes. When the last space in a workspace closes, the workspace closes. When the last workspace closes, the app quits.

**FR-06:** The app must display the current workspace name, space name, and tab in a visible indicator (e.g., title bar or status area) at all times.

**FR-07:** Users must be able to switch between workspaces via a keyboard shortcut. The switcher must support fuzzy search by workspace name.

**FR-08:** Users must be able to switch between spaces within the current workspace via a keyboard shortcut.

**FR-09:** Users must be able to switch between tabs within the current space via keyboard shortcuts (next/previous tab, go-to-tab-by-number).

**FR-10:** Users must be able to move focus between panes within the current tab via directional keyboard shortcuts (up/down/left/right).

### Terminal Core

**FR-11:** Each pane must host an independent terminal session connected to a PTY running the user's default shell.

**FR-12:** The terminal must correctly handle standard VT100/VT220/xterm escape sequences as supported by libghostty-vt (cursor movement, colors, alternate screen, scrollback).

**FR-13:** The terminal must support at minimum 256-color and true-color (24-bit) output.

**FR-14:** The terminal must maintain a scrollback buffer of configurable length (default: 10,000 lines) per pane.

**FR-15:** Scrolling through the scrollback buffer must be smooth (GPU-accelerated) with no visible stuttering at 60fps on supported hardware.

**FR-16:** Terminal output must report correct terminal dimensions ($COLUMNS, $LINES, SIGWINCH) and update them when a pane is resized.

**FR-17:** The terminal must correctly handle Unicode text including multi-byte characters, combining characters, and wide (CJK) characters.

### Rendering

**FR-18:** All terminal cell rendering must be performed on the GPU via Metal. The renderer must use a font atlas and instanced cell rendering.

**FR-19:** The renderer must support configurable font family and font size.

**FR-20:** The renderer must support bold, italic, underline, strikethrough, and inverse text attributes.

**FR-21:** Cursor rendering must support block, underline, and bar styles, with configurable blinking.

### Persistence

**FR-22:** On app quit, if any pane has a foreground process running (other than the shell itself), the app must show a confirmation dialog listing the affected panes and process names. On confirm, the app sends SIGHUP to all PTY sessions and proceeds with quit. On cancel, the quit is aborted.

**FR-23:** On app quit (after confirmation if needed), the app must first serialize the full workspace hierarchy to disk as JSON, then send SIGHUP to all PTY sessions. The persisted state includes: all workspaces, their spaces, tabs within each space, pane split tree within each tab (including nested split directions and ratios), the working directory of each pane, and the last-active workspace/space/tab/pane. State is stored in `~/Library/Application Support/aterm/` with a `"version"` field for future schema migration. If serialization fails (e.g., disk full, permission error), the app proceeds with quit (kills processes); on next launch it starts with a fresh default workspace.

**FR-24:** On app launch, the app must restore the persisted hierarchy including the full pane split tree and working directories. Each restored pane opens a fresh shell session in its saved working directory (no command replay in v1). If no persisted state exists (first launch), the app opens a workspace named "default" with one space, one tab, and one pane in `$HOME`.

**FR-25:** When a shell process exits in a pane (exit code 0), the pane closes automatically. When a shell exits with a non-zero exit code or crashes, the pane must display the exit code and a message (e.g., "[process exited with code 1]") and remain open until the user explicitly closes it.

### Configuration

**FR-26:** The app must read configuration from a user-editable configuration file (not just a GUI settings panel).

**FR-27:** The configuration must support defining custom keybindings for all workspace navigation and terminal operations.

**FR-28:** The configuration must support defining named profiles that specify: font family, font size, color scheme, default shell, and default working directory.

**FR-29:** Profiles must be assignable at the workspace level, space level, or globally (with inheritance: pane inherits from space, space inherits from workspace, workspace inherits from global).

**FR-30:** The app must support defining and switching between named color themes.

**FR-31:** Configuration changes must take effect without requiring an app restart (live reload or reload command).

### Input & Selection

**FR-32:** The terminal must support text selection via mouse click-and-drag and keyboard (Shift+arrow).

**FR-33:** Selected text must be copyable to the system clipboard (Cmd+C). Paste from clipboard must work via Cmd+V.

**FR-34:** Double-click must select a word. Triple-click must select a line.

**FR-35:** The app must support a keyboard shortcut to open a "find in scrollback" search overlay for the active pane.

### Window Management

**FR-36:** The app must support multiple macOS windows, each displaying one workspace.

**FR-37:** The app must support native macOS full-screen mode.

**FR-38:** The app must support standard macOS window operations (minimize, zoom, drag-to-resize).

### Pane Resize

**FR-43:** Panes must be resizable via drag handles. Resize proportions are percentage-based and configurable in the TOML configuration file.

### Visual Design

**FR-39:** The space bar and tab bar must be visually distinct from each other (e.g., through different background colors, separator weight, typography, or spatial grouping) so users can immediately tell which row represents spaces and which represents tabs.

### Accessibility

**FR-40:** All workspace navigation (switching workspaces, spaces, tabs, panes) must be operable entirely via keyboard without requiring a mouse.

**FR-41:** The space bar, tab bar, and workspace switcher must expose appropriate labels and roles for VoiceOver navigation.

**FR-42:** All UI chrome (space bar, tab bar, workspace indicator, status text) must meet WCAG 2.1 AA minimum contrast ratios (4.5:1 for normal text, 3:1 for large text) in both the default theme and any bundled themes.

---

## 6. UX & Design

### Information Architecture

```
Window (macOS native)
├── Workspace indicator (title bar area)
├── Space bar (horizontal tabs showing spaces within current workspace)
├── Tab bar (horizontal tabs showing tabs within current space)
└── Content area
    └── Pane grid (split layout)
        ├── Pane 1 (terminal)
        ├── Pane 2 (terminal)
        └── ...
```

### User Flow: Create a New Project Workspace

```
Precondition: App is running with at least one existing workspace.

Happy Path:
1. User presses workspace creation shortcut (e.g., Cmd+Shift+N)
2. App presents a name input field (inline or modal)
3. User types workspace name (e.g., "tickle-app") and presses Enter
4. App creates the workspace with one default space ("default"), one tab, one pane
5. Pane opens the user's default shell in the configured working directory (or home)
6. Workspace indicator updates to show "tickle-app"

Alternate Flows:
- User cancels name input (Esc) -> No workspace created, focus returns to previous pane
- User enters a duplicate name -> App appends a disambiguator or shows inline error

Error States:
- Shell fails to launch -> Pane shows error message with the failed command and exit code

Empty States:
- N/A -- a new workspace always starts with one space/tab/pane
```

### User Flow: Switch Between Workspaces

```
Precondition: Multiple workspaces exist.

Happy Path:
1. User presses workspace switcher shortcut (e.g., Cmd+Shift+W)
2. App displays an overlay listing all workspaces with fuzzy search
3. User types to filter, then selects a workspace and presses Enter
4. App switches to the selected workspace, restoring the last-active space/tab/pane
5. Overlay dismisses. Focus is in the restored pane.

Alternate Flows:
- User presses Esc -> Overlay dismisses, no switch
- Only one workspace exists -> Switcher still opens (user may want to create a new one)

Loading States:
- If workspace was previously unloaded from memory -> Brief loading indicator while restoring
```

### User Flow: Split a Pane

```
Precondition: A pane has focus.

Happy Path:
1. User presses split shortcut (e.g., Cmd+Shift+D for vertical, Cmd+Shift+E for horizontal)
2. App splits the focused pane, creating a new pane adjacent to it
3. New pane inherits the working directory of the source pane
4. New pane opens a new shell session
5. Focus moves to the new pane

Alternate Flows:
- Maximum pane limit reached (if any) -> No action, optional subtle feedback

Error States:
- Shell fails to spawn in new pane -> New pane shows error, existing pane unaffected
```

### User Flow: App Quit and Restore

```
Precondition: User has multiple workspaces with spaces, tabs, and panes open.

Happy Path:
1. User quits the app (Cmd+Q or menu)
2. If any pane has a foreground process running, app shows a confirmation dialog listing affected panes
3. User confirms quit (or no foreground processes were running)
4. App serializes the full workspace hierarchy (layout, working directories) to disk, then sends SIGHUP to all PTY sessions
5. User relaunches the app
6. App reads persisted state and reconstructs all workspaces, spaces, tabs, and pane layouts
7. Each pane spawns a new shell in its saved working directory
8. App focuses the last-active workspace/space/tab/pane

Alternate Flows:
- User cancels the quit confirmation dialog -> Quit is aborted, user returns to the app
- Persisted state file is corrupted or missing -> App launches with a single default workspace
- A saved working directory no longer exists -> Pane opens shell in home directory, shows a one-time notice

Loading States:
- During restore -> App window appears immediately with pane placeholders, shells spawn asynchronously
```

### Platform-Specific Behavior

| Behavior | macOS |
|----------|-------|
| Window chrome | Native SwiftUI title bar with workspace indicator |
| Full screen | Native macOS full-screen (green button) |
| Keyboard shortcuts | Cmd-based chords (Cmd+Shift+...) |
| Font rendering | Core Text / Metal font atlas |
| Clipboard | System pasteboard (NSPasteboard) |

---

## 7. Permissions & Privacy

**Device Permissions:**
- Full Disk Access: not required by default; user may grant if their shell or tools need it.
- Accessibility: not required in v1.

**Data Collected / Stored / Shared:**
- No data is collected or shared externally.
- Workspace state (names, layout, working directory paths) is stored locally on disk.
- No telemetry, no crash reporting to external services in v1.

**Compliance:** Not applicable (personal tool, no user data collection).

---

## 8. Analytics & Instrumentation

No external analytics in v1 (non-goal NG2).

**Internal observability (for developer debugging only):**

| Signal | Purpose |
|--------|---------|
| Frame render time (ms) | Detect rendering regressions |
| Shell spawn latency (ms) | Detect slow session creation |
| Restore time (ms) | Detect slow app launch with many workspaces |
| Memory per pane | Detect scrollback buffer leaks |
| Restore correctness (%) | Ratio of panes restored with correct layout and working directory vs. total panes saved. Log mismatches with details. |

These should be available via a debug overlay or log, not sent externally.

---

## 9. Success Metrics

Since this is a personal tool with a single user, success is qualitative:

| Metric | Target |
|--------|--------|
| Daily driver | Developer uses aterm as their only terminal for all work |
| Session restore reliability | 100% of workspace layouts restore correctly on relaunch |
| Restore correctness (instrumented) | Restore correctness % (logged at launch) must be 100% for layout and working directories across 20 consecutive app restarts |
| Rendering smoothness | No perceptible frame drops during normal use (typing, scrolling, resizing) |
| Keyboard coverage | All workspace/space/tab/pane operations achievable without mouse |
| Launch to usable | App is interactive within 1 second of launch (cold start with restored state) |
| Shell spawn latency | New pane is usable within 200ms of the split/create action |

---

## 10. Open Questions

| # | Question | Owner | Due Date |
|---|----------|-------|----------|
| ~~1~~ | ~~What configuration file format?~~ **Resolved:** TOML. | psycoder | Resolved |
| 2 | Should spaces auto-detect the current git branch, or is manual naming sufficient for v1? | psycoder | TBD |
| ~~3~~ | ~~What is the maximum number of panes per tab?~~ **Resolved:** No limit — left to the user's discretion. | psycoder | Resolved |
| 4 | Should workspace switcher support creating a new workspace inline, or only switch between existing ones? | psycoder | TBD |
| ~~5~~ | ~~What happens to running processes on quit?~~ **Resolved:** Show confirmation dialog if foreground processes are running; kill on confirm (see FR-22). | psycoder | Resolved |
| ~~6~~ | ~~Should "restore running sessions" attempt to replay the last command, or only restore the working directory with a fresh shell?~~ **Resolved:** Fresh shell only in v1. Command replay deferred to post-v1. | psycoder | Resolved |
| 7 | What is the default color scheme and font? Ship a built-in set or require user configuration from the start? | psycoder | Before M1 |
| ~~8~~ | ~~How should pane resize work?~~ **Resolved:** Both drag handles and percentage-based keyboard resize, configurable in TOML (see FR-43). | psycoder | Resolved |
| 9 | Should the app expose a CLI tool (e.g., `aterm open workspace-name`) for scripting? | psycoder | TBD |
| ~~10~~ | ~~What is the persistence format for workspace state?~~ **Resolved:** JSON. | psycoder | Resolved |

---

## 11. Milestones

### M1: Terminal Fundamentals
**Goal:** A single-window, single-pane terminal that renders correctly and is usable as a basic terminal emulator.

- PTY spawns user's default shell
- VT escape sequence handling via libghostty-vt
- GPU-rendered text output (Metal + font atlas)
- Keyboard input, text selection, copy/paste
- Scrollback buffer with smooth scrolling
- Correct Unicode rendering
- Basic color scheme support

### M2: Pane Splitting
**Goal:** Support multiple panes within a single tab.

- Horizontal and vertical splits
- Directional focus navigation between panes
- Pane resize via drag handles (FR-43)
- Close individual panes
- New panes inherit working directory

### M3: Tabs and Spaces
**Goal:** Full tab and space support within a workspace.

- Create, close, rename, reorder tabs
- Tab bar UI with keyboard navigation
- Create, close, rename spaces
- Space bar/indicator UI with clear visual differentiation from tab bar (FR-39)
- Switch between spaces via keyboard

### M4: Workspaces
**Goal:** Multi-workspace support with switching and visual context.

- Create, rename, delete workspaces
- Workspace switcher with fuzzy search
- Workspace indicator in window chrome
- Multiple windows (one workspace per window)
- Default working directory per workspace/space

### M5: Persistence
**Goal:** Full session restore across app launches.

- Confirmation dialog on quit if foreground processes are running (FR-22)
- Serialize workspace hierarchy on quit
- Restore layout and working directories on launch
- Restore correctness % instrumentation (logged at launch)
- Handle missing directories and corrupted state gracefully
- Fast restore (under 1 second target)

### M6: Configuration and Customization
**Goal:** User-configurable themes, profiles, keybindings.

- Configuration file (TOML format)
- Named profiles with font, color, shell settings
- Profile inheritance (global > workspace > space)
- Custom keybindings
- Named color themes
- Live reload of configuration changes

### M7: Daily Driver Polish
**Goal:** Resolve remaining rough edges blocking daily use.

- Find-in-scrollback search
- Native macOS full-screen support
- Edge case handling (shell crashes, permission errors, unusual terminal sequences)
- Shell exit/crash behavior (FR-25: show exit code, keep pane open on non-zero exit)
- VoiceOver labels for workspace navigation UI (FR-41)
- Performance profiling and optimization

---

## Appendix

### Competitive Landscape

| Feature | aterm (planned) | Ghostty | iTerm2 | Alacritty | Kitty | WezTerm |
|---------|----------------|---------|--------|-----------|-------|---------|
| GPU rendering | Yes (Metal) | Yes (Metal/OpenGL) | Metal | OpenGL | OpenGL | OpenGL/Metal |
| Workspace hierarchy | 4-level | None | Profiles/arrangements | None | Layouts | Tabs + panes |
| Session persistence | Yes | No | Partial (arrangements) | No | Partial (sessions) | No |
| macOS native | Yes (SwiftUI) | Yes | Yes (Obj-C) | No (cross-platform) | No (cross-platform) | No (cross-platform) |
| Customizability | High (goal) | Limited | High | Config file | Extensive | Lua scripting |
| Cross-platform | No | Yes | No | Yes | Yes | Yes |

### Motivation

The developer currently uses a combination of terminal emulator + tmux for session management across multiple projects and git worktrees. This workflow has friction:
- tmux prefix keys conflict with macOS keyboard conventions
- No native macOS window management integration with tmux
- Session restore in tmux requires plugins and is fragile
- No visual distinction between project contexts

aterm aims to collapse the terminal + tmux stack into a single native application with first-class project workspace management.
