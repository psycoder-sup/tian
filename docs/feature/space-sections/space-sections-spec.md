# SPEC: Space Sections (Claude + Terminal)

**Based on:** docs/feature/space-sections/space-sections-prd.md v1.1
**Author:** CTO Agent
**Date:** 2026-04-23
**Version:** 1.3
**Status:** Approved

---

## Version History

| Version | Date | Author | Notes |
|---------|------|--------|-------|
| 1.0 | 2026-04-23 | CTO Agent | Initial draft |
| 1.1 | 2026-04-23 | CTO Agent | Spec-reviewer revision: explicit migration pseudocode with `claudeSessionState` preservation and relaxed `SessionRestorer.validate`; cascade rewritten so Space never auto-closes from Claude emptiness alone; FR-29 deferred to follow-up; `SectionSpawner.configure` signature expanded with `environmentVariables`; explicit decision table for show/hide/reset; phase re-ordering (compat shim between Phase 1 and Phase 4); `SpaceModel.focusedSection` helper; `TabState.sectionKind` now non-optional; test skeletons fixed; new FR-08 Retry and FR-15 mid-drag toggle skeletons |
| 1.2 | 2026-04-23 | CTO Agent | Round-2 revision: FR-08b Retry skeleton rewritten using real APIs (`surfaceSpawnFailedNotification`, `restartShell`); migrator closure signature matches `Migration` typealias (value-returning); `RestoreError.emptyTabs` extended with `kind`; `.closeTab` removed from Section 6 key-action table — documented the real dual Cmd+W entry point (surface `performKeyEquivalent` vs placeholder `.cancelAction`); `TabModel.sectionKind` moved from extension to class body; Phase 1 snapshot write path specified (derive v3 `tabs` from terminalSection; Claude layout not persisted pre-Phase 4); `SectionLayout`, `SectionDividerClamper`, `SectionTabBarDropCoordinator`, `SectionDividerDragController` promoted into Section 7 types; `focusedSectionKind` round-trip added; FR-06 skeleton added; Cmd+W-on-empty-Claude reconciled with parent PRD FR-22 foreground-process confirmation; `state.prev.json` escape-hatch note clarified |
| 1.3 | 2026-04-23 | CTO Agent | Round-3 revision: fix test skeleton compile errors (`surface(for:)?.id` instead of nonexistent `surfaceID(for:)`; notification userInfo keys use `"surfaceId"` lowercase-d with `UInt32` exit codes); resolve `setDockPosition` vs `enqueueDockPosition` contract — public entry is `SpaceModel.setDockPosition` which consults `sectionDividerDragController.isDragging`; give `requestSpaceClose` a real foreground-process confirm policy hook backed by `SpaceCloseConfirmationCoordinator`; document Phase 1–4 user-exposure rule with Option A (squash-merge) preferred; strengthen FR-08b skeleton with second spawn-failure assertion and unit-test-no-window caveat; fix delegate signature quote (`terminalSurfaceViewRequestClose(_:)`); add `SectionModel.init` precondition assertions; document `hideTerminal()` keeps `focusedSectionKind` but `.nextTab` no-ops while hidden; Phase 1 explicitly deletes `SpaceModel.onEmpty` and rewrites `wireSpaceClose` in the same commit |

---

## 1. Overview

This spec describes how to split a Space's interior into two role-typed sections — a mandatory **Claude section** and an optional **Terminal section** — while preserving the existing 4-level hierarchy (Workspace → Space → Tab → Pane) and the value-typed split tree (`SplitTree` / `PaneNode`).

The current implementation treats a `SpaceModel` as owning a flat `[TabModel]` list. This feature inserts an intermediate concept between `SpaceModel` and `[TabModel]` by introducing a new `SectionModel` value that owns the `[TabModel]` list, the active tab id, and a `SectionKind` discriminator (`.claude` or `.terminal`). A `SpaceModel` now holds two `SectionModel` instances plus section-level metadata (visibility of the Terminal section, dock position, split ratio, last-focused section). Each pane's section identity is derived from the section it belongs to — panes are not moved across sections (PRD NG5), so the parent section is the source of truth for "this pane must spawn `claude`" vs "this pane must spawn shell".

Persistence, the `onEmpty` cascade, key bindings, and spatial navigation all extend the existing code paths rather than replacing them. Spawn-kind enforcement happens at pane-creation sites (the two `createTab`/`splitPane` call sites) where the owning section decides the launch command. A one-shot migration at schema version 4 rewires legacy `SpaceState.tabs` into `SpaceState.terminalSection.tabs` and synthesises a fresh `claudeSection` with a single Claude pane.

---

## 2. Database Schema

Not applicable — tian has no database. Persistence is JSON at `~/Library/Application Support/tian/state.json` (see `tian/Persistence/SessionSerializer.swift`). The equivalent of schema changes is the `SessionState` Codable tree and the migrator chain at `tian/Persistence/SessionStateMigrator.swift`.

### Current (v3) layout

```
SessionState
└── WorkspaceState
    └── SpaceState { id, name, activeTabId, defaultWorkingDirectory, worktreePath, tabs: [TabState] }
        └── TabState { id, name, activePaneId, root: PaneNodeState }
            └── PaneNodeState .pane(PaneLeafState) / .split(PaneSplitState)
```

### New (v4) layout

```
SessionState (unchanged: version, savedAt, activeWorkspaceId, workspaces)
└── WorkspaceState (unchanged: id, name, activeSpaceId, defaultWorkingDirectory, windowFrame, isFullscreen)
    └── SpaceState {
          id, name, defaultWorkingDirectory, worktreePath,
          claudeSection: SectionState,
          terminalSection: SectionState,
          terminalVisible: Bool,
          dockPosition: "right" | "bottom",
          splitRatio: Double (0.1...0.9, default 0.7),
          focusedSectionKind: "claude" | "terminal"
        }
        └── SectionState { id: UUID, kind: "claude" | "terminal", activeTabId: UUID?, tabs: [TabState] }
            └── TabState { id, name, activePaneId, root: PaneNodeState, sectionKind: "claude" | "terminal" }
                └── PaneNodeState .pane(PaneLeafState) / .split(PaneSplitState) (unchanged; `PaneLeafState.claudeSessionState` preserved through migration)
```

Only `SpaceState` is reshaped. `SessionState` and `WorkspaceState` fields are preserved verbatim by the migration (see Section 11 for the exhaustive list).

Field-by-field table:

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `SpaceState.claudeSection` | `SectionState` | synthesised on migration | Always present; **must have ≥1 tab** (enforced by `SessionRestorer.validate`) |
| `SpaceState.terminalSection` | `SectionState` | populated on migration from legacy `SpaceState.tabs` | **May have zero tabs** on fresh Spaces and after FR-12 auto-hide; always present in the schema for symmetry. `activeTabId` is nullable when `tabs.isEmpty` |
| `SpaceState.terminalVisible` | `Bool` | `false` on new Space; `false` on migrated Space (per FR-25) | Drives `FR-02`, `FR-12`, `FR-13` |
| `SpaceState.dockPosition` | `String` | `"right"` | See PRD FR-14 |
| `SpaceState.splitRatio` | `Double` | `0.7` | Single value reused across orientations (NG10 / FR-16) |
| `SpaceState.focusedSectionKind` | `String` | `"claude"` | Drives FR-20 "cycle focus between sections" |
| `SectionState.id` | `UUID` | newly generated on migration | Enables diagnostic log pairing between in-memory and on-disk sections |
| `SectionState.kind` | `String` | fixed per section | `"claude"` or `"terminal"`; mirrors `SectionKind` in-memory |
| `SectionState.activeTabId` | `UUID?` | nil only when `tabs.isEmpty` | Each section owns its own active tab pointer |
| `TabState.sectionKind` | `String` | **required** in v4 (no longer optional) | Non-optional removes the "infer on decode" branch (closes open question 15.1). Migration sets this explicitly on every tab; fresh tabs set it from the owning section |
| `PaneLeafState.claudeSessionState` | `ClaudeSessionState?` | preserved verbatim from v3 | Migration moves `TabState` subtrees wholesale, so `claudeSessionState` on legacy shell panes survives into `terminalSection`. Claude-section synthesised panes have `claudeSessionState = nil` |

Legacy `SpaceState.tabs` and `SpaceState.activeTabId` are removed in v4. Each section carries its own `activeTabId`. Focus-at-space-level is derived from `focusedSectionKind` + the matching section's `activeTabId` + that tab's pane `activePaneId`.

### Validation rules (v4)

`SessionRestorer.validate` is updated to treat the two sections asymmetrically:

| Rule | Claude section | Terminal section |
|------|----------------|------------------|
| `tabs` may be empty | No — decode fails | Yes — permitted and expected (fresh Space or auto-hidden) |
| `activeTabId` resolvable | Required when `!tabs.isEmpty`; otherwise must be `nil` | Required when `!tabs.isEmpty`; otherwise must be `nil` |
| Stale `activeTabId` fix | Existing behaviour (auto-pick first tab and log `stalePaneIdFix`) | Same |

**`RestoreError` changes** (v4):

The existing case `emptyTabs(spaceName: String)` is extended to carry a `kind` so Claude-side and Terminal-side failures can be distinguished in logs without breaking existing consumers more than necessary:

- Before: `case emptyTabs(spaceName: String)` (`tian/Persistence/SessionRestorer.swift:14`).
- After: `case emptyTabs(spaceName: String, kind: SectionKind)`.

All existing log / description consumers are updated accordingly: `SessionRestorer.description` gets a kind-aware message ("Space '\(name)' has no tabs in \(kind) section"); `validate` throws the new form with `kind: .claude` when `claudeSection.tabs.isEmpty`, and silently passes when `terminalSection.tabs.isEmpty`. The call site today (`SessionRestorer.swift:102`) is the only throwing site and is the only place that needs the associated-value update. Tests in `SessionRestorerTests` (if any) that pattern-match on `emptyTabs` get a new binding.

Concretely: the existing single `emptyTabs` check becomes two checks, one per section, with the Terminal side allowed to pass through.

### Indexes

Not applicable. JSON is loaded fully into memory at launch.

### Access Policies

Not applicable. The persisted file is chmod `0600` (owner read/write only) as set by `SessionSerializer.save`. No change.

### Data Flow

1. **On app launch** — `TianAppDelegate` calls `SessionRestorer.loadState()` which invokes `SessionStateMigrator.migrateIfNeeded(data:)`. If the version is ≤3, the migrator chain runs v3 → v4 (section synthesis). The result is decoded as `SessionState` with the new shape, validated, and passed to `SessionRestorer.buildWorkspaceCollection` which now constructs `SectionModel` instances in addition to `SpaceModel`.
2. **On user action (e.g. split Claude pane)** — `PaneViewModel.splitPane` runs, the owning `SectionModel` records the new pane id and marks it as Claude-kind (same kind as the source pane). The new pane's initial input is wired through the existing `TerminalSurfaceView.initialInput` mechanism to inject `claude\n` on first prompt.
3. **On app quit** — `SessionSerializer.snapshot` walks each `WorkspaceCollection → Workspace → SpaceCollection → SpaceModel → [SectionModel]` and emits the new `SpaceState` shape described above.

---

## 3. API Layer

### Runtime "API"

tian has no HTTP API. "API layer" for this spec means the public methods on model classes that the view and key-binding layers call. The following table lists new or modified methods, grouped by owning class.

#### `SectionModel` (new, `tian/Tab/SectionModel.swift`)

| Method | Purpose | Called From |
|--------|---------|------------|
| `init(kind:initialTab:)` | Create a section with one tab of the given kind | `SpaceModel.init`, migration |
| `init(id:kind:tabs:activeTabID:)` | Restore from persisted state | `SessionRestorer` |
| `createTab(workingDirectory:)` | Append a new tab; seed it with a Claude or shell pane depending on `kind` | Key handler (FR-09/FR-21), "New Claude pane" placeholder button |
| `removeTab(id:)` | Remove tab; may trigger `onEmpty` | Tab close UI, cascade |
| `nextTab()` / `previousTab()` / `goToTab(index:)` | Tab navigation | `KeyBindingRegistry` → `WorkspaceWindowController` |
| `reorderTab(from:to:)` | Drag-reorder within section | `SectionTabBarView` |
| `closeOtherTabs(keepingID:)` / `closeTabsToRight(ofID:)` | Context-menu batch close | Tab context menu |
| `onEmpty: (() -> Void)?` | Fires when last tab removed | Wired by `SpaceModel` |

#### `SpaceModel` (modified, `tian/Tab/SpaceModel.swift`)

