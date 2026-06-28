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

File-logged categories (`ipc`, `lifecycle`, `persistence`, `git`) dual-write to `os.Logger` and `~/Library/Logs/tian/tian.log` (rotated to `tian.1.log`). The debug build writes to `~/Library/Logs/tian-debug/tian.log` instead, so a running debug app and production app don't race on the same file. See `tian/Utilities/FileLogWriter.swift`. Other categories (`core`, `view`, `ghostty`, `perf`, `worktree`) go to unified logging only — read with `log stream --predicate 'subsystem == "com.tian.app"'`.

<!-- project-kit:begin — managed block. Safe to edit; re-running /project-kit updates only between these markers. -->

## Status

A native macOS terminal emulator (SwiftUI + embedded Ghostty) with a workspace model and CLI built for driving Claude Code sessions.

**Live state lives in [`docs/pm/status.json`](docs/pm/status.json) — read it first each session.** It's structured JSON; keep this section to a 2–4 line summary of the current focus and let `status.json` carry the detail. Humans: launch the live dashboard with `python3 docs/pm/dashboard/serve.py`.

- **Now:** Restructuring project docs into docs/pm via /project-kit (status + ADRs + dashboard).
- **Next:** Merge the /tian implement skill branch, then cut a release.

## Repo layout (context docs)

- `docs/pm/status.json` — live project state (now / next / milestones / blocked / shipped). The first thing to read each session — keep it lean. Shape: `docs/pm/schema/status.schema.json`.
- `docs/pm/decisions/` — decision records (ADRs): one JSON per direction change, numbered, fixed once accepted. `NNNN-*.json` are the records (shape: `schema/decision.schema.json`), `_template.json` is the skeleton, `README.md` is the auto-generated index.
- `docs/pm/schema/` — JSON Schemas: the field-by-field contract + guidance for each doc. Consult before writing/updating a JSON file.
- `docs/pm/dashboard/` — the read-only viewer: `serve.py` (stdlib, no installs) serves the docs and live-reloads on change; `index.html` is the dashboard. Run `python3 docs/pm/dashboard/serve.py`.

## Keeping the record current (do this without being asked)

`docs/pm/status.json` is the project's live state and the first thing to read each session. It's only useful if it's true, so maintaining it is part of finishing the work — not a separate request. The dashboard renders it live, so updates show up the moment you save. **After completing any meaningful unit of work — a task, a milestone step, a decision, a notable dead-end — update the record before treating the job as done:**

- **`docs/pm/status.json`** — add the finished item to `shipped` (with `date` and `commit`); **reset `now`** — a shipped item *leaves* `now`, it doesn't accumulate; update `next`; add or clear `blocked`; flip a milestone's `done` to `true` if one completed; bump `lastUpdated`. Match `schema/status.schema.json`. **Keep it lean — it's read every session:** `now`/`next` ≤3 items, ≤2 lines each; each entry is one claim + one pointer (link a commit/PR/ADR — never paste deploy run IDs or file-by-file lists). **`shipped` keeps only the newest ~3** (just enough to orient); when it grows past that, older entries simply drop off — `git log` (and the commit links you kept) is the full history, so there's no archive to maintain. Whole-file target ≤ ~150 lines.
- **`CLAUDE.md` → Status** — only if the current focus changed. Keep it to the 2–4 line summary (it's auto-loaded every session) and let it point at `status.json` for detail.
- **A decision record** (`docs/pm/decisions/NNNN-*.json`) — only when direction changed: a choice a future session shouldn't silently reverse. Routine progress needs no ADR. When one supersedes an earlier ADR, set `supersedes` on the new record and set `supersededBy` (and `status: "Superseded"`) on the old one. After adding or changing a record, regenerate `docs/pm/decisions/README.md`.

Keep entries specific and falsifiable — cite dates, link commits/ADRs. A stale status is worse than none: if unsure whether something shipped, say so in the file rather than guessing. `status.json` is a snapshot, not a journal — git history is the fine-grained log.

<!-- project-kit:end -->
