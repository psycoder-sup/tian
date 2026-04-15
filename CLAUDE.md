# tian

A native macOS terminal emulator built with SwiftUI. Uses the full ghostty embedding API (`ghostty_app_t` / `ghostty_surface_t`) from the Ghostty project. Ghostty handles PTY, VT parsing, Metal rendering, font atlas, cursor, selection, scrollback, and color themes internally. tian provides the NSView + CAMetalLayer and forwards keyboard/mouse events.

## Target

- **Platform:** macOS 26

## Concepts

tian organizes terminals in a 4-level hierarchy:

```
Workspace → Space → Tab → Pane (split tree)
```

- **Workspace** — Top-level organizational unit (e.g., a project). Each workspace maps to one OS window. Has a name, default working directory, and contains a `SpaceCollection`.
- **Space** — Named group of tabs within a workspace (similar to virtual desktops). Navigated with Cmd+Shift+Arrow. Contains an ordered list of `TabModel`s.
- **Tab** — Single tab within a space. Lightweight container that owns a `PaneViewModel` (split tree + surfaces). Displays the focused pane's title.
- **Pane** — A single terminal session. Panes live as leaves in a binary `SplitTree` (value-type). Each pane maps 1:1 to a `GhosttyTerminalSurface` (`ghostty_surface_t`). Panes can be split horizontally or vertically.

### Split Tree

Pane layout is modeled as an immutable binary tree (`SplitTree` / `PaneNode`):
- `.leaf(paneID, workingDirectory)` — a terminal pane
- `.split(id, direction, ratio, first, second)` — a container splitting two children

All mutations return new values (value semantics). `PaneViewModel` replaces the entire `splitTree` on each change. Spatial navigation between panes uses concrete layout frames, not tree position.

### Working Directory Resolution

Fallback chain: active pane (OSC 7) → pane node → space default → workspace default → `$HOME`.

### Lifecycle

Cascading close via `onEmpty` callbacks: `PaneViewModel` → `TabModel` → `SpaceModel` → `SpaceCollection` → `Workspace`.

## Architecture

### Source Layout

- `Workspace/` — `Workspace`, `WorkspaceCollection`, `WorkspaceManager`
- `Tab/` — `SpaceModel`, `TabModel`, `SpaceCollection`, `SpaceGitContext`
- `Pane/` — `PaneViewModel`, `SplitTree`, `PaneNode`, `SplitNavigation`, `SplitLayout`, `PaneHierarchyContext`, `PaneStatusManager`
- `Core/` — `GhosttyApp`, `GhosttyTerminalSurface`, notifications, IPC, `ClaudeSessionState`, `GitTypes`
- `View/` — SwiftUI components (terminal, sidebar, tabs, splits)
- `WindowManagement/` — `WorkspaceWindowController`, `WindowCoordinator`, `TianAppDelegate`
- `Persistence/` — Session serialization/restoration (`SessionState`)
- `DragAndDrop/` — Drag item types for reordering workspaces/spaces/tabs
- `Input/` — Key binding registry and handling
- `Utilities/` — `Logger`, `Colors`, `WorkingDirectoryResolver`
- `Vendor/` — `GhosttyKit.xcframework` + `ghostty.h` (built from `.ghostty-src` via `scripts/build-ghostty.sh`)

### Key Layers

- **App** — `TianApp` (SwiftUI entry point, GhosttyApp init), `TianAppDelegate` (lifecycle, session restoration)
- **Window** — `WindowCoordinator` (multi-window management), `WorkspaceWindowController` (NSWindowController per window)
- **Core** — `GhosttyApp` (singleton wrapping `ghostty_app_t`, runtime callbacks, clipboard, tick), `GhosttyTerminalSurface` (per-terminal `ghostty_surface_t` wrapper)
- **View** — `TerminalSurfaceView` (persistent NSView + CAMetalLayer, keyboard/mouse/IME forwarding), `WorkspaceWindowContent` (SwiftUI root per window)

### State Management

All model classes use `@MainActor @Observable`. Ghostty surface events flow through `NotificationCenter` (surface close/exit/title/pwd/bell). `PaneHierarchyContext` carries workspace/space/tab IDs down to panes as `TIAN_*` environment variables.

## Build

Run `scripts/build-ghostty.sh` to build and vendor GhosttyKit.xcframework from the ghostty source. Requires `zig` (`brew install zig`).

The Xcode project is generated via **XcodeGen** (`project.yml`). After adding, removing, or renaming source files, run `xcodegen generate` to regenerate `tian.xcodeproj`. Never edit `project.pbxproj` manually. `project.pbxproj` is gitignored — on a fresh clone, run `xcodegen generate` (or `scripts/build.sh`) once before opening the project in Xcode.

When using `xcodebuild`, always pass `-derivedDataPath .build` to keep build artifacts in the project directory.

Prefer `scripts/build.sh [Debug|Release]` (defaults to Debug) — it runs `xcodegen generate` then `xcodebuild` with the correct flags, avoiding stale-pbxproj bugs.

## Scratch / Temporary Files

Use `.dev/tmp/` for temporary code, experiments, and scratch files instead of `/tmp`. The `.dev/tmp/` subdirectory is gitignored; `.dev/` itself is tracked.

## Logs

File-logged categories (`ipc`, `lifecycle`, `persistence`, `git`) dual-write to `os.Logger` and `~/Library/Logs/tian/tian.log` (rotated to `tian.1.log`). See `tian/Utilities/FileLogWriter.swift`. Other categories (`core`, `view`, `ghostty`, `perf`, `worktree`) go to unified logging only — read with `log stream --predicate 'subsystem == "com.tian.app"'`.