| Method | Purpose | Called From |
|--------|---------|------------|
| `showTerminal()` | Make Terminal section visible. If `terminalSection.tabs.isEmpty` (fresh Space or after FR-12 auto-hide), spawn one shell tab+pane; otherwise leave preserved tabs untouched and refocus | Toolbar button (FR-09), `Ctrl+`` ` `` handler |
| `hideTerminal()` | Set `terminalVisible = false`. **Never mutates `terminalSection.tabs`**; tabs + panes + shell processes stay alive in the background per FR-13 | Toolbar button, `Ctrl+`` ` ``, drag-past-minimum (FR-16), last-pane-close auto-hide (FR-12 — which runs after the normal pane-remove flow has already cleared `tabs`) |
| `toggleTerminal()` | Convenience wrapper | Key binding |
| `setDockPosition(_:)` | Public entry point for dock change. If `sectionDividerDragController.isDragging`, the toggle is queued and applied on drag end (FR-15); otherwise applied immediately. Never closes panes. | Terminal header toggle |
| `setSplitRatio(_:)` | Write new ratio (clamped to pixel minimums elsewhere) | Divider drag, restore |
| `resetTerminalSection()` | Close all Terminal tabs/panes (sends SIGHUP to every shell), return section to zero-tab state, set `terminalVisible = false` (FR-13 action) | Terminal header menu |
| `cycleFocusedSection()` | FR-20 Cmd+Shift+` behaviour | Key handler |
| `requestSpaceClose()` | Explicit user close — see Section 9 | Empty Claude placeholder Cmd+W, sidebar, context menu |

**Show / hide / reset decision table.** This table disambiguates the three "hide"-ish code paths and their interaction with `showTerminal`:

| Trigger | `terminalSection.tabs` after | `terminalVisible` after | Shell processes |
|---------|------------------------------|-------------------------|------------------|
| User clicks Hide Terminal / presses Ctrl+` while visible | Unchanged (preserved) | `false` | Kept alive (FR-13) |
| User drags divider past Terminal minimum (FR-16) | Unchanged (preserved) | `false` (calls `hideTerminal()` on gesture end) | Kept alive |
| Last Terminal pane closes via Cmd+W or shell exit (FR-12) | Empty (the normal pane-removal flow already cleared tabs **before** auto-hide fires) | `false` (via `SectionModel.onEmpty` → `SpaceModel.hideTerminal()`) | Dead (they exited) |
| User selects "Reset Terminal section" from header menu (FR-13) | Empty (explicit teardown) | `false` | Killed via SIGHUP |
| User presses Ctrl+` while hidden AND `tabs.isEmpty` | Spawns fresh single tab+pane in Space's resolved wd | `true` | Fresh shell |
| User presses Ctrl+` while hidden AND `tabs.nonEmpty` (preserved layout) | Unchanged (restored) | `true` | Still alive (never died) |

**Invariants:**
- `hideTerminal()` never clears `tabs`. Any "empty" state reached via auto-hide is produced upstream by the pane-removal flow, not by `hideTerminal` itself.
- `hideTerminal()` also **never mutates `focusedSectionKind`**. If the Terminal section was focused at the moment of hide, `focusedSectionKind` stays `.terminal` so `showTerminal()` can restore focus naturally. Key handlers that would operate on the Terminal section while it's hidden (e.g., `.nextTab`) must check `terminalVisible` and no-op if hidden, regardless of `focusedSectionKind`.
- `showTerminal()` spawns a new tab **only when** `tabs.isEmpty`. Otherwise it is visibility-only.
- `resetTerminalSection()` is the only path that intentionally kills live shell processes in the Terminal section. It also resets `focusedSectionKind = .claude`.

Computed / observed properties added to `SpaceModel`:

- `claudeSection: SectionModel`
- `terminalSection: SectionModel`
- `terminalVisible: Bool`
- `dockPosition: DockPosition` (`.right` / `.bottom`)
- `splitRatio: Double`
- `focusedSectionKind: SectionKind`
- `lastFocusedPaneID(in:)` — returns the most-recently-focused pane id for a given `SectionKind` (for FR-20 alternation)

#### `PaneViewModel` (modified, `tian/Pane/PaneViewModel.swift`)

No new public methods; instead, a **sectionKind** hint is threaded through at construction time and through the split path so the surface knows whether to inject `claude\n` via `initialInput`. Two approaches:

- Add `var sectionKind: SectionKind` to `PaneViewModel`. Preferred — it already carries other context (`hierarchyContext`, `directoryFallback`).
- Add `sectionKind` as a parameter to `splitPane(direction:targetPaneID:)` (Unnecessary — the section is fixed per tab).

We choose the first approach.

#### `KeyAction` (modified, `tian/Input/KeyAction.swift`)

Two new cases:

| Case | Default shortcut | Action |
|------|------------------|--------|
| `.toggleTerminalSection` | `` Ctrl+` `` (keyCode 50, modifiers `[.control]`) | Calls `activeSpace.toggleTerminal()` |
| `.cycleSectionFocus` | `` Cmd+Shift+` `` (keyCode 50, modifiers `[.command, .shift]`) | Calls `activeSpace.cycleFocusedSection()` |

Registered in `KeyBindingRegistry.defaults()` alongside existing bindings.

#### `SectionSpawner` (new, `tian/Tab/SectionSpawner.swift`)

Small helper used at every pane-creation site to enforce FR-05/FR-11. Given a `SectionKind`, a working directory, and a pre-built environment-variable dictionary, it configures a new `TerminalSurfaceView`:

- `view.initialWorkingDirectory = workingDirectory`
- `view.environmentVariables = environmentVariables` (propagates `TIAN_WORKSPACE_ID`, `TIAN_SPACE_ID`, `TIAN_TAB_ID`, `TIAN_PANE_ID`, `TIAN_SOCKET`, etc. — identical to the path used today in `PaneViewModel.splitPane`)
- **Claude:** `view.initialInput = "claude\n"` (the wrapper at `tian/Resources/claude` is already on PATH via `EnvironmentBuilder` and handles the real `claude` invocation / PATH lookup)
- **Terminal:** `view.initialInput = nil` (normal shell prompt)

This keeps the `"claude\n"` literal in exactly one place. Environment variables are **not** computed inside `SectionSpawner` — the caller is responsible for computing them via `EnvironmentBuilder` / `PaneHierarchyContext` so that all existing call-sites keep using the same builder. `SectionSpawner` only plumbs them through.

**Call-site map** — every site that creates a `TerminalSurfaceView` must route through `SectionSpawner.configure(...)`:

| Call site | Section kind source | Environment source |
|-----------|---------------------|-------------------|
| `SectionModel.init(kind: .claude, initialTab:)` synthesised by `SpaceModel.init` | literal `.claude` | `EnvironmentBuilder.buildInitial(hierarchy:)` with fresh IDs |
| `SectionModel.init(kind: .terminal, initialTab:)` synthesised by `SpaceModel.showTerminal` when `tabs.isEmpty` | literal `.terminal` | same |
| `SectionModel.createTab(workingDirectory:)` | `self.kind` | `EnvironmentBuilder.buildInitial(hierarchy:)` with fresh tab / pane IDs |
| `PaneViewModel.splitPane(direction:targetPaneID:)` | inherited from `self.sectionKind` | existing `buildEnvironmentVariables(forPaneID:)` — unchanged |
| `SessionRestorer.buildWorkspaceCollection` — per-leaf pane construction | `SectionState.kind` | `EnvironmentBuilder.buildInitial(hierarchy:)` for each restored pane |

If any of these sites forgets to route through `SectionSpawner`, Claude panes launch as blank shells — caught by `SectionSpawnerTests` and the FR-03 / FR-24 unit tests.

#### `ClaudeSpawnGate` — **DEFERRED** (see Section 14, Section 15.5)

FR-29's cold-launch Claude spawn rate limit is deferred to a follow-up spec. The proposed `viewDidMoveToWindow` signal is not a real "spawn settled" trigger (it fires before the PTY spawn completes), so the gate would degenerate into either an instant-release no-op or a pure 3-second timeout hack. Implementing a real signal (first OSC 7 or title-change event from the new surface) requires Ghostty-surface callback plumbing that is out of scope for v1. v1 ships without rate limiting; on cold restore all Claude panes spawn in parallel. If thundering-herd CPU/memory becomes a problem in practice, re-scope FR-29 with a real signal.

### Server Functions

Not applicable.

---

## 4. State Management

### Observed State

SwiftUI updates are driven by `@Observable` model classes. The new state additions live in:

| Storage | Location | Observed By |
|---------|----------|-------------|
| `SpaceModel.terminalVisible` | `SpaceModel` | `SpaceContentView` (to render divider + Terminal section), Claude toolbar button icon |
| `SpaceModel.dockPosition` | `SpaceModel` | `SpaceContentView` (chooses HStack vs VStack) |
| `SpaceModel.splitRatio` | `SpaceModel` | `SectionDividerView` |
| `SpaceModel.focusedSectionKind` | `SpaceModel` | `SectionToolbarView` (focus ring indicator, optional), key handler |
| `SectionModel.tabs`, `activeTabID` | `SectionModel` | `SectionTabBarView`, `SectionSplitContainerView` |
| `PaneViewModel.paneStates` | existing | unchanged (FR-29 deferred — no `.queued` state in v1) |

### Local State

- **Divider drag gesture** — `SectionDividerView` tracks the drag offset in `@GestureState` to allow live preview; commits to `SpaceModel.splitRatio` on release. Pixel minimums (320 for Claude, 160 for Terminal, per FR-16) clamp in real time.
- **Show/hide animation** — `SpaceContentView` uses a SwiftUI `.animation(.easeInOut(duration: 0.2), value: terminalVisible)` wrapping the conditional Terminal view; no extra state.
- **Drag-past-minimum auto-hide** — in the divider gesture handler: if the Terminal section would fall below 160pt and the user is still dragging toward hide, fire `hideTerminal()` on gesture end (not mid-drag — committing mid-drag would fight the user's finger).
- **Spawn queue display** — Deferred with FR-29. No `.queued` state is added in v1.

### Cache / Invalidation

tian has no explicit cache; SwiftUI re-renders on `@Observable` writes. No cache keys needed. Updates propagate in one render cycle (~16ms), matching existing performance.

---

## 5. Component Architecture

### Feature Directory Structure

All new types live next to their siblings in the existing directory layout. New files:

```
tian/
├── Tab/
│   ├── SectionModel.swift           — new: container owning [TabModel] + kind + activeTabID
│   ├── SectionKind.swift            — new: enum .claude / .terminal
│   ├── DockPosition.swift           — new: enum .right / .bottom
│   ├── SectionSpawner.swift         — new: helper injecting initialInput per kind
│   ├── SpaceModel.swift             — modified: add sections, terminalVisible, ratio, etc.
│   ├── TabModel.swift               — modified: add sectionKind (mirrors parent section)
│   └── SpaceCollection.swift        — modified: createSpace now seeds Claude + hidden Terminal
├── Pane/
│   ├── PaneViewModel.swift          — modified: carry sectionKind; splitPane wires initialInput
│   └── PaneState.swift              — unchanged in v1 (FR-29 deferred)
├── Persistence/
│   ├── SessionState.swift           — modified: SectionState struct; SpaceState reshape; v4 schema
│   ├── SessionSerializer.swift      — modified: bump currentVersion to 4; snapshot builds sections
│   ├── SessionRestorer.swift        — modified: build SectionModel; validation updated
│   └── SessionStateMigrator.swift   — modified: register v3→v4 migration function
├── Input/
│   ├── KeyAction.swift              — modified: add .toggleTerminalSection, .cycleSectionFocus
│   └── KeyBindingRegistry.swift     — modified: Ctrl+` and Cmd+Shift+` defaults
├── View/
│   ├── Space/
│   │   ├── SpaceContentView.swift          — modified root: renders sections + divider
│   │   ├── SectionView.swift               — new: tab bar + split container for one section
│   │   ├── SectionTabBarView.swift         — new: per-section tab bar (extracted)
│   │   ├── SectionDividerView.swift        — new: draggable divider between sections
│   │   ├── SectionToolbarView.swift        — new: Show/Hide + Move-to-right/bottom + Reset buttons
│   │   └── EmptyClaudePlaceholderView.swift — new: placeholder per FR-07
│   └── ... (existing TerminalSurfaceView, pane split container stay)
└── WindowManagement/
    └── WorkspaceWindowController.swift — modified: dispatch new key actions
```

### Screen Specifications

There is exactly one "screen" — the workspace window content. Inside it, layout changes. The spec below describes the view tree rooted at the Space level.

#### `SpaceContentView`

- **Inputs:** `SpaceModel`
- **Layout:**
  - Vertical stack: Claude toolbar (row of buttons: Show/Hide Terminal, sidebar toggle — existing) over the sections region.
  - Sections region branches on `dockPosition`:
    - `.right` → `HStack { SectionView(.claude, width: claudeWidth) ; SectionDividerView ; SectionView(.terminal, width: terminalWidth) }`
    - `.bottom` → `VStack { SectionView(.claude, height: claudeHeight) ; SectionDividerView ; SectionView(.terminal, height: terminalHeight) }`
  - When `terminalVisible == false`, the divider and Terminal section are omitted and Claude expands to fill (FR-17).
- **States:**
  - Default (Claude + Terminal visible)
  - Claude-only (Terminal hidden)
  - Empty Claude (Claude section has no tabs) — Claude section renders `EmptyClaudePlaceholderView` instead of tabs+splits (FR-07)
- **Design system:** Uses existing color tokens (`Color.terminalBackground`, etc.) and SF Symbols. No new tokens required in v1.

#### `SectionView`

- **Inputs:** `SectionModel`, `SectionKind`, overall available axis size
- **Layout (vertical stack):**
  1. `SectionTabBarView` — shows tabs with a leading section-kind glyph (Claude wordmark / `>_` for Terminal, per FR-26) and a trailing header-menu button for Terminal ("Move to bottom"/"Move to right", "Reset Terminal section")
  2. `SectionSplitContainerView` — the existing split-tree rendering, but scoped to the active tab's `PaneViewModel`
- **States:**
  - Empty tabs — only applies to the Claude section per FR-07 (Terminal section auto-hides before reaching zero tabs per FR-12). Render `EmptyClaudePlaceholderView`.
  - Loading pane — existing spinner overlay (no "Queued" extension in v1 since FR-29 is deferred)
  - Spawn-failed pane — existing error overlay; Claude panes additionally show a "Retry" button (FR-08)

#### `SectionDividerView`

- **Inputs:** binding to `SpaceModel.splitRatio`, dock position, computed pixel extents
- **Behavior:**
  - 6pt visual width (slightly thicker than the 4pt pane divider per FR-27)
  - Hit area 10pt for comfortable grab
  - Cursor: `NSCursor.resizeLeftRight` or `.resizeUpDown` depending on dock
  - Drag updates ratio live, clamped to `[claude ≥ 320pt, terminal ≥ 160pt]`
  - Drag that would cross the Terminal 160pt minimum calls `hideTerminal()` on gesture end (FR-16)

#### `EmptyClaudePlaceholderView`

- **Inputs:** `() -> Void` new-pane callback, `String` shortcut hint
- **Layout:** Centered VStack with:
  - Claude glyph
  - Label: "No Claude pane running"
  - Primary button: "New Claude pane" (SF Symbol `plus.circle.fill`)
  - Caption: "⌘T for new tab, ⌘D for split"
- **Behavior:** Button tap calls `SectionModel.createTab()`.

### Reusable Components

- **`SectionToolbarView`** — compact toolbar; same look for both sections, differentiated by icon. Claude toolbar hosts `Show/Hide Terminal`; Terminal toolbar hosts dock toggle + Reset menu.
- **`SectionKindGlyph`** — `View` that renders the per-kind icon. Reused in tab bars and the placeholder.

---

## 6. Navigation

### New "routes"

tian is single-window; there is no router. New "destinations" map to new key actions:

| Action | Default shortcut | Destination |
|--------|------------------|-------------|
| `.toggleTerminalSection` | `` Ctrl+` `` | Calls `activeSpace.toggleTerminal()`. If Terminal becomes visible and the section has zero tabs, spawn one shell pane (FR-10). Focus moves to the newly visible Terminal section's most-recently-focused pane, or the first pane after creation. |
| `.cycleSectionFocus` | `` Cmd+Shift+` `` | Calls `activeSpace.cycleFocusedSection()`. Moves focus to the most-recently-focused pane in the other section. No-op if target section has zero visible panes. |
| Existing `.newTab` (⌘T) | unchanged | Routed via `activeSpace.focusedSection.createTab(...)` (not `activeSpace.createTab` — that method no longer exists in v4). Creates tab in the focused pane's section. Matches FR-18. |
| Existing `.nextTab`/`.previousTab`/`.goToTab` | unchanged | Routed via `activeSpace.focusedSection.nextTab()` / `previousTab()` / `goToTab(index:)`. |
| Existing directional focus (⌘⌥Arrow, pane-level) | unchanged as shortcuts | Now dispatches through `SpaceLevelSplitNavigation` (Section 13.5 / FR-19) which treats both sections' layout frames as a flat set. |

**Cmd+W dispatch (close-pane / close-Space):** tian has no `.closeTab` `KeyAction` — closing is delegate-driven, not key-binding-dispatched. Two entry points exist in v4:

1. **Surface-level Cmd+W (normal panes):** `TerminalSurfaceView.performKeyEquivalent` intercepts Cmd+W and forwards via `TerminalSurfaceViewDelegate.terminalSurfaceViewRequestClose(_:)`, which the delegate resolves back to a `paneID` and calls `PaneViewModel.closePane(paneID:)`. The cascade then runs: `PaneViewModel.onEmpty` → `TabModel.onEmpty` → `SectionModel.removeTab` → (if last tab) `SectionModel.onEmpty` → either `SpaceModel.enterEmptyClaudeState()` (Claude side, FR-07) or `SpaceModel.hideTerminal()` (Terminal side, FR-12). Under no branch does this path reach `SpaceModel.requestSpaceClose()`.
2. **Placeholder-level Cmd+W (empty Claude):** When the Claude section is in empty state there is no `TerminalSurfaceView` to intercept the key event. `EmptyClaudePlaceholderView` installs `.keyboardShortcut(.cancelAction)` on its "Close" button, which calls `SpaceModel.requestSpaceClose()` directly.

**Key handler dispatch detail:** `WorkspaceWindowController.installKeyboardMonitor` today resolves `.newTab`/`.nextTab`/`.previousTab`/`.goToTab` and calls `activeSpace.createTab()` or similar space-level methods. In v4 these call sites change to the new `activeSpace.focusedSection.*` routing. The `focusedSection` computed property on `SpaceModel` looks at `focusedSectionKind` and returns `claudeSection` or `terminalSection`. Focus state is updated by the view layer when a pane receives first-responder status (existing `PaneFocusNotification` handler), which also calls `SpaceModel.focusedSectionKind = <kind>` and `SectionModel.lastFocusedPaneID = <id>`.

### Navigation Flow

- User starts focused on a Claude pane. ⌘T creates a new Claude tab.
- User presses `Ctrl+`` ` ``. Terminal section appears, focus moves to its first pane. ⌘T now creates a new Terminal tab.
- User presses `` Cmd+Shift+` ``. Focus returns to the last-focused Claude pane.
- ⌘⌥→ from the rightmost Claude pane (right-docked Terminal) moves focus into the Terminal section.

Tab drag-and-drop (FR-22): each section's tab bar owns its own `NSItemProvider` payload and rejects drags originating from the opposite section (enforced in `SectionTabBarView.onDrop`). The existing `com.tian.tab-drag-item` UTI is reused; the drag item gains an optional `sectionKind` field (or a new UTI `com.tian.claude-tab-drag-item` / `com.tian.terminal-tab-drag-item` — open question 15.2).

---

## 7. Type Definitions

### Summary Table

| Type | Purpose | Consumers |
|------|---------|-----------|
| `SectionKind` | Discriminator between Claude and Terminal sections | `SectionModel`, `PaneViewModel`, `TabModel`, views, migration |
| `DockPosition` | Right or bottom placement of the Terminal section | `SpaceModel`, `SpaceContentView`, `SectionDividerView` |
| `SectionModel` | Owns [TabModel] + kind + activeTabID; equivalent of the tab-bar-owning role previously played by SpaceModel | `SpaceModel`, tab bar views, split container view |
| `SectionState` | Codable persistence snapshot of a `SectionModel` | `SessionSerializer`, `SessionRestorer`, `SessionStateMigrator` |
| `SpaceState` (modified) | Now holds two sections + layout metadata, drops flat `tabs` list | persistence pipeline |
| `SectionSpawner` | Helper translating `SectionKind` + working directory + env vars → `TerminalSurfaceView` configuration | All pane-creation call sites |
| `SectionLayout` | Value-type helper computing the Claude / Terminal / divider frames for a given container size, ratio, and dock orientation | `SpaceContentView`, `SpaceLevelSplitNavigationTests` fixtures |
| `SectionDividerClamper` | Value-type helper enforcing FR-16 pixel minimums and auto-hide threshold | `SectionDividerView`, `DividerClampingTests` |
| `SectionTabBarDropCoordinator` | Static helper gating FR-22 cross-section drag-and-drop | `SectionTabBarView`, `TabDragConstraintTests` |
| `SectionDividerDragController` | Observable holding live drag state + queued dock toggles for FR-15 mid-drag behaviour | `SpaceModel`, `SectionDividerView`, `DockToggleDuringDragTests` |

### Type Code

```swift
// tian/Tab/SectionKind.swift
enum SectionKind: String, Sendable, Codable, Equatable, CaseIterable {
    case claude
    case terminal
}

// tian/Tab/DockPosition.swift
enum DockPosition: String, Sendable, Codable, Equatable {
    case right
    case bottom
}

// tian/Tab/SectionModel.swift
@MainActor @Observable
final class SectionModel: Identifiable {
    let id: UUID
    let kind: SectionKind
    private(set) var tabs: [TabModel]
    var activeTabID: UUID

    /// Most-recently-focused pane inside this section. Used by
    /// `SpaceModel.cycleFocusedSection()` (FR-20).
    var lastFocusedPaneID: UUID?

    /// Called when the last tab is removed. Owning SpaceModel decides
    /// whether to auto-hide (Terminal) or enter empty state (Claude).
    var onEmpty: (() -> Void)?

    /// Preconditions:
    ///   - `initialTab.sectionKind == kind` (debug-asserted; release logs
    ///     a mismatch and trusts `kind` as authoritative).
    init(kind: SectionKind, initialTab: TabModel)

    /// Same precondition applies to every element of `tabs`.
    init(id: UUID, kind: SectionKind, tabs: [TabModel], activeTabID: UUID)

    @discardableResult
    func createTab(workingDirectory: String) -> TabModel
    func removeTab(id: UUID)
    func activateTab(id: UUID)
    func nextTab()
    func previousTab()
    func goToTab(index: Int)
    func reorderTab(from: Int, to: Int)
    func closeOtherTabs(keepingID: UUID)
    func closeTabsToRight(ofID: UUID)
}

// tian/Tab/TabModel.swift (add one stored property to the class body)
@MainActor @Observable
final class TabModel: Identifiable {
    // ... existing id, name, paneViewModel, gitBranch, etc.
    /// Mirrors the owning SectionModel.kind. Set on construction, never
    /// changed — panes do not move sections (PRD NG5).
    let sectionKind: SectionKind
    // ... existing init(s) gain a `sectionKind: SectionKind` parameter.
}

// All TabModel initializer call sites must pass `sectionKind`:
//   - SessionRestorer.buildWorkspaceCollection  — from SectionState.kind
//   - SpaceCollection.createSpace / SpaceCollection.init  — literal .terminal or .claude
//   - SectionModel.createTab(workingDirectory:)  — from self.kind
//   - SectionModel.init(kind:initialTab:)  — from the kind argument
//   - Any test fixture that constructs a TabModel directly — explicit literal

// tian/Tab/SpaceModel.swift (added / changed members)
@MainActor @Observable
final class SpaceModel: Identifiable {
    // ... existing id, name, gitContext, etc.
    let claudeSection: SectionModel
    let terminalSection: SectionModel
    var terminalVisible: Bool
    var dockPosition: DockPosition
    var splitRatio: Double            // 0.1...0.9, default 0.7
    var focusedSectionKind: SectionKind

    /// Primary initializer used by SpaceCollection.createSpace and by
    /// SessionRestorer.buildWorkspaceCollection after migration.
    init(
        id: UUID = UUID(),
        name: String,
        claudeSection: SectionModel,
        terminalSection: SectionModel,
        terminalVisible: Bool = false,
        dockPosition: DockPosition = .right,
        splitRatio: Double = 0.7,
        focusedSectionKind: SectionKind = .claude,
        defaultWorkingDirectory: URL? = nil,
        worktreePath: String? = nil
    )

    /// Convenience initializer used only during Phase 1 development (compat
    /// shim). Constructs a Space with a freshly-synthesised Claude section
    /// holding one `claude` pane and an empty Terminal section. Removed at
    /// end of Phase 4 once SessionRestorer is fully v4-native.
    convenience init(name: String, workingDirectory: String)

    /// Convenience used by `KeyBindingRegistry` dispatch so FR-18 tab
    /// actions target the section of the focused pane.
    var focusedSection: SectionModel { /* returns claudeSection or terminalSection based on focusedSectionKind */ }

    func showTerminal()
    func hideTerminal()
    func toggleTerminal()
    func setDockPosition(_ position: DockPosition)
    func setSplitRatio(_ ratio: Double)
    func resetTerminalSection()
    func cycleFocusedSection()

    /// Called by EmptyClaudePlaceholderView Cmd+W handler and by sidebar
    /// / context-menu Close Space action. Invokes onSpaceClose.
    func requestSpaceClose()

    /// Wired by SpaceCollection.wireSpaceClose; invokes
    /// SpaceCollection.removeSpace(id: self.id). Replaces the v3 `onEmpty`
    /// closure, which no longer auto-fires from the cascade.
    var onSpaceClose: (() -> Void)?

    var isEffectivelyEmpty: Bool { /* claudeSection.tabs.isEmpty && terminalSection.tabs.isEmpty */ }

    /// Coordinates live divider-drag state and FR-15 mid-drag dock-toggle
    /// queueing. Owned here so SectionDividerView and toolbar buttons both
    /// route through the same controller.
    let sectionDividerDragController: SectionDividerDragController
}

// tian/Pane/PaneState.swift — unchanged in v1 (FR-29 deferred)

// tian/Tab/SectionSpawner.swift
enum SectionSpawner {
    /// Configures a fresh TerminalSurfaceView for the given section kind.
    /// - Claude: sets initialInput to "claude\n".
    /// - Terminal: leaves initialInput nil.
    /// In both cases, sets initialWorkingDirectory and environmentVariables
    /// from the caller so TIAN_* env propagation stays on the existing code path.
    ///
    /// **Precondition:** must be called before the view enters a window.
    /// Calling after `viewDidMoveToWindow` is a no-op for PTY state (initial-*
    /// fields are read once during `GhosttyTerminalSurface.createSurface`).
    /// Debug builds assert `view.window == nil`.
    static func configure(
        view: TerminalSurfaceView,
        kind: SectionKind,
        workingDirectory: String,
        environmentVariables: [String: String]
    )
}

// tian/View/Space/SectionLayout.swift
struct SectionLayout: Equatable {
    let claude: CGRect
    let terminal: CGRect
    let divider: CGRect

    /// Computes frames for both sections and the divider given a container
    /// size, split ratio, and dock orientation. Clamps ratio per the pixel
    /// minimums. Reused by SpaceContentView for geometry and by
    /// SpaceLevelSplitNavigationTests fixtures so tests track real constants.
    static func computeFrames(
        containerSize: CGSize,
        ratio: Double,
        dock: DockPosition,
        claudeMin: CGFloat,
        terminalMin: CGFloat,
        dividerThickness: CGFloat
    ) -> SectionLayout
}

// tian/View/Space/SectionDividerClamper.swift
struct SectionDividerClamper: Equatable {
    static let defaultClaudeMin: CGFloat = 320
    static let defaultTerminalMin: CGFloat = 160

    let containerAxis: CGFloat  // width for .right, height for .bottom
    let claudeMin: CGFloat
    let terminalMin: CGFloat

    /// Clamps a proposed ratio so Claude ≥ claudeMin. Returns the hard-stop
    /// value when the drag would make Claude smaller than the minimum.
    func clampRatio(proposed: Double, dock: DockPosition) -> Double

    /// On gesture end, returns the final ratio plus whether auto-hide should
    /// fire (proposed ratio put Terminal below terminalMin).
    func evaluateDragEnd(proposedRatio: Double, dock: DockPosition)
        -> (clamped: Double, shouldHide: Bool)
}

// tian/View/Space/SectionDividerDragController.swift
@MainActor @Observable
final class SectionDividerDragController {
    private(set) var isDragging: Bool = false
    private(set) var queuedDockPosition: DockPosition?

    func beginDrag()
    func endDrag(finalRatio: Double)

    /// Internal helper used by `SpaceModel.setDockPosition` when a drag is
    /// in progress. The public entry point is `SpaceModel.setDockPosition`,
    /// which consults `isDragging` and routes here when appropriate.
    /// FR-15 behavior.
    func enqueueDockPosition(_ position: DockPosition)
}

// tian/View/Space/SectionTabBarDropCoordinator.swift
enum SectionTabBarDropCoordinator {
    /// Returns false when a tab drag crosses section boundaries (FR-22).
    static func canAccept(
        sourceSectionKind: SectionKind,
        destinationSectionKind: SectionKind,
        tabID: UUID
    ) -> Bool
}

// tian/View/Space/SectionDividerView.swift (constant declared alongside the view)
extension SectionDividerView {
    /// Visual thickness of the section divider (FR-27 — thicker than
    /// SplitLayout.dividerThickness which is 4pt).
    static let thickness: CGFloat = 6
}

// tian/Persistence/SessionState.swift — v4 additions
struct SectionState: Codable, Sendable, Equatable {
    let id: UUID
    let kind: SectionKind            // "claude" | "terminal"
    let activeTabId: UUID?           // nil iff tabs.isEmpty
    let tabs: [TabState]
}

/// v4 SpaceState. Replaces v3 SpaceState (legacy `tabs`/`activeTabId` removed).
struct SpaceState: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let defaultWorkingDirectory: String?
    let worktreePath: String?
    let claudeSection: SectionState
    let terminalSection: SectionState
    let terminalVisible: Bool
    let dockPosition: DockPosition   // "right" | "bottom"
    let splitRatio: Double           // clamped 0.1...0.9
    let focusedSectionKind: SectionKind
}

// TabState adds required `sectionKind` in v4. Non-optional removes the
// "infer on decode" branch; migration sets it explicitly on every tab,
// and freshly-created tabs set it from their owning section.
struct TabState: Codable, Sendable, Equatable {
    let id: UUID
    let name: String?
    let activePaneId: UUID
    let root: PaneNodeState
    let sectionKind: SectionKind     // required in v4
}

// tian/Input/KeyAction.swift (added cases)
extension KeyAction {
    /* case .toggleTerminalSection */
    /* case .cycleSectionFocus      */
}
```

---

## 8. Analytics Implementation

Per PRD Section 8 there are **no external analytics** in v1. The signals listed in the PRD are internal debug-log emissions using the existing `Log.<category>` APIs (`os.Logger` + file-logged categories).

| Signal | Log category | Trigger point |
|--------|-------------|---------------|
| Claude pane spawn latency | `Log.perf` | End of `GhosttyTerminalSurface.createSurface` when pane is Claude-kind (wrap the existing `recordSurfaceCreation` call and tag with `kind=claude`). Also serves as the data source for the deferred FR-29 decision |
| Claude pane unexpected exit count | `Log.lifecycle` | `PaneViewModel` notification handler for `surfaceExitedNotification` when `sectionKind == .claude` |
| Claude launch-failure count | `Log.lifecycle` | `surfaceSpawnFailedNotification` handler when `sectionKind == .claude`, plus on "Retry" clicks |
| Terminal section show/hide events | `Log.lifecycle` | `SpaceModel.showTerminal` / `hideTerminal` |
| Divider drag start/end ratios | `Log.perf` | `SectionDividerView` gesture start/end |
| Auto-hide-via-drag-past-minimum | `Log.lifecycle` | `SectionDividerView` commit path when threshold tripped |
| Empty-Claude dwell time | `Log.lifecycle` | On entering empty state (record timestamp); on leaving (diff + log) |
| Migration success/failure | `Log.persistence` (already file-logged) | `SessionStateMigrator` v3→v4 migration path; also on fresh-launch fallback |

No new logging subsystems are introduced.

---

## 9. Permissions & Security

### Access Policies

tian has no user-facing auth. The persisted state file continues to be chmod `0600` (set by `SessionSerializer.save`). No changes.

### Client-Side Guards

- **Claude binary absence** (FR-08): `PaneViewModel.closePane` is NOT invoked on spawn failure. Instead, `PaneState.spawnFailed` is set, the pane stays open with a "Retry" button. This already happens via `surfaceSpawnFailedNotification` — no change needed beyond the UI overlay adding a Retry button for Claude-kind panes.
- **Claude exit cascade** (FR-07): Modified logic — see Section 11 (Migration & Deployment) and the "Cascading-close rules" subsection below.
- **Cross-section pane move** (NG5): `SectionModel.createTab` is the only creation surface that accepts a `SectionKind`; the pane view model inherits the kind of its owning section. `PaneViewModel.splitPane` inherits the source pane's kind (which equals the tab's kind) and cannot be asked to produce a different-kind pane.

### Cascading-close rules (updated)

**Key invariant:** `SpaceModel.onSpaceClose` **never** fires automatically from Claude or Terminal section emptiness alone. The empty-Claude placeholder (FR-07) is always reachable. (`SpaceModel` has no `onEmpty` closure in v4 — that name is reserved for `SectionModel` / `TabModel` at the inner cascade levels.) A Space closes only on an explicit user gesture (`Cmd+W` from the empty Claude placeholder, or `Cmd+W` from the Space context menu / sidebar), or — symmetrically — when the *user* closes the last Terminal pane while Claude is already in the empty state (via Cmd+W from that Terminal pane).

| Event | v3 behaviour | v4 behaviour |
|-------|--------------|--------------|
| Last pane in a tab closes | `TabModel.onEmpty` → `SpaceModel.removeTab` | Unchanged at pane/tab level: `TabModel.onEmpty` → `SectionModel.removeTab` |
| Last tab in Claude section closes | Would cascade to Space close | `SectionModel.onEmpty` (Claude) → `SpaceModel.enterEmptyClaudeState()`. Claude section renders `EmptyClaudePlaceholderView`. **Space stays open regardless of Terminal state.** (FR-07) |
| Last tab in Terminal section closes | n/a | `SectionModel.onEmpty` (Terminal) → `SpaceModel.hideTerminal()` (auto-hide). **Space stays open regardless of Claude state.** (FR-12) |
| User invokes Cmd+W on empty Claude placeholder | n/a | `SpaceModel.requestSpaceClose()` → if Terminal section has any live foreground processes (parent PRD FR-22), present a confirmation dialog listing them and proceed only on user confirm; otherwise proceed unconditionally to `SpaceCollection.removeSpace(id: self.id)`. This is the **primary** Space-close path from the Claude side (FR-07 clause a) — shells are SIGHUPped as part of normal Space teardown |
| User invokes Cmd+W on the last Terminal pane **while Claude is in empty state** | n/a | Standard pane close runs; when Terminal auto-hides, the Space is now empty on both sides; `SpaceModel.requestSpaceClose()` is still NOT invoked automatically. The user remains in the empty-Claude placeholder and must Cmd+W again to close the Space. This keeps the "user is always in control" rule uniform |
| User closes the Space via sidebar / context menu | `SpaceCollection.removeSpace(id:)` | Unchanged |

Rationale for the "two Cmd+W" rule when both sections go empty: it keeps the Space-close contract single-sourced (a Space closes only when the user explicitly asks via Cmd+W on the currently-focused surface), and avoids any path where the Space vanishes while the user is still looking at content — matching PRD User Story 11 ("close my last Claude pane without losing my running shell jobs"). An implementation variant that auto-closes the Space when *both* sections are empty is explicitly rejected as surprising.

**`SpaceModel.isEffectivelyEmpty` computed property:**

```text
isEffectivelyEmpty ≡ claudeSection.tabs.isEmpty && terminalSection.tabs.isEmpty
```

Used by diagnostics and by the sidebar (dim the Space's row visually when `isEffectivelyEmpty`) — but **not** as an auto-close trigger.

**`SpaceModel.requestSpaceClose()` method:**

Single entry point for "user is asking to close this Space". Called by:

- `EmptyClaudePlaceholderView.onCmdW` (intercepted at the view layer; see Section 5).
- Existing sidebar / context-menu close action (already calls `SpaceCollection.removeSpace`; refactored to go through this method for uniform lifecycle logging).

Signature: `func requestSpaceClose(confirm: (( [ForegroundProcessSummary]) async -> Bool)? = nil) async`.

Implementation flow:

1. Enumerate running foreground processes in both sections (reuse the existing `PaneViewModel.foregroundProcesses` helper from the parent PRD FR-22 quit-time flow — it already walks panes and returns PID/name summaries).
2. If non-empty and `confirm != nil`, await `confirm(summaries)`. If the user cancels, return without closing.
3. If empty or the user confirms, fire `onSpaceClose?()` (an owner-injected closure provided by `SpaceCollection.wireSpaceClose`), which today already invokes `removeSpace(id: self.id)` — shells are SIGHUPped by the existing teardown path.

Callers that can present UI pass a `confirm` closure that wraps `NSAlert`; callers in test contexts pass `nil` or a deterministic stub. `SpaceCloseConfirmationCoordinator` in `WindowManagement/` owns the default `NSAlert`-based implementation and injects it into `SpaceModel.requestSpaceClose`. The wiring is set up in `WorkspaceWindowController` at Space attach time.

**Cmd+W dispatch when the empty-Claude placeholder is on screen:** When Claude's active tab contains zero panes, there is no `TerminalSurfaceView.performKeyEquivalent` to intercept Cmd+W. `EmptyClaudePlaceholderView` installs its own key-equivalent handler (via `NSViewRepresentable` or a SwiftUI `.keyboardShortcut(.cancelAction)` binding on the placeholder's Close button). When Claude section has ≥1 tab but a tab's pane is empty-state (not applicable in v1 — Claude tabs always have panes on creation), the existing surface-level Cmd+W handler runs. See resolved open question 15.6.

---

## 10. Performance Considerations

- **SwiftUI re-renders.** Splitting `SpaceModel` into two sections means the existing single `@Observable` model now has more observed properties. The Claude and Terminal `SectionView` each read only from their own `SectionModel`, not from `SpaceModel` directly. `SpaceContentView` is the only view that observes `dockPosition` and `terminalVisible`.
- **Divider drag path.** `SpaceContentView.body` does **not** read `SpaceModel.splitRatio` directly during drag. The live drag offset is held in `SectionDividerView`'s `@GestureState` (local to the divider view) and propagated to the two `SectionView`s via a `PreferenceKey` + `.frame(width:height:)` modifier on each child. This confines per-frame invalidation to the divider itself plus a geometry-only update on the two section containers — the terminal surfaces' bodies do not re-run. On gesture end, the divider commits the final ratio to `SpaceModel.splitRatio` once. Target: 60fps drag, no Metal surface re-layout per frame.
- **Animation during drag.** `SwiftUI.Animation` is disabled while the drag gesture is active (`.animation(nil, value: splitRatio)`) to prevent animation lag and double-interpolation between the gesture-state offset and the committed ratio.
- **Cold-launch Claude spawn.** Deferred to a follow-up spec (see Section 15.5). v1 spawns all restored Claude panes in parallel. Typical sessions restore 1–3 Claude panes, so thundering-herd is not expected to be a v1 concern. If it becomes one, FR-29 can be revisited with a real spawn-settled signal hooked into Ghostty-surface callbacks.
- **Persistence size.** Each Space now serialises ~2x the structure. Measured impact on restore time: negligible (single-digit ms at current scales).
- **Spawn latency budget.** PRD success metric: first usable shell prompt within 200ms after "Show Terminal". Achieved by reusing the existing view-is-in-window-now path (no extra sleeps, no modal loading).

---

## 11. Migration & Deployment

### Schema migration (FR-25)

Bump `SessionSerializer.currentVersion` from 3 → 4. Register a new non-identity closure in `SessionStateMigrator.migrations[3]`. A non-identity entry is **required**: the migrator loop `for v in version..<currentVersion { guard let migration = migrations[v] else { continue } ... }` would otherwise silently skip v3 data, then attempt to decode as v4 — which would fail because `SpaceState.claudeSection` is non-optional. A test in `SessionMigrationV3ToV4Tests` asserts `SessionStateMigrator.migrations[3] != nil` to guard this.

```text
Input:  v3 { version: 3, ..., workspaces: [{ ..., spaces: [{ id, name, activeTabId, ..., tabs: [TabState] }] }] }
Output: v4 { version: 4, ..., workspaces: [{ ..., spaces: [{ id, name, ..., claudeSection, terminalSection, terminalVisible, dockPosition, splitRatio, focusedSectionKind }] }] }
```

**Top-level / workspace-level fields preserved verbatim:**

- `SessionState.version` (rewritten to `4`), `savedAt`, `activeWorkspaceId`.
- `WorkspaceState.id`, `name`, `activeSpaceId`, `defaultWorkingDirectory`, `windowFrame`, `isFullscreen`, `spaces[]` (descent only; each `SpaceState` inside is rewritten).

**Field-by-field rewire for each Space:**

| v3 field | Destination in v4 |
|----------|-------------------|
| `SpaceState.id, name, defaultWorkingDirectory, worktreePath` | Unchanged, copied verbatim |
| `SpaceState.tabs` (legacy, all shell) | `SpaceState.terminalSection.tabs` (preserves order). Each `TabState` gains `sectionKind: "terminal"`. **`PaneLeafState.claudeSessionState` is preserved verbatim** — the rewire moves `TabState` subtrees wholesale, so per-pane session metadata survives into the Terminal section for the `claude-session-status` feature |
| `SpaceState.activeTabId` | `SpaceState.terminalSection.activeTabId` (nullable when legacy `tabs` was empty, which today is impossible but tolerated) |
| (none — synthesised) | `SpaceState.claudeSection = { id: <newSectionID>, kind: "claude", activeTabId: <newTabID>, tabs: [<one fresh TabState>] }`. The fresh tab has: `id = <newTabID>`, `name = null`, `sectionKind: "claude"`, `activePaneId = <newPaneID>`, `root = .pane({ paneID: <newPaneID>, workingDirectory: spaceDefault ?? $HOME, restoreCommand: null, claudeSessionState: null })`. All three UUIDs are freshly generated; `activePaneId` MUST equal the leaf's `paneID` to avoid `stalePaneIdFix` log noise in `SessionRestorer.validate` |
| (none — synthesised) | `SpaceState.terminalVisible = false` |
| (none — synthesised) | `SpaceState.dockPosition = "right"` |
| (none — synthesised) | `SpaceState.splitRatio = 0.7` |
| (none — synthesised) | `SpaceState.focusedSectionKind = "claude"` |

The migration operates on the raw `[String: Any]` JSON dictionary per the existing migrator contract. Pseudocode lives entirely inside `SessionStateMigrator.migrations[3]`; no typed models are touched.

**Migrator pseudocode.** Matches the existing `typealias Migration = @Sendable ([String: Any]) throws -> [String: Any]` contract (see `tian/Persistence/SessionStateMigrator.swift:9`). Registry entries in v1/v2 today already follow the "take a dict, return a dict" pattern (`migrations[1]`/`migrations[2]` are the identity); this entry returns a transformed copy.

```text
migrations[3] = { json throws -> [String: Any] in
    var dict = json
    dict["version"] = 4

    guard var workspaces = dict["workspaces"] as? [[String: Any]] else {
        return dict
    }
    for (wi, workspace) in workspaces.enumerated() {
        guard var spaces = workspace["spaces"] as? [[String: Any]] else { continue }
        for (si, oldSpace) in spaces.enumerated() {
            var newSpace = oldSpace

            // 1. Migrate legacy tabs into the Terminal section (preserving
            //    pane subtrees verbatim — including PaneLeafState.claudeSessionState).
            let legacyTabs = (oldSpace["tabs"] as? [[String: Any]]) ?? []
            let taggedTabs: [[String: Any]] = legacyTabs.map { tab in
                var t = tab
                t["sectionKind"] = "terminal"
                return t
            }
            let legacyActive = oldSpace["activeTabId"] as? String
            newSpace["terminalSection"] = [
                "id": UUID().uuidString,
                "kind": "terminal",
                "activeTabId": taggedTabs.isEmpty
                    ? NSNull()
                    : (legacyActive ?? (taggedTabs[0]["id"] as? String ?? "")) as Any,
                "tabs": taggedTabs,
            ] as [String: Any]

            // 2. Synthesise a fresh Claude section with one tab and one pane.
            //    `activePaneId` MUST equal the leaf's `paneID` to avoid
            //    SessionRestorer.validate's stalePaneIdFix log spam.
            let paneID = UUID().uuidString
            let tabID = UUID().uuidString
            let wd = (oldSpace["defaultWorkingDirectory"] as? String)
                 ?? ProcessInfo.processInfo.environment["HOME"] ?? "/"
            let leaf: [String: Any] = [
                "type": "pane",
                "paneID": paneID,
                "workingDirectory": wd,
                "restoreCommand": NSNull(),
                "claudeSessionState": NSNull(),
            ]
            let freshTab: [String: Any] = [
                "id": tabID,
                "name": NSNull(),
                "activePaneId": paneID,
                "root": leaf,
                "sectionKind": "claude",
            ]
            newSpace["claudeSection"] = [
                "id": UUID().uuidString,
                "kind": "claude",
                "activeTabId": tabID,
                "tabs": [freshTab],
            ] as [String: Any]

            // 3. Layout defaults.
            newSpace["terminalVisible"] = false
            newSpace["dockPosition"] = "right"
            newSpace["splitRatio"] = 0.7
            newSpace["focusedSectionKind"] = "claude"

            // 4. Remove legacy keys.
            newSpace.removeValue(forKey: "tabs")
            newSpace.removeValue(forKey: "activeTabId")

            spaces[si] = newSpace
        }
        workspaces[wi]["spaces"] = spaces
    }
    dict["workspaces"] = workspaces
    return dict
}
```

**`SessionRestorer.validate` update (v4):**

Today the validator asserts `!space.tabs.isEmpty` (line ~100). In v4 this becomes:

- Assert `!space.claudeSection.tabs.isEmpty` — fail decode with `RestoreError.emptyTabs(spaceName: space.name, kind: .claude)` if violated.
- Tolerate `space.terminalSection.tabs.isEmpty` — in that case, also require `space.terminalSection.activeTabId == nil`; log (but do not fail) if inconsistent.
- `paneExists(tab.activePaneId, in: tab.root)` runs per tab in both sections, same logic as v3.

**Failure handling (FR-25):**

1. If `JSONSerialization.jsonObject` fails on the raw data → existing fallback to `state.prev.json` (via `SessionRestorer.loadFrom` chain).
2. If migration throws → `SessionStateMigrator.MigrationError.migrationFailed` bubbles up; `SessionRestorer.loadState` logs and returns `nil`.
3. If `nil` is returned → `SessionRestorer.buildWorkspaceCollection` is skipped; `TianAppDelegate` creates a fresh default `WorkspaceCollection` (one workspace, one space, one Claude tab, one Claude pane, no Terminal section).
4. On fresh-launch fallback, post a one-time notice with the full path to the legacy file at `~/Library/Application Support/tian/state.json` so the user can inspect it (user surface: an alert sheet on first launch, dismissible).

The legacy file is **not deleted**. After successful migration the migrator writes the new state to `state.json` atomically (reusing existing `SessionSerializer.save`); the file rotation creates a backup at `state.prev.json` containing the migrated v4 payload. Legacy v3 data is not preserved beyond the first successful save — `state.prev.json` is a recent-save backup, **not** a v3 escape hatch. Users who want to downgrade past the first quit cycle must restore `state.json` from a Time Machine (or equivalent) backup.

### Feature flag

The feature is shipped unconditionally. Since tian is a personal tool with no external users, no rollout gate is warranted.

**The v3→v4 migration is one-way and permanent.** `SessionSerializer.save` rotates `state.json` into `state.prev.json` on every save, so after one quit+relaunch cycle both files contain v4 data. A v3 binary running against a v4-upgraded home directory will hit `MigrationError.futureVersion` and fall back to a fresh session — which is the documented and expected behaviour. There is no rollback path beyond manual restore of `state.json` from a Time Machine backup.

### Deployment order

1. Ship v4 code with the migrator registered. First launch performs migration; disk is rewritten as v4.
2. Subsequent launches read v4 directly.
3. If a developer checks out an older commit locally, they will hit `MigrationError.futureVersion` and the fresh-launch fallback kicks in (as designed).

---

## 12. Implementation Phases

Each phase ships a working, testable increment. **Phase 1 must keep existing v3 state loadable** so the developer can exercise partial builds against real local state. The v4 in-memory model is introduced alongside a temporary compat shim in `SessionRestorer`; true v3→v4 migration lands in Phase 4.

**User-exposure rule.** Because tian has no feature flag and each phase merges to `main`, Claude-tab data loss between Phase 1 and Phase 4 is unacceptable (the developer who merges Phase 1 IS the only user). Two options, pick one at merge time:

- **Option A (preferred):** squash-merge Phases 1–4 as a single PR so the disk format only flips once. Phases 5 and 6 (polish, instrumentation, placeholders, retry) merge separately because they don't touch persistence.
- **Option B:** keep phases as separate PRs but gate Phase 1/2/3 snapshot emission with an `#if DEBUG_SECTIONS` build flag that short-circuits `SessionSerializer.save` to a no-op when set. Local debug builds set the flag; release builds don't. Phase 4 removes the flag.

The Phase 1 bullets below describe behaviour under Option A; under Option B adjust the snapshot description to "no-op under DEBUG_SECTIONS".

### Phase 1 — Model layer + fresh-session UX + SessionRestorer compat shim

- Introduce `SectionKind`, `DockPosition`, `SectionModel`, `SectionSpawner`.
- Modify `SpaceModel` to own two `SectionModel`s, `terminalVisible=false` by default, `dockPosition=.right`, `splitRatio=0.7`. Add new primary initializer (Section 7).
- Modify `SpaceCollection.createSpace` / `SpaceCollection.init` to seed a Claude section with one Claude tab.
- Modify `PaneViewModel` to carry `sectionKind`; route every pane-creation call site through `SectionSpawner.configure(...)` so Claude panes get `initialInput = "claude\n"`.
- Wire cascading-close per Section 9 (`SpaceModel.onSpaceClose`, `requestSpaceClose`, `isEffectivelyEmpty`). **Delete `SpaceModel.onEmpty`** in the same commit and rewrite `SpaceCollection.wireSpaceClose` to inject `onSpaceClose = { [weak self] in self?.removeSpace(id: space.id) }` — otherwise both the old and new paths stay wired and a Space close fires twice.
- **Add temporary compat shim in `SessionRestorer.buildWorkspaceCollection`**: when it encounters v3-shaped raw data (no `claudeSection` key), it synthesises a fresh Claude section in memory and routes the legacy `tabs` into a Terminal section. The on-disk file stays v3.
- **Add temporary compat path in `SessionSerializer.snapshot`**: since `SpaceModel.tabs` no longer exists, snapshot derives the v3 `SpaceState.tabs` field from `space.terminalSection.tabs` and `SpaceState.activeTabId` from `space.terminalSection.activeTabID ?? <first tab id>`. **Claude-section state is intentionally NOT persisted during Phase 1** — it is re-synthesised fresh on every launch via the read shim. This is acceptable because Phase 1 is pre-feature-flag-exposure developer testing; users never see it. Phase 2 also accepts this limitation.
- **Data-loss warning:** Any Claude-tab layout the developer builds during Phase 1/2 testing is discarded on quit. Phase 4 removes both shims atomically: `currentVersion` bumps to 4, the real migrator runs, snapshot emits v4, and restore reads v4 natively. The shims live for at most two merged phases.
- Ship: **new Spaces open with one Claude pane; Terminal section is hidden; existing users' state still loads via the compat shim; disk format stays v3 until Phase 4.** No UI for toggling yet; developer can verify the model layer.

### Phase 2 — SwiftUI views for sections

- Build `SpaceContentView` with the HStack/VStack branch on `dockPosition`.
- Build `SectionView`, `SectionTabBarView`, `SectionDividerView`, `SectionToolbarView`, `EmptyClaudePlaceholderView`.
- Wire the Show/Hide button and Move-to-bottom/right toggle. Wire the divider drag gesture with pixel minimums (FR-16). Wire auto-hide on drag-past-minimum.
- Ship: **user can visually toggle Terminal, drag the divider, switch dock position.** `Ctrl+`` ` `` not yet bound.

### Phase 3 — Key bindings + directional navigation + section-focus cycling

- Add `.toggleTerminalSection` and `.cycleSectionFocus` to `KeyAction` and `KeyBindingRegistry`.
- Dispatch both in `WorkspaceWindowController.installKeyboardMonitor`.
- Implement `SpaceLevelSplitNavigation` (new helper in `tian/Pane/`) which collects `paneFrames` from both sections and delegates to `SplitNavigation.neighbor(...)`. Wire from the existing `TerminalSurfaceViewDelegate.terminalSurfaceViewRequestFocusDirection` handler: first try within-tab navigation; if no match, ask `SpaceLevelSplitNavigation` to search across sections.
- Ship: **full keyboard parity; directional focus crosses the section divider per FR-19.**

### Phase 4 — Persistence + migration (removes Phase 1 compat shim)

- Add `SectionState` to `tian/Persistence/SessionState.swift`; reshape `SpaceState`.
- Update `SessionSerializer.snapshot` to emit the v4 shape.
- Update `SessionRestorer.buildWorkspaceCollection` to construct `SectionModel`s from the v4 payload natively; **remove the Phase 1 compat shim** — the migrator now produces v4 input before restore runs.
- Update `SessionRestorer.validate` with asymmetric Claude / Terminal empty-tabs handling (Section 11).
- Bump `SessionSerializer.currentVersion` to 4.
- Register v3→v4 migration in `SessionStateMigrator.migrations[3]` with the pseudocode in Section 11. Verify `claudeSessionState` round-trips.
- On migration failure, emit the one-time notice alert (new `MigrationNoticeController` or reuse `NotificationCenter`).
- Ship: **existing users upgrade cleanly; quit/relaunch preserves section state; no shim remains.**

### Phase 5 — Placeholders + retry

- Add the Retry button + action to Claude-kind spawn-failed overlays (FR-08).
- Add the empty Claude placeholder action path and "Reset Terminal section" menu item (FR-07/FR-13).
- Wire `EmptyClaudePlaceholderView.onCmdW` → `SpaceModel.requestSpaceClose()` (FR-07 clause a).
- Ship: **FR-07 placeholder + explicit close, FR-08 Retry, FR-13 Reset complete.** (FR-29 deferred to follow-up; see Section 15.5.)

### Phase 6 — Polish & instrumentation

- Add all debug-log instrumentation per Section 8.
- Visual polish pass per open question 10.1 (design concept link).
- Tab drag-and-drop constraint: prevent cross-section drops (FR-22).
- Ship: **feature complete.**

---

## 13. Test Strategy

### Mapping to PRD Success Criteria

| PRD Success Metric | Target | Verification Method | Phase |
|--------------------|--------|---------------------|-------|
| Default-state usefulness | 100% of new Spaces usable for Claude work without user setup | Unit: `SpaceCollection.createSpace` yields a Space with exactly one Claude tab + one Claude pane and `terminalVisible=false`; integration smoke test confirms `claude` is the initial input on the new pane. | Phase 1 |
| Claude exit cleanliness | 0 dead Claude panes after `/exit` across 20 sessions | Unit: `PaneViewModel` exit-notification handler closes the pane on any exit code when `sectionKind == .claude`; manual QA. | Phase 1, Phase 6 |
| Cascade safety | 0 incidents of running Terminal shells killed by a Claude `/exit` | Unit: closing the last Claude tab with a non-empty Terminal section leaves Terminal tabs untouched and keeps the Space alive (FR-07). | Phase 1 |
| Section divider drag | No janky frames at 60fps | Manual QA with Instruments' Core Animation FPS gauge; Phase 2. | Phase 2 |
| Section toggle latency | First usable shell prompt within 200ms | Manual timing test; `Log.perf` spawn-latency signal. | Phase 2, Phase 6 |
| Migration | First launch after upgrade produces a usable Space with all prior tabs preserved | Unit: `SessionStateMigrator.migrations[3]` on a synthetic v3 fixture; integration: restore-round-trip through `SessionRestorer`. | Phase 4 |
| Daily driver | Developer no longer manually splits panes or types `claude` | Self-reported qualitative; no automated test. | Phase 6 |

### Mapping to Functional Requirements

| FR ID | Test Description | Type | Preconditions |
|-------|-----------------|------|---------------|
| FR-01 | New Space has exactly one Claude section; Claude section cannot be removed via API | Unit | Fresh `SpaceCollection` |
| FR-02 | New Space starts with Terminal section hidden | Unit | Fresh `SpaceCollection` |
| FR-03 | Initial Claude pane has `initialInput = "claude\n"` and working directory equals Space default | Unit | Fresh Space with workingDirectory argument |
| FR-04 | Tab/split/focus operations on Claude section do not mutate Terminal section (and vice versa) | Unit | Space with both sections populated |
| FR-05 | Splitting a Claude pane produces a pane with `sectionKind == .claude` and `initialInput == "claude\n"` | Unit | Claude pane focused |
| FR-06 | Claude pane exit (any exit code) closes the pane without exit-code overlay | Unit | Claude pane; simulate `surfaceExitedNotification` with exit code 1 |
| FR-07 | Closing last Claude pane with non-empty Terminal: Space stays alive, Claude section enters empty state, Terminal untouched | Unit | Space with 1 Claude tab/pane + 1 Terminal tab/pane |
| FR-07b | Closing last Claude pane with empty Terminal: Space stays alive in "both empty" state; `requestSpaceClose` NOT called automatically | Unit | Space with 1 Claude tab/pane and no Terminal panes |
| FR-07c | Explicit Cmd+W on empty Claude placeholder calls `requestSpaceClose()` and removes the Space from its collection | Unit | Space with Claude in empty state |
| FR-08b | Clicking Retry on a spawn-failed Claude pane re-creates the surface and re-attempts spawn; on second failure pane remains in `spawnFailed` state | Unit | Claude pane whose first spawn failed |
| FR-08 | Claude launch failure leaves pane open with `spawnFailed` state; no cascade | Unit | Simulate `surfaceSpawnFailedNotification` on a Claude pane |
| FR-09 | `Ctrl+`` ` `` dispatches `.toggleTerminalSection` | Unit | Event mock in `KeyBindingRegistry` |
| FR-10 | First `showTerminal()` creates one tab with one shell pane in Space's resolved wd | Unit | Space with hidden empty Terminal section |
| FR-11 | New Terminal pane has no `initialInput` (shell only) | Unit | Existing Terminal section |
| FR-12 | Closing last Terminal pane auto-hides the Terminal section (does not close Space) | Unit | Space with populated Terminal, non-empty Claude |
| FR-13 | `hideTerminal()` preserves tabs, panes, working directories; re-`showTerminal()` restores exactly; "Reset Terminal section" closes all Terminal panes | Unit | Space with populated Terminal |
| FR-14 | `dockPosition` defaults to `.right`; toggling to `.bottom` does not close panes | Unit | Space with populated Terminal |
| FR-15 | `setDockPosition` persists after quit/relaunch | Integration | Round-trip through `SessionSerializer.save` → `SessionRestorer.loadState` |
| FR-16 | Divider drag clamped to Claude ≥ 320pt and Terminal ≥ 160pt; drag past Terminal minimum triggers `hideTerminal()` | Unit (view logic) | Mock container size 800pt |
| FR-17 | Hidden Terminal → Claude occupies 100% of content area | View snapshot | |
| FR-18 | Tab/split/close shortcuts act on focused pane's section | Unit | Two-section Space, focus in Terminal |
| FR-19 | `SpaceLevelSplitNavigation` finds target pane across sections using flat `paneFrames` dict | Unit | Mock frames for Claude pane + Terminal pane adjacent |
| FR-20 | `cycleFocusedSection()` alternates between most-recently-focused pane in each section; no-op when target empty | Unit | Space with focus history |
| FR-21 | `splitPane` on a Claude pane produces a Claude pane; on Terminal produces Terminal | Unit | Both sections populated |
| FR-22 | Tab drag rejected when source and destination sections differ | Unit | Mock drop coordinator |
| FR-23 | Serialisation round-trip preserves section visibility, dock, ratio, tabs, panes, working directories | Integration | Space with populated Terminal, hidden |
| FR-24 | On restore, each Claude pane has `initialInput = "claude\n"`; Terminal panes don't | Integration | v4 fixture through `SessionRestorer.buildWorkspaceCollection` |
| FR-25 | v3 fixture migrates to v4 with legacy tabs in terminalSection, fresh claudeSection synthesised | Unit | Synthetic v3 JSON dictionary |
| FR-25b | Malformed v3 JSON triggers fresh-launch fallback and emits migration-failure log | Unit | Corrupted JSON fixture |
| FR-26 | Tab bar view renders kind-specific glyph | View snapshot | Claude + Terminal section |
| FR-27 | Section divider visually distinct (different thickness) from pane divider | Constant check (`SectionDividerView.thickness == 6`, `SplitLayout.dividerThickness == 4`) | — |
| FR-28 | Show/Hide Terminal toolbar button swaps icon based on `terminalVisible` | View snapshot | — |
| FR-29 | **Deferred to follow-up spec** — no v1 test. See Section 15.5. | — | — |

### Non-Goals Verification

| NG | Verification |
|----|--------------|
| NG1 | Repeated launches do not re-read legacy `tabs` field (after first migration, v4 file is on disk; test asserts file no longer has a top-level `tabs` at Space level). |
| NG2 | Codebase has no `SectionKind.notes` / `SectionKind.logs` cases — enum exhaustiveness enforced by compile. |
| NG3 | Claude spawn wraps `claude` binary on PATH; no config lookup. Assert by grep that `"claude\n"` literal appears exactly once in code (`SectionSpawner`). |
| NG4 | `DockPosition` has exactly `.right` and `.bottom` — compile-enforced. |
| NG5 | No `PaneViewModel.move(toSection:)` API. Code review; no test possible for an absent API. |
| NG6 | `SectionView` is embedded in `SpaceContentView`; no detached-window code path exists. |
| NG7 | Terminal panes resolve wd via `WorkingDirectoryResolver` using Space/workspace defaults — no per-section default field on `SpaceModel`. |
| NG8 | `PaneViewModel` notification handler for Claude exit calls `closePane` (not `restartShell`). Unit test confirms. |
| NG9 | `SectionModel` and related types have no analytics calls — code review grep for telemetry dependencies. |
| NG10 | `SpaceModel` has a single `splitRatio: Double`, not two — compile-enforced. |

### Unit Tests

New test files (Swift Testing):

- `tianTests/SectionModelTests.swift` — tab ops, onEmpty, active-tab bookkeeping.
- `tianTests/SpaceModelSectionTests.swift` — show/hide, dock toggle, ratio clamp, cascading close, emptyClaude state, resetTerminal.
- `tianTests/SectionSpawnerTests.swift` — Claude panes get `initialInput="claude\n"` and propagated env vars; Terminal panes get `nil` initial input.
- `tianTests/SpaceLevelSplitNavigationTests.swift` — FR-19 cross-section navigation using pane frames derived from a shared `SectionLayout` helper.
- Existing `tianTests/SplitNavigationTests.swift` unaffected.

### Integration Tests

- `tianTests/SessionMigrationV3ToV4Tests.swift` — synthetic v3 JSON payload fed through `SessionStateMigrator.migrateIfNeeded(data:)`; asserts resulting structure has `claudeSection`, `terminalSection`, `terminalVisible=false`, legacy `tabs` relocated, `claudeSessionState` preserved on every moved pane, and `SessionStateMigrator.migrations[3]` is non-nil.
- `tianTests/SessionRoundTripV4Tests.swift` — build a populated in-memory `WorkspaceCollection`, snapshot → encode → decode → restore → compare.

### End-to-End Tests

End-to-end UI tests live in `tianUITests/`. New flows:

- **Flow: Create new Space** (PRD 6.1) — launches app, ⌘⇧T, verifies Claude pane visible, Terminal hidden, `claude` prompt active within 1s.
- **Flow: Open Terminal section first time** (PRD 6.2) — `Ctrl+`` ` ``; assert Terminal section appears right-docked, shell prompt within 500ms.
- **Flow: Switch Terminal position** (PRD 6.3) — click Move to bottom; assert `VStack` layout, same ratio, no pane exit.
- **Flow: Claude exits** (PRD 6.4) — type `/exit`; assert pane closed within 1s, Space still open if Terminal has panes, placeholder shown if none.
- **Flow: Last Terminal pane closes** (PRD 6.5) — `exit` in the only Terminal pane; assert auto-hide + Claude expands.
- **Flow: Hide and reopen Terminal** (PRD 6.6) — populate Terminal with 2 tabs + split, hide, show; assert layout + working directories preserved.
- **Flow: Quit and restore** (PRD 6.7) — populated Claude + visible bottom-docked Terminal; quit; relaunch; assert state restored.
- **Flow: First launch after upgrade** (PRD 6.8) — seed v3 state file in sandbox; launch; assert Claude section fresh, Terminal section matches legacy tabs, alert shown once.

### Edge Case & Error Path Tests

| Case | Test |
|------|------|
| Empty Claude state + explicit Cmd+W, Terminal has no foreground processes | `requestSpaceClose()` fires → `SpaceCollection.removeSpace` runs; Terminal processes are SIGHUPped as part of normal Space teardown. Unit test asserts behaviour. |
| Empty Claude state + explicit Cmd+W, Terminal has live foreground processes | Confirmation dialog (parent PRD FR-22) lists the running processes; on confirm, `requestSpaceClose()` fires; on cancel, no-op. Unit test asserts the dialog is presented when foreground processes exist. |
| Empty Claude state + both sections empty + implicit | No automatic Space close; the user remains in empty-Claude placeholder. Unit test asserts `space.onSpaceClose` closure is NOT invoked. |
| Dock toggle while divider drag in progress (FR-15) | Toolbar button tap during an active `SectionDividerView` drag gesture: dock toggle is queued until gesture end; during drag the button is visually disabled with a tooltip "Release divider to switch dock". Unit test asserts queued behaviour. |
| Drag divider past Terminal minimum | Auto-hide triggered once on gesture end; `terminalVisible=false`; Claude at 100%; working directories + panes preserved. |
| Drag divider past Claude minimum | Hard stop; ratio does not fall below the threshold. |
| Claude binary missing | `PaneState.spawnFailed` on Claude pane; Retry button visible; Space stays alive; Terminal unaffected. |
| Corrupted v3 state file | Fresh-launch fallback; one-time alert with path to legacy file. |
| Cmd+Shift+` with hidden Terminal | No-op; focus stays in Claude. |
| Cmd+Shift+` with empty Claude | No-op if Terminal empty; otherwise focus to Terminal's last-focused pane. |
| Dock toggle while divider drag in progress | Dock change commits only on gesture end; mid-drag changes are ignored. |
| Reset Terminal while Terminal section has 4 tabs + splits | All panes cleaned up (surfaces freed, PTYs SIGHUPped); section returns to zero-tab state; next show creates fresh single pane. |

### Performance & Load Tests

| Target | Verification |
|--------|--------------|
| First shell prompt within 200ms of `Ctrl+`` ` `` | Instrument `Log.perf` surface-creation timing, assert p95 ≤ 200ms on local test Mac. |
| 60fps divider drag | Manual Instruments pass; no CPU-bound operations in drag handler. |
| Cold-launch restore with 5 Claude panes | All `.running` within 2s; manual QA for CPU/memory spike. (FR-29 rate limit deferred.) |
| Serialization size | v4 state.json within 10% of v3 size for a representative session (5 Spaces × 3 tabs). |

---

## 13.5 Test Skeletons

One failing-test skeleton per FR (matching the table in Section 13). All skeletons use Swift Testing (`import Testing`, `@Test`, `#expect`). File placement follows the plan in "Unit Tests" above.

```swift
// tianTests/SpaceModelSectionTests.swift
import Testing
import Foundation
@testable import tian

@MainActor
struct SpaceModelSectionTests {

    // FR-01
    @Test func newSpaceHasOneClaudeSection() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        #expect(space.claudeSection.kind == .claude)
        #expect(space.claudeSection.tabs.count == 1)
    }

    // FR-02
    @Test func newSpaceStartsWithTerminalHidden() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        #expect(space.terminalVisible == false)
    }

    // FR-03
    @Test func initialClaudePaneIsSeededWithClaudeCommand() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.claudeSection.tabs[0]
        let paneID = tab.paneViewModel.splitTree.focusedPaneID
        let view = tab.paneViewModel.surfaceView(for: paneID)
        #expect(view?.initialInput == "claude\n")
    }

    // FR-04 (section isolation)
    @Test func tabOperationsOnOneSectionDoNotAffectOther() {
        let space = makeSpaceWithBothSections()
        let claudeTabCountBefore = space.claudeSection.tabs.count
        space.terminalSection.createTab(workingDirectory: "/tmp")
        #expect(space.claudeSection.tabs.count == claudeTabCountBefore)
    }

    // FR-07 (cascade safety)
    @Test func closingLastClaudeTabKeepsSpaceAliveWhenTerminalHasPanes() {
        let space = makeSpaceWithBothSections()
        let claudeTabID = space.claudeSection.tabs[0].id
        space.claudeSection.removeTab(id: claudeTabID)
        #expect(space.claudeSection.tabs.isEmpty)
        #expect(space.terminalSection.tabs.isEmpty == false)
        // Space should NOT have fired onSpaceClose
        #expect(space.isEffectivelyEmpty == false)
    }

    // FR-07b (no automatic close when both empty)
    @Test func closingLastClaudeTabDoesNotCloseSpaceEvenIfTerminalEmpty() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        var spaceClosed = false
        space.onSpaceClose = { spaceClosed = true }
        let claudeTabID = space.claudeSection.tabs[0].id
        space.claudeSection.removeTab(id: claudeTabID)
        #expect(spaceClosed == false)
        #expect(space.isEffectivelyEmpty == true)  // but still reachable
    }

    // FR-07c (explicit Cmd+W on empty Claude closes the Space)
    @Test func explicitCloseRequestFromEmptyClaudeClosesSpace() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        var spaceClosed = false
        space.onSpaceClose = { spaceClosed = true }
        let claudeTabID = space.claudeSection.tabs[0].id
        space.claudeSection.removeTab(id: claudeTabID)
        space.requestSpaceClose()
        #expect(spaceClosed == true)
    }

    // FR-12 (Terminal auto-hide)
    @Test func closingLastTerminalTabAutoHidesSection() {
        let space = makeSpaceWithBothSections()
        space.terminalVisible = true
        let termTabID = space.terminalSection.tabs[0].id
        space.terminalSection.removeTab(id: termTabID)
        #expect(space.terminalVisible == false)
    }

    // FR-13 (hide preserves layout)
    @Test func hideTerminalPreservesTabsAndPanes() {
        let space = makeSpaceWithBothSections()
        space.showTerminal()
        space.terminalSection.createTab(workingDirectory: "/tmp")
        let expectedTabIDs = space.terminalSection.tabs.map(\.id)
        space.hideTerminal()
        #expect(space.terminalSection.tabs.map(\.id) == expectedTabIDs)
        space.showTerminal()
        #expect(space.terminalSection.tabs.map(\.id) == expectedTabIDs)
    }

    // FR-13 (reset)
    @Test func resetTerminalSectionClearsAllTabs() {
        let space = makeSpaceWithBothSections()
        space.showTerminal()
        space.terminalSection.createTab(workingDirectory: "/tmp")
        space.resetTerminalSection()
        #expect(space.terminalSection.tabs.isEmpty)
    }

    // FR-14
    @Test func defaultDockPositionIsRight() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        #expect(space.dockPosition == .right)
    }

    // FR-15 (toggle does not close panes)
    @Test func togglingDockPositionDoesNotAffectPanes() {
        let space = makeSpaceWithBothSections()
        space.showTerminal()
        let paneCountBefore = space.terminalSection.tabs[0].paneViewModel.surfaces.count
        space.setDockPosition(.bottom)
        #expect(space.dockPosition == .bottom)
        #expect(space.terminalSection.tabs[0].paneViewModel.surfaces.count == paneCountBefore)
    }

    // FR-20
    @Test func cycleFocusedSectionMovesFocusBetweenSections() {
        let space = makeSpaceWithBothSections()
        space.focusedSectionKind = .claude
        space.cycleFocusedSection()
        #expect(space.focusedSectionKind == .terminal)
    }

    @Test func cycleFocusedSectionNoOpWhenTargetEmpty() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        // Terminal has no tabs
        space.focusedSectionKind = .claude
        space.cycleFocusedSection()
        #expect(space.focusedSectionKind == .claude)
    }

    // Helpers
    private func makeSpaceWithBothSections() -> SpaceModel {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()  // seeds one Terminal tab per FR-10
        return space
    }
}
```

```swift
// tianTests/SectionSpawnerTests.swift
import Testing
@testable import tian

@MainActor
struct SectionSpawnerTests {

    // FR-05
    @Test func claudeSpawnerInjectsClaudeCommandAndEnv() {
        let view = TerminalSurfaceView()
        let env: [String: String] = ["TIAN_PANE_ID": "abc"]
        SectionSpawner.configure(view: view, kind: .claude, workingDirectory: "/tmp", environmentVariables: env)
        #expect(view.initialInput == "claude\n")
        #expect(view.initialWorkingDirectory == "/tmp")
        #expect(view.environmentVariables["TIAN_PANE_ID"] == "abc")
    }

    // FR-11
    @Test func terminalSpawnerLeavesInitialInputNil() {
        let view = TerminalSurfaceView()
        let env: [String: String] = ["TIAN_PANE_ID": "xyz"]
        SectionSpawner.configure(view: view, kind: .terminal, workingDirectory: "/tmp", environmentVariables: env)
        #expect(view.initialInput == nil)
        #expect(view.environmentVariables["TIAN_PANE_ID"] == "xyz")
    }

    // FR-21 (inherit from source pane)
    @Test func splittingClaudePaneProducesClaudePane() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let claudeTab = space.claudeSection.tabs[0]
        let newID = claudeTab.paneViewModel.splitPane(direction: .horizontal)
        #expect(newID != nil)
        let newView = claudeTab.paneViewModel.surfaceView(for: newID!)
        #expect(newView?.initialInput == "claude\n")
    }

    // FR-06 — Claude pane exit (any code) closes the pane; Terminal keeps .exited.
    @Test func claudeExitWithNonZeroCodeClosesPane() async throws {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.claudeSection.tabs[0]
        let paneID = try #require(tab.paneViewModel.splitTree.focusedPaneID)
        let surfaceID = try #require(tab.paneViewModel.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceExitedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID, "exitCode": UInt32(1)]
        )
        try await Task.sleep(for: .milliseconds(10))
        #expect(tab.paneViewModel.paneStates[paneID] == nil)  // pane removed
    }

    @Test func terminalExitWithNonZeroCodeKeepsPaneInExitedState() async throws {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()
        let tab = space.terminalSection.tabs[0]
        let paneID = try #require(tab.paneViewModel.splitTree.focusedPaneID)
        let surfaceID = try #require(tab.paneViewModel.surface(for: paneID)?.id)

        NotificationCenter.default.post(
            name: GhosttyApp.surfaceExitedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID, "exitCode": UInt32(1)]
        )
        try await Task.sleep(for: .milliseconds(10))
        if case .exited(let code) = tab.paneViewModel.paneStates[paneID] {
            #expect(code == 1)
        } else {
            Issue.record("Expected .exited state")
        }
    }
}
```

```swift
// tianTests/SpaceLevelSplitNavigationTests.swift
import Testing
import CoreGraphics
import Foundation
@testable import tian

@MainActor
struct SpaceLevelSplitNavigationTests {

    // Helper: build frames via the real SectionLayout helper so the test
    // tracks implementation constants (divider thickness, pixel minimums)
    // rather than hardcoded magic numbers.
    private func makeFrames(
        claudeID: UUID,
        terminalID: UUID,
        container: CGSize,
        dock: DockPosition,
        ratio: Double
    ) -> [UUID: CGRect] {
        let layout = SectionLayout.computeFrames(
            containerSize: container,
            ratio: ratio,
            dock: dock,
            claudeMin: SectionDividerClamper.defaultClaudeMin,
            terminalMin: SectionDividerClamper.defaultTerminalMin,
            dividerThickness: SectionDividerView.thickness
        )
        return [claudeID: layout.claude, terminalID: layout.terminal]
    }

    // FR-19 (cross-section, right-docked)
    @Test func focusRightCrossesSectionDivider() {
        let claude = UUID()
        let terminal = UUID()
        let frames = makeFrames(
            claudeID: claude, terminalID: terminal,
            container: CGSize(width: 800, height: 600),
            dock: .right, ratio: 0.7
        )
        #expect(SplitNavigation.neighbor(of: claude, direction: .right, in: frames) == terminal)
    }

    @Test func focusLeftFromTerminalFindsClaude() {
        let claude = UUID()
        let terminal = UUID()
        let frames = makeFrames(
            claudeID: claude, terminalID: terminal,
            container: CGSize(width: 800, height: 600),
            dock: .right, ratio: 0.7
        )
        #expect(SplitNavigation.neighbor(of: terminal, direction: .left, in: frames) == claude)
    }

    @Test func focusRightFromRightmostPaneIsNoOp() {
        let claude = UUID()
        let terminal = UUID()
        let frames = makeFrames(
            claudeID: claude, terminalID: terminal,
            container: CGSize(width: 800, height: 600),
            dock: .right, ratio: 0.7
        )
        #expect(SplitNavigation.neighbor(of: terminal, direction: .right, in: frames) == nil)
    }

    @Test func focusDownCrossesBottomDockedDivider() {
        let claude = UUID()
        let terminal = UUID()
        let frames = makeFrames(
            claudeID: claude, terminalID: terminal,
            container: CGSize(width: 800, height: 600),
            dock: .bottom, ratio: 0.7
        )
        #expect(SplitNavigation.neighbor(of: claude, direction: .down, in: frames) == terminal)
    }
}
```

```swift
// tianTests/RetryClaudeSpawnTests.swift
import Testing
import Foundation
@testable import tian

@MainActor
struct RetryClaudeSpawnTests {

    // FR-08b — Retry on a spawn-failed Claude pane re-initialises the surface.
    // Drives state via the existing `surfaceSpawnFailedNotification` code path
    // (PaneViewModel.installObservers) and invokes restartShell, which today
    // already handles `.spawnFailed` transitions (PaneViewModel.swift:310-313).
    @Test func retryReInitiatesSpawnOnSpawnFailedPane() async throws {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        let tab = space.claudeSection.tabs[0]
        let paneID = try #require(tab.paneViewModel.splitTree.focusedPaneID)
        let surfaceID = try #require(tab.paneViewModel.surface(for: paneID)?.id)

        // Trigger `.spawnFailed` via the real notification pipeline.
        NotificationCenter.default.post(
            name: GhosttyApp.surfaceSpawnFailedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID]
        )
        try await Task.sleep(for: .milliseconds(10))  // let notification dispatch
        #expect(tab.paneViewModel.paneStates[paneID] == .spawnFailed)

        // Retry re-arms the surface. On success, state clears out of
        // `.spawnFailed` immediately. Note: in unit-test context the view
        // has no window, so `restartShell`'s `if surfaceView.window != nil`
        // branch does NOT invoke a real PTY spawn — this test covers the
        // state-machine transition only. The real spawn path is exercised
        // by `tianUITests/` end-to-end flows.
        tab.paneViewModel.restartShell(paneID: paneID)
        #expect(tab.paneViewModel.paneStates[paneID] != .spawnFailed)

        // Claude "command" is still set (assigned by SectionSpawner at
        // initial tab creation in Phase 1; see Section 3 call-site map).
        let view = tab.paneViewModel.surfaceView(for: paneID)
        #expect(view?.initialInput == "claude\n")

        // A second spawn failure on the same pane returns it to .spawnFailed.
        NotificationCenter.default.post(
            name: GhosttyApp.surfaceSpawnFailedNotification,
            object: nil,
            userInfo: ["surfaceId": surfaceID]
        )
        try await Task.sleep(for: .milliseconds(10))
        #expect(tab.paneViewModel.paneStates[paneID] == .spawnFailed)
    }
}
```

```swift
// tianTests/DockToggleDuringDragTests.swift
import Testing
@testable import tian

@MainActor
struct DockToggleDuringDragTests {

    // FR-15 — Dock toggle is queued while divider drag is active.
    @Test func dockToggleMidDragIsQueuedUntilGestureEnd() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()
        #expect(space.dockPosition == .right)

        // Start drag.
        space.sectionDividerDragController.beginDrag()
        space.setDockPosition(.bottom)  // should be queued
        #expect(space.dockPosition == .right)  // unchanged mid-drag

        // End drag; queued toggle applies.
        space.sectionDividerDragController.endDrag(finalRatio: 0.6)
        #expect(space.dockPosition == .bottom)
    }
}
```

```swift
// tianTests/SessionMigrationV3ToV4Tests.swift
import Testing
import Foundation
@testable import tian

struct SessionMigrationV3ToV4Tests {

    // Guard rail: non-identity migration must be registered.
    @Test func migrationForV3IsRegistered() {
        #expect(SessionStateMigrator.migrations[3] != nil)
    }

    // FR-25
    @Test func v3SpaceWithTabsMigratesIntoTerminalSection() throws {
        let v3 = """
        {
          "version": 3,
          "savedAt": "2026-04-20T00:00:00Z",
          "activeWorkspaceId": "11111111-1111-1111-1111-111111111111",
          "workspaces": [{
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "default",
            "activeSpaceId": "22222222-2222-2222-2222-222222222222",
            "defaultWorkingDirectory": "/tmp",
            "spaces": [{
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "default",
              "activeTabId": "33333333-3333-3333-3333-333333333333",
              "defaultWorkingDirectory": "/tmp",
              "tabs": [{
                "id": "33333333-3333-3333-3333-333333333333",
                "name": null,
                "activePaneId": "44444444-4444-4444-4444-444444444444",
                "root": {"type":"pane","paneID":"44444444-4444-4444-4444-444444444444","workingDirectory":"/tmp","restoreCommand":null,"claudeSessionState":null}
              }]
            }]
          }]
        }
        """.data(using: .utf8)!

        let migrated = try SessionStateMigrator.migrateIfNeeded(data: v3)!
        let json = try JSONSerialization.jsonObject(with: migrated) as! [String: Any]
        #expect((json["version"] as? Int) == 4)

        let ws = (json["workspaces"] as! [[String: Any]])[0]
        let space = (ws["spaces"] as! [[String: Any]])[0]

        // Legacy tabs must be gone
        #expect(space["tabs"] == nil)

        // Terminal section carries legacy tabs
        let terminal = space["terminalSection"] as! [String: Any]
        #expect((terminal["kind"] as? String) == "terminal")
        let termTabs = terminal["tabs"] as! [[String: Any]]
        #expect(termTabs.count == 1)
        #expect((termTabs[0]["id"] as? String) == "33333333-3333-3333-3333-333333333333")

        // Claude section synthesised with one fresh tab
        let claude = space["claudeSection"] as! [String: Any]
        #expect((claude["kind"] as? String) == "claude")
        #expect((claude["tabs"] as! [[String: Any]]).count == 1)

        // Layout defaults
        #expect((space["terminalVisible"] as? Bool) == false)
        #expect((space["dockPosition"] as? String) == "right")
        #expect((space["splitRatio"] as? Double) == 0.7)
        #expect((space["focusedSectionKind"] as? String) == "claude")
    }

    // FR-25b
    @Test func corruptedV3DataThrowsMigrationError() {
        let corrupted = "{".data(using: .utf8)!
        #expect(throws: Error.self) {
            _ = try SessionStateMigrator.migrateIfNeeded(data: corrupted)
        }
    }

    // FR-25c — claudeSessionState on migrated shell panes is preserved verbatim
    // so the claude-session-status feature keeps working after upgrade.
    @Test func claudeSessionStateSurvivesMigration() throws {
        let v3 = """
        {
          "version": 3, "savedAt": "2026-04-20T00:00:00Z",
          "activeWorkspaceId": "11111111-1111-1111-1111-111111111111",
          "workspaces": [{
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "default", "activeSpaceId": "22222222-2222-2222-2222-222222222222",
            "defaultWorkingDirectory": "/tmp",
            "spaces": [{
              "id": "22222222-2222-2222-2222-222222222222", "name": "default",
              "activeTabId": "33333333-3333-3333-3333-333333333333",
              "defaultWorkingDirectory": "/tmp",
              "tabs": [{
                "id": "33333333-3333-3333-3333-333333333333", "name": null,
                "activePaneId": "44444444-4444-4444-4444-444444444444",
                "root": {"type":"pane","paneID":"44444444-4444-4444-4444-444444444444",
                         "workingDirectory":"/tmp","restoreCommand":null,
                         "claudeSessionState":{"status":"idle","sessionId":"s-123"}}
              }]
            }]
          }]
        }
        """.data(using: .utf8)!

        let migrated = try SessionStateMigrator.migrateIfNeeded(data: v3)!
        let json = try JSONSerialization.jsonObject(with: migrated) as! [String: Any]
        let ws = (json["workspaces"] as! [[String: Any]])[0]
        let space = (ws["spaces"] as! [[String: Any]])[0]
        let terminal = space["terminalSection"] as! [String: Any]
        let tab = (terminal["tabs"] as! [[String: Any]])[0]
        let root = tab["root"] as! [String: Any]
        let css = root["claudeSessionState"] as! [String: Any]
        #expect((css["sessionId"] as? String) == "s-123")
    }
}
```

```swift
// tianTests/SessionRoundTripV4Tests.swift
import Testing
import Foundation
@testable import tian

@MainActor
struct SessionRoundTripV4Tests {

    // FR-23
    @Test func roundTripPreservesSectionVisibilityAndRatio() throws {
        let collection = WorkspaceCollection(workingDirectory: "/tmp")
        let space = collection.activeWorkspace!.spaceCollection.activeSpace!
        space.showTerminal()
        space.setDockPosition(.bottom)
        space.setSplitRatio(0.6)
        space.focusedSectionKind = .terminal   // simulate user focused Terminal at quit
        space.hideTerminal()  // preserve layout

        let snapshot = SessionSerializer.snapshot(from: collection)
        let data = try SessionSerializer.encode(snapshot)
        let decoded = try SessionRestorer.decode(from: data)

        let restored = decoded.workspaces[0].spaces[0]
        #expect(restored.terminalVisible == false)
        #expect(restored.dockPosition == .bottom)
        #expect(abs(restored.splitRatio - 0.6) < 0.0001)
        #expect(restored.terminalSection.tabs.count >= 1)
        #expect(restored.focusedSectionKind == .terminal)
    }

    // FR-24 (Claude panes get fresh claude\n on restore)
    @Test func restoredClaudePanesReinjectClaudeCommand() throws {
        let collection = WorkspaceCollection(workingDirectory: "/tmp")
        let snapshot = SessionSerializer.snapshot(from: collection)
        let data = try SessionSerializer.encode(snapshot)
        let decoded = try SessionRestorer.decode(from: data)
        let restored = SessionRestorer.buildWorkspaceCollection(from: decoded)
        let claudeTab = restored.workspaces[0].spaceCollection.activeSpace!.claudeSection.tabs[0]
        let paneID = claudeTab.paneViewModel.splitTree.focusedPaneID
        let view = claudeTab.paneViewModel.surfaceView(for: paneID)
        #expect(view?.initialInput == "claude\n")
    }
}
```

```swift
// tianTests/DividerClampingTests.swift
import Testing
import CoreGraphics
@testable import tian

@MainActor
struct DividerClampingTests {

    // FR-16 (hard stop at Claude min)
    @Test func dragBelowClaudeMinimumIsClamped() {
        let helper = SectionDividerClamper(containerAxis: 800, claudeMin: 320, terminalMin: 160)
        let clamped = helper.clampRatio(proposed: 0.1, dock: .right)
        // Claude ≥ 320pt of 800pt = ratio ≥ 0.4
        #expect(clamped >= 0.4 - 0.001)
    }

    // FR-16 (auto-hide when past Terminal min on release)
    @Test func dragPastTerminalMinimumSignalsAutoHide() {
        let helper = SectionDividerClamper(containerAxis: 800, claudeMin: 320, terminalMin: 160)
        let (clamped, shouldHide) = helper.evaluateDragEnd(proposedRatio: 0.95, dock: .right)
        #expect(shouldHide == true)
        #expect(clamped >= 0.4 - 0.001)  // clamped back to last valid before hide
    }
}
```

```swift
// tianTests/TabDragConstraintTests.swift
import Testing
@testable import tian

@MainActor
struct TabDragConstraintTests {

    // FR-22
    @Test func tabDragRejectedAcrossSections() {
        let space = SpaceCollection(workingDirectory: "/tmp").activeSpace!
        space.showTerminal()
        let claudeTabID = space.claudeSection.tabs[0].id
        // Simulated drop into Terminal tab bar:
        let accepted = SectionTabBarDropCoordinator.canAccept(
            sourceSectionKind: .claude,
            destinationSectionKind: .terminal,
            tabID: claudeTabID
        )
        #expect(accepted == false)
    }
}
```

Coverage: every FR in the PRD (FR-01..FR-29) has at least one skeleton above or is covered by an existing test file that will be extended (e.g. FR-17 via existing view-layout tests or manual QA where automated assertion is not practical). FR-17, FR-26, FR-27, FR-28 are snapshot / constant tests flagged in Section 13 but not skeletonised here because they are trivial `#expect` on view constants and will be co-located with view files.

---

## 14. Technical Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Migration v3→v4 corrupts user state | Users lose persisted tabs | Low | Migration operates on raw JSON, is purely additive for most fields; `state.prev.json` backup preserved; fresh-launch fallback surfaces legacy file path; integration test with real v3 fixture. |
| Injecting `claude\n` via `initialInput` races with shell prompt not ready | Claude fails to launch / prints to wrong prompt | Medium | Existing `initialInput` path in `TerminalSurfaceView.viewDidMoveToWindow` already synchronises injection after surface creation; this is the same mechanism used for `restoreCommand` today. Retry button (FR-08) catches edge cases. |
| Divider drag clamp math inconsistent between right-dock and bottom-dock | User sees jumping divider | Medium | Single `SectionDividerClamper` helper covers both orientations; unit tests at each dock. |
| Cold-launch restore with many Claude panes saturates CPU/memory (FR-29 deferred) | Slow cold-launch UX | Low in practice (typical sessions restore 1–3 Claude panes) | Monitor via `Log.perf` spawn-latency signal; revisit with a real spawn-settled signal if observed. |
| Cross-section directional focus picks wrong pane due to divider-in-middle heuristic | Cmd+Opt+→ feels wrong | Low | Existing `SplitNavigation.edgeDistanceSquared` already uses center-of-nearest-edge; re-using it unchanged ensures parity with within-tab behaviour. |
| Terminal section "hide" while panes have running foreground processes becomes surprising to user | User thinks they killed processes | Low | FR-13 explicitly keeps shells alive in hidden state. A status indicator (number of background panes) can be added to the Show Terminal button — defer to open question 15.3. |
| Cascading-close invariant inverted: closing last Claude pane accidentally closes Space when Terminal has panes | Data loss (background jobs killed) | High if buggy | Covered by two targeted unit tests (FR-07, FR-07b); implement the `isEffectivelyEmpty` predicate in one place and reuse. |
| SwiftUI re-rendering the entire Space on every divider drag frame | Dropped frames | Medium | `SectionDividerView` holds live drag offset in `@GestureState` and exposes it via a `PreferenceKey` consumed by the two `SectionView` geometry modifiers. `SpaceContentView.body` does not read `splitRatio` mid-drag, so terminal-surface bodies are not re-invoked per frame. Commit to `SpaceModel` once on release; disable implicit animation during gesture. |
| v4 adds optional `TabState.sectionKind` that becomes ambiguous if inferred wrong post-migration | Panes mis-typed after migration | Low | Migration explicitly sets `sectionKind` on every migrated tab; restore validation double-checks against parent `SectionState.kind` and corrects (logging a stalePaneIdFix-style counter). |

---

## 15. Open Technical Questions

| # | Question | Context | Impact if unresolved |
|---|----------|---------|----------------------|
| 15.1 | ~~Do we keep `TabState.sectionKind` as an explicit field on `TabState`, or infer it strictly from `SectionState.kind`?~~ | **Resolved in v1.1:** kept as **required** (non-optional) `TabState.sectionKind` in v4. Migration sets it explicitly; fresh tabs set it from their owning section; decode no longer has an "infer on nil" branch. | — |
| 15.2 | Tab drag UTI: extend existing `com.tian.tab-drag-item` payload with a `sectionKind` flag, or introduce two new UTIs? | Existing UTI ships today; a flag is less disruptive. | Low — proposed solution is to extend payload; test FR-22 either way. |
| 15.3 | Should the "Show Terminal" button show a badge indicating N background panes running while hidden (FR-13)? | PRD does not require it; could reduce "oh I didn't know processes were still running" confusion. | Low — ship without for v1; track as post-v1 enhancement. |
| 15.4 | On restore, should focus go to the last-focused pane regardless of section, or prefer Claude if Terminal was hidden at quit? | PRD open question 10.2; spec currently uses `focusedSectionKind` as authoritative. | Low — decision doesn't block implementation; current approach matches "last focused" and Terminal-hidden-at-quit implies `focusedSectionKind == .claude`. |
| 15.5 | FR-29 Claude spawn rate limit is deferred from v1. Is the deferred scope acceptable, and if we bring it back, what is the correct "spawn settled" signal? | `viewDidMoveToWindow` fires before the PTY is ready; Ghostty does not today emit a "first prompt" notification. Options: (a) hook the first OSC 7 / title-change event, (b) add a Ghostty callback, (c) timer-based gate. | Medium — deferred scope is safe for 1–3 Claude panes; revisit if thundering-herd observed in practice. |
| 15.6 | ~~How should the Cmd+W behaviour differ between an empty Claude placeholder and a normal focused pane?~~ | **Resolved in v1.1:** `EmptyClaudePlaceholderView` installs its own `.keyboardShortcut(.cancelAction)` binding on its Close button which calls `SpaceModel.requestSpaceClose()`. Normal pane Cmd+W is intercepted earlier by `TerminalSurfaceView.performKeyEquivalent` and is unaffected. | — |
| 15.7 | Where does the one-time "tian was upgraded..." notice live (FR-25 happy path)? | PRD flow describes the text but not the surface. | Low — spec proposes an `NSAlert` sheet on the first active window after upgrade; defer final copy to open question 10.1 design review. |
| 15.8 | Do we need `.tian/config.toml` hooks for this feature (e.g. dock-position override, default ratio)? | Parent PRD FR-27 says key bindings are eventually configurable; this feature only defines two new actions, so config support can come later. | None — v1 ships with hardcoded defaults matching PRD. |
