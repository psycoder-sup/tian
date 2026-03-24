# SPEC: M4 -- Workspaces

**Based on:** docs/feature/aterm/aterm-prd.md v1.4
**Author:** CTO Agent
**Date:** 2026-03-24
**Version:** 1.0
**Status:** Draft

---

## 1. Overview

Milestone 4 introduces the Workspace tier of aterm's 4-level hierarchy (Workspace > Space > Tab > Pane). It adds the ability to create, rename, reorder, and delete named workspaces; a fuzzy-search workspace switcher overlay; a workspace indicator in the window title bar; multi-window support (one workspace per macOS window); and default working directories assignable at the workspace and space levels. This milestone builds on top of M1 (terminal core), M2 (pane splitting), and M3 (tabs and spaces), which provide the PTY/rendering layer, the pane split tree, the tab model, and the space model respectively. M4 does not include persistence (M5) or configuration/profiles (M6), but its data model must be designed with those milestones in mind.

---

## 2. Data Model

### 2.1 Workspace

The `Workspace` is the top-level organizational unit. Each workspace maps to a project and owns a collection of spaces.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Stable identity, generated at creation time. Used as the key for persistence in M5. |
| name | String | User-visible display name. Must be non-empty. Not required to be unique, but the switcher should visually disambiguate duplicates. |
| defaultWorkingDirectory | URL? (optional) | If set, new spaces/tabs/panes created within this workspace default to this directory unless overridden at the space level. Falls back to the user's home directory when nil. |
| spaces | OrderedCollection of Space | Ordered list of spaces within this workspace. Must contain at least one space at all times. |
| activeSpaceID | UUID | The ID of the currently focused space. |
| createdAt | Date | Timestamp of creation. Used for ordering in the switcher when sort-by-creation is desired. |

### 2.2 Space Modifications (extends M3 model)

M3 defines the Space model. M4 adds one field:

| Field | Type | Description |
|-------|------|-------------|
| defaultWorkingDirectory | URL? (optional) | If set, overrides the workspace-level default for new tabs/panes within this space. |

### 2.3 Working Directory Resolution Order

When a new pane is created (new tab, new split, new space), the working directory is resolved by walking up the hierarchy:

1. If the action is "split pane" or "new tab in current space", inherit the working directory of the source pane (existing M2 behavior).
2. If the action is "new space" or "new tab in a fresh space", check the space's `defaultWorkingDirectory`.
3. If the space has no default, check the workspace's `defaultWorkingDirectory`.
4. If neither is set, use the user's home directory (`$HOME`).

This resolution logic should be encapsulated in a single pure function so it can be unit-tested independently.

### 2.4 Application State Model

The top-level application state holds the collection of all workspaces and the mapping of windows to workspaces.

| Field | Type | Description |
|-------|------|-------------|
| workspaces | OrderedCollection of Workspace | All workspaces in creation order. When the last workspace is removed, the app quits (FR-05 cascading close). |
| windowWorkspaceMap | Dictionary of NSWindow.ID to Workspace.ID | Tracks which window is displaying which workspace. |
| activeWindowID | NSWindow.ID? | The frontmost window. Determines the "current" workspace for keyboard shortcuts that are not window-scoped. |

---

## 3. WorkspaceManager

### 3.1 Responsibilities

`WorkspaceManager` is the central coordinator for workspace lifecycle. It is an `ObservableObject` (or `@Observable` class targeting macOS 26) that the SwiftUI layer observes for state changes.

### 3.2 Operations

| Operation | Inputs | Behavior | Validation / Edge Cases |
|-----------|--------|----------|------------------------|
| createWorkspace | name: String, workingDirectory: URL? | Creates a new Workspace with one default Space, one Tab, one Pane. Spawns a shell in the resolved working directory. Opens the workspace in a new window (or the current window if it is the initial launch). Returns the new workspace. | Name must be non-empty (trim whitespace). If empty after trim, reject with an error. |
| renameWorkspace | workspaceID: UUID, newName: String | Updates the workspace name. Triggers UI refresh of the workspace indicator and any open switcher. | Same non-empty validation. |
| deleteWorkspace | workspaceID: UUID | Closes all PTY sessions in the workspace (sends SIGHUP to each). Removes the workspace. Closes the associated window. If this was the last workspace, the app quits via `NSApplication.shared.terminate(nil)`. The M5 quit flow (serialize state before quitting) still applies -- state is serialized before the app terminates. | Confirm before delete if any pane has a foreground process (reuse the same confirmation pattern as FR-22). |
| setDefaultWorkingDirectory (workspace) | workspaceID: UUID, directory: URL? | Sets or clears the workspace-level default working directory. | Validate that the directory exists and is accessible. If not, show an inline error and do not set. |
| setDefaultWorkingDirectory (space) | spaceID: UUID, directory: URL? | Sets or clears the space-level default working directory. | Same validation. |
| switchToWorkspace | workspaceID: UUID | Brings the window associated with the given workspace to the front. If the workspace has no window (future: if workspaces can exist without a window), opens one. Restores focus to the last-active pane in that workspace. | No-op if already the active workspace. |
| reorderWorkspace | sourceIndex: Int, destinationIndex: Int | Moves a workspace from one position to another in the ordered list. The UI triggers this via drag-and-drop in the workspace list/sidebar. | No validation needed beyond bounds checking on the indices. |

### 3.3 Concurrency Model

All workspace mutations happen on the main actor (`@MainActor`). Shell spawning (PTY fork/exec) is dispatched to a background thread and the resulting file descriptor is handed back to the main actor for integration with the pane model. This matches the pattern established in M1 for PTY spawning.

---

## 4. Fuzzy Search

### 4.1 Algorithm

The workspace switcher requires a fuzzy matcher that ranks workspace names against a query string. The algorithm should:

1. Use subsequence matching: every character in the query must appear in order within the candidate string, but not necessarily contiguously.
2. Score based on: (a) consecutive character matches (bonus), (b) match at word boundary or start of string (bonus), (c) shorter candidate strings ranked higher when scores are equal, (d) case-insensitive matching with bonus for exact case match.
3. Return results sorted by descending score, with a zero-score threshold (no match).

### 4.2 Implementation Approach

Implement as a standalone pure function: `fuzzyMatch(query: String, candidate: String) -> Int?` returning an optional score (nil = no match). A companion function `fuzzySearch(query: String, candidates: [(id: UUID, name: String)]) -> [(id: UUID, name: String, score: Int)]` filters and sorts.

This should be its own file (e.g., `FuzzyMatch.swift`) with no dependencies on UI or workspace types, making it trivially unit-testable.

### 4.3 Performance

For the expected workspace count (tens, maybe low hundreds), a simple O(n * m) per-candidate approach is sufficient. No indexing or caching is needed.

---

## 5. Multi-Window Architecture

### 5.1 AppKit Window Management with SwiftUI Content

The multi-window architecture uses **AppKit `NSWindowController`** for window lifecycle management and **`NSHostingView`** to embed SwiftUI views as window content. This is the same pattern used by Ghostty and other production macOS terminal emulators.

**Why not SwiftUI `WindowGroup(for:)`?** Research shows `WindowGroup(for:)` has persistent reliability issues across macOS 14-15: `dismissWindow` silently fails in some contexts, automatic state restoration creates phantom windows with stale data, and toolbar customization is broken with multiple windows. These bugs were not addressed in macOS 26 (WWDC 2025). Since multi-window management is a core architectural primitive for aterm, deterministic control over window lifecycle is essential.

**Architecture:**

```
NSWindow (AppKit — full lifecycle control)
└── NSHostingView (Apple's bridge class)
    └── WorkspaceWindowContent (SwiftUI — all interior UI)
        ├── WorkspaceIndicatorView (toolbar)
        ├── SpaceBar (from M3)
        ├── TabBar (from M3)
        └── PaneGrid (from M2)
```

**Key components:**

- **`WorkspaceWindowController`** — `NSWindowController` subclass. Creates and owns an `NSWindow`, sets its `contentView` to an `NSHostingView` wrapping the SwiftUI `WorkspaceWindowContent`. Implements `NSWindowDelegate` for close/resize/fullscreen events. Each instance is associated with exactly one workspace ID.
- **`WindowCoordinator`** — Manages all `WorkspaceWindowController` instances. Provides `openWindow(for:)`, `closeWindow(for:)`, and `bringToFront(for:)` methods. Owned by `WorkspaceManager`.
- **`AtermApp.swift`** — Uses a minimal SwiftUI `App` scene with `MenuBarExtra` or `.commands {}` for menu bar items and keyboard shortcuts. The initial window is created programmatically via `WindowCoordinator` on launch, not via `WindowGroup`.

### 5.2 Window Lifecycle

| Event | Behavior |
|-------|----------|
| New workspace created | `WindowCoordinator.openWindow(for: workspace.id)` creates a new `WorkspaceWindowController`, which creates an `NSWindow` with `NSHostingView(rootView: WorkspaceWindowContent(workspaceID: id))`, then calls `window.makeKeyAndOrderFront(nil)`. |
| Workspace deleted | `WindowCoordinator.closeWindow(for: workspace.id)` calls `window.close()` on the associated controller, which triggers cleanup via `NSWindowDelegate.windowWillClose(_:)`. |
| Window closed by user (red button) | `windowShouldClose(_:)` delegate method fires. If the workspace has foreground processes (checked via `tcgetpgrp`), present a confirmation dialog. On confirm (or no processes), delete the workspace and clean up PTYs. If this is the last window/workspace, the app quits via `NSApplication.shared.terminate(nil)`. The M5 quit flow (serialize state before quitting) still applies. |
| App quit (Cmd+Q) | `applicationShouldTerminate(_:)` on the app delegate. In M4 this tears down all workspaces. In M5 this will serialize first (using `.terminateLater` to defer quit until serialization completes). |
| Workspace switcher selects a workspace | `WindowCoordinator.bringToFront(for: workspace.id)` calls `window.makeKeyAndOrderFront(nil)` on the target workspace's window. If no window exists (post-M5 scenario), opens a new one. |

### 5.3 Window Title

Set `window.title = workspace.name` directly on the `NSWindow` via `WorkspaceWindowController`. Observe workspace name changes (via Combine publisher or `@Observable` callback) and update the title live when renamed.

### 5.4 One Workspace Per Window Constraint

Enforce that each window maps to exactly one workspace. The `WindowCoordinator` maintains a `[Workspace.ID: WorkspaceWindowController]` dictionary as the source of truth. The switcher does not change the current window's workspace -- it brings the target workspace's window to front (or opens a new window for it). This avoids complexity around detaching/reattaching space and tab state between windows.

### 5.5 NSHostingView Integration Notes

- The `NSHostingView` is created once per window and wraps the `WorkspaceWindowContent` SwiftUI view.
- The SwiftUI view receives the workspace ID and reads workspace state from the `WorkspaceManager` (injected via `.environment()`).
- SwiftUI keyboard shortcuts registered via `.commands {}` in the app scene still work inside `NSHostingView`.
- Focus management for the terminal pane (Metal view) must bridge between AppKit's `NSResponder` chain and SwiftUI's `@FocusState`. The `WorkspaceWindowController` should set the `NSHostingView` as the window's `initialFirstResponder`.

---

## 6. Workspace Switcher Overlay

### 6.1 Activation

Triggered by a keyboard shortcut (default: Cmd+Shift+W, configurable in M6). The shortcut is registered as a SwiftUI `.keyboardShortcut` on the menu bar command or via an `NSEvent` global monitor if it needs to work across windows.

### 6.2 UI Structure

The switcher is a modal overlay (not a sheet, not a separate window) rendered on top of the current window's content. It consists of:

| Element | Description |
|---------|-------------|
| Search field | Auto-focused text field at the top. Typing filters the list in real time via the fuzzy matcher. |
| Results list | Vertical list of matching workspaces. Each row shows: workspace name, default working directory (if set, abbreviated with `~`), and number of spaces/tabs. The currently active workspace should be visually distinguished (e.g., checkmark or highlight). |
| Selection highlight | Arrow keys (up/down) move a selection highlight through the list. The first result is selected by default. |
| Empty state | If no workspaces match the query, show "No matching workspaces" text. |

### 6.3 Interactions

| Input | Behavior |
|-------|----------|
| Typing | Updates the query, re-filters and re-scores the list. Selection resets to the top result. |
| Up/Down arrows | Move selection through the filtered list. Wraps around at boundaries. |
| Enter / Return | Switches to the selected workspace (brings its window to front or opens a new one). Dismisses the overlay. |
| Escape | Dismisses the overlay with no action. Focus returns to the previously active pane. |
| Click on a row | Same as Enter for that row. |
| Cmd+Shift+W (while open) | Dismisses the overlay (toggle behavior). |

### 6.4 Rendering

The overlay should use a semi-transparent background blur (`.ultraThinMaterial` or similar) to maintain visual context. It should appear centered in the window, occupying roughly 400pt wide by up to 50% of the window height. Animate in/out with a short fade or scale transition (150ms).

### 6.5 Accessibility

- The search field should have an accessibility label: "Search workspaces".
- Each row should expose the workspace name as its accessibility label.
- The list should use the `List` role so VoiceOver can announce item count and position.
- Selection changes via arrow keys should be announced.

---

## 7. Workspace Reorder via Drag-and-Drop (FR-01)

### 7.1 Scope

Workspaces can be reordered via drag-and-drop in the workspace switcher overlay's results list. This allows users to arrange workspaces in their preferred order.

### 7.2 Implementation

Use SwiftUI's `Transferable` protocol and `onDrag` / `onDrop` modifiers on the workspace list rows in the switcher overlay.

**Transferable type:** Define a `WorkspaceDragItem` struct conforming to `Transferable` with a custom UTType containing the workspace's UUID. This follows the same pattern used for tab and space drag-and-drop in M3.

**Drag interaction:**
- Each workspace row in the switcher overlay is draggable.
- During drag, a visual drop indicator (insertion line) appears at the target position.
- On drop, the `WorkspaceManager.reorderWorkspace(sourceIndex:destinationIndex:)` method is called to update the ordered workspace array.
- The switcher list re-renders to reflect the new order.
- Drag-and-drop is only enabled when the search query is empty (showing the full list). When the list is filtered by a search query, drag is disabled to avoid confusing reorders based on a filtered view.

**Persistence:** Workspace order is preserved in the M5 persistence schema (the `workspaces` array in the JSON state file is ordered).

---

## 8. Workspace Indicator

### 8.1 Location

Displayed in the window's title bar area. On macOS, this is the `toolbar` region or the window title itself. The simplest approach: set the window title to the workspace name (already covered in section 5.3). For richer display (e.g., an icon or badge), use a `ToolbarItem(placement: .principal)` containing the workspace name styled with the design system typography.

### 8.2 Content

The indicator shows: workspace name. Optionally (if space permits): the active space name separated by a chevron or slash (e.g., "tickle-app / feature-auth"). This combined display satisfies FR-06 ("display the current workspace name, space name, and tab").

### 8.3 Interaction

Clicking the workspace indicator could open the workspace switcher (nice-to-have, not required for M4 core).

---

## 9. Component Architecture

### 9.1 File Structure

All paths below are relative to the project's Swift source root (e.g., `aterm/Sources/`). The exact root depends on whether the project uses Swift Package Manager or an Xcode project; the relative structure within is what matters.

```
Models/
    Workspace.swift              -- Workspace struct/class
    WorkspaceManager.swift       -- Central workspace coordinator

WindowManagement/
    WorkspaceWindowController.swift  -- NSWindowController subclass, owns NSWindow + NSHostingView
    WindowCoordinator.swift          -- Manages all WorkspaceWindowController instances
    AtermAppDelegate.swift           -- NSApplicationDelegate for quit handling, window restoration

Views/
    WorkspaceSwitcher/
        WorkspaceSwitcherOverlay.swift    -- The overlay container
        WorkspaceSwitcherRow.swift        -- Individual row in the results list
        WorkspaceSwitcherSearchField.swift -- Search input field (if customized beyond TextField)

    WindowChrome/
        WorkspaceIndicatorView.swift      -- Title bar workspace indicator

    Workspace/
        WorkspaceWindowContent.swift      -- Root SwiftUI view hosted inside NSHostingView per window

DragAndDrop/
    WorkspaceDragItem.swift      -- Transferable conformance for workspace drag-and-drop reordering

Utilities/
    FuzzyMatch.swift             -- Fuzzy matching algorithm

App/
    AtermApp.swift               -- (modified) Minimal SwiftUI App scene for menu bar commands; windows created via WindowCoordinator
```

### 9.2 Dependency on M1-M3 Components

M4 depends on but does not modify the following M1-M3 components:

| Component | Milestone | M4 Usage |
|-----------|-----------|----------|
| PTY / Shell spawning | M1 | Creating shells for new workspace panes |
| Terminal renderer (Metal) | M1 | Rendering pane content in workspace windows |
| Pane model and split tree | M2 | Each workspace's tabs contain pane split trees |
| Pane focus management | M2 | Restoring focus to last-active pane when switching workspaces |
| Tab model and tab bar | M3 | Workspaces contain spaces which contain tabs |
| Space model and space bar | M3 | Workspaces contain an ordered collection of spaces |
| SpaceManager (or equivalent from M3) | M3 | WorkspaceManager delegates space operations to the existing space management layer |

### 9.3 Screen Specifications

#### WorkspaceWindowContent (root view per window)

- **Route/Context:** Receives a workspace ID. Looks up the Workspace from WorkspaceManager.
- **Layout:** Vertical stack: WorkspaceIndicatorView (in toolbar), SpaceBar (from M3), TabBar (from M3), content area with pane grid (from M2).
- **States:**
  - Normal: Displays the active space's active tab's pane grid.
  - Switcher open: Renders WorkspaceSwitcherOverlay on top of everything via a ZStack overlay.
  - Workspace not found (defensive): If the workspace ID no longer exists in WorkspaceManager (race condition during deletion), show a placeholder and auto-close the window.

#### WorkspaceSwitcherOverlay

- **Trigger:** Keyboard shortcut toggles a boolean binding (`isSwitcherPresented`) on the window content view.
- **Layout:** ZStack overlay with blur background. Centered card containing search field + scrollable list.
- **Props/Bindings:** `isPresented: Binding<Bool>`, reads workspaces from WorkspaceManager environment object, calls `switchToWorkspace` on selection.
- **States:** Empty query (shows all workspaces sorted by recency or creation), filtered (shows fuzzy-matched results), no results (shows empty state message).

---

## 10. Type Definitions

### Workspace

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Stable unique identifier |
| name | String | Display name |
| defaultWorkingDirectory | URL? | Optional default directory for new panes |
| spaces | [Space] | Ordered collection of spaces |
| activeSpaceID | UUID | Currently focused space |
| createdAt | Date | Creation timestamp |

### WorkspaceManager (observable state)

| Field | Type | Description |
|-------|------|-------------|
| workspaces | [Workspace] | All workspaces in order |
| windowWorkspaceMap | [NSWindow.ID: UUID] | Window-to-workspace mapping |
| activeWorkspaceID | UUID? | The workspace in the frontmost window |

### FuzzyMatchResult

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Workspace ID |
| name | String | Workspace name |
| score | Int | Match score (higher = better) |
| matchedRanges | [Range of String.Index] | Character ranges that matched, for highlighting in the UI |

---

## 11. Navigation

### 11.1 Keyboard Shortcuts (Defaults)

| Action | Shortcut | Scope |
|--------|----------|-------|
| Open workspace switcher | Cmd+Shift+W | Global (any window) |
| Create new workspace | Cmd+Shift+N | Global |
| Close/delete workspace | Cmd+Shift+Backspace | Current window's workspace |
| Rename workspace | None by default (context menu or switcher action) | -- |

Shortcuts should be registered via the main menu bar (built in `AtermAppDelegate` or via SwiftUI `.commands { }` if using a hybrid App scene), making them discoverable via Help > Search. The `WorkspaceWindowController` can also register shortcuts as `NSEvent` local monitors for window-scoped actions.

### 11.2 Navigation Flow

```
Any window
  |-- Cmd+Shift+W --> Workspace Switcher Overlay
  |     |-- type to filter, Enter to select --> brings target workspace window to front
  |     |-- Escape --> dismisses overlay
  |
  |-- Cmd+Shift+N --> Name input dialog
  |     |-- Enter with name --> creates workspace, opens new window, focuses it
  |     |-- Escape --> cancels
  |
  |-- Cmd+Shift+Backspace --> Confirmation (if foreground processes) --> deletes workspace, closes window
  |     |-- if last workspace: app quits (M5 quit flow serializes state first)
```

---

## 12. Permissions and Security

No new permissions required for M4. File system access for default working directories uses standard sandbox-allowed paths. If the app is not sandboxed (developer tool, not App Store), all local directories are accessible.

Client-side guards:
- Validate that a `defaultWorkingDirectory` exists and is a directory before setting it. On pane creation, if the resolved directory no longer exists, fall back to `$HOME` and log a warning.
- When the last workspace is deleted, the app quits (per FR-05 cascading close). The M5 quit flow still applies.

---

## 13. Performance Considerations

| Concern | Mitigation |
|---------|------------|
| Fuzzy search latency | With < 100 workspaces, brute-force fuzzy match on every keystroke is negligible (< 1ms). No debouncing needed. |
| Window creation overhead | Opening a new NSWindow + SwiftUI view hierarchy takes ~50-100ms. Shell spawn is async and overlaps. Acceptable. |
| Memory per workspace | Each workspace holds references to spaces/tabs/panes. No data is duplicated. A workspace with no visible window could release its Metal resources (optimization for M7, not M4). |
| Workspace switching latency | Switching is just bringing an existing window to front (NSWindow.orderFront). Near-instant. |

---

## 14. Migration and Deployment

### 14.1 No Persistence Migration in M4

M4 does not include persistence (that is M5). However, the Workspace data model should be designed with `Codable` conformance from the start so M5 can serialize it without model changes. Include a `schemaVersion` constant in the model file.

### 14.2 Feature Flag

No feature flag needed -- M4 is the first milestone where workspaces exist. Before M4, the app operates as a single implicit workspace. M4 transitions to explicit workspace management. The migration path: on first launch after M4 is integrated, if no workspace state exists, create a single "default" workspace containing whatever spaces/tabs/panes are currently open.

### 14.3 Rollback

Since there is no persisted state yet, rollback means reverting to the M3 codebase. No data migration concerns.

---

## 15. Implementation Phases

### Phase 1: Workspace Data Model and Manager

- Define `Workspace` struct with all fields, `Codable` conformance.
- Extend Space model with `defaultWorkingDirectory` field.
- Implement `WorkspaceManager` with create, rename, delete operations.
- Implement working directory resolution function.
- Unit tests for all manager operations and directory resolution.
- **Deliverable:** Workspace model exists and is testable in isolation. No UI yet.

### Phase 2: Multi-Window Support (AppKit + NSHostingView)

- Implement `WorkspaceWindowController` (NSWindowController subclass) that creates an NSWindow and sets its contentView to `NSHostingView(rootView: WorkspaceWindowContent(...))`.
- Implement `WindowCoordinator` with `openWindow(for:)`, `closeWindow(for:)`, `bringToFront(for:)`.
- Implement `AtermAppDelegate` with `applicationShouldTerminate(_:)` for quit handling.
- Implement `WorkspaceWindowContent` as the root SwiftUI view per window.
- Wire up `WindowCoordinator` to workspace creation/deletion in `WorkspaceManager`.
- Handle window close (red button) via `NSWindowDelegate.windowShouldClose(_:)` with workspace cleanup.
- Implement last-workspace-close behavior: when the last workspace closes, the app quits via `NSApplication.shared.terminate(nil)`. The M5 quit flow (serialize state) still applies.
- Window title set via `window.title = workspace.name`, live-updated on rename.
- **Deliverable:** User can create multiple workspaces, each in its own window. No switcher yet; relies on macOS window management (Cmd+`) to switch.

### Phase 3: Workspace Indicator

- Implement `WorkspaceIndicatorView` showing workspace name + active space name in the toolbar.
- Live update when workspace or space is renamed.
- **Deliverable:** User always sees their current context in the title bar.

### Phase 4: Fuzzy Search and Workspace Switcher

- Implement `FuzzyMatch.swift` with scoring algorithm.
- Unit tests for fuzzy matching (exact match, subsequence, no match, case sensitivity, boundary bonuses).
- Implement `WorkspaceSwitcherOverlay` with search field, results list, keyboard navigation.
- Wire up Cmd+Shift+W to toggle the overlay.
- Implement Enter-to-switch (brings target window to front).
- Implement drag-and-drop reordering of workspace rows in the switcher (via Transferable/onDrag/onDrop).
- Implement WorkspaceDragItem with custom UTType.
- Disable drag when search query is active (filtered list).
- Accessibility labels on all switcher elements.
- **Deliverable:** Full workspace switching and reordering workflow via keyboard and mouse.

### Phase 5: Default Working Directory

- Add UI for setting default working directory on workspace (context menu or inline edit in switcher).
- Add UI for setting default working directory on space (context menu on space bar).
- Wire directory resolution into pane creation flow.
- **Deliverable:** New panes respect the workspace/space default directory hierarchy.

---

## 16. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| AppKit/SwiftUI interop edge cases -- `NSHostingView` focus management, keyboard shortcut routing between AppKit responder chain and SwiftUI `@FocusState` | Medium -- could cause focus bugs in terminal panes | Low | Set `NSHostingView` as `initialFirstResponder`. Test keyboard input routing thoroughly in Phase 2. Ghostty uses this same pattern successfully. |
| Window close (red button) vs. app quit semantics -- macOS convention is that closing the last window does not quit the app, but aterm follows FR-05 cascading close | Low -- developer tools commonly quit on last window close (e.g., Terminal.app) | Low | Closing the last workspace quits the app via `NSApplication.shared.terminate(nil)`. The M5 quit flow (serialize state) still runs. This matches Terminal.app behavior and FR-05 requirements. |
| Keyboard shortcut conflicts -- Cmd+Shift+W may conflict with other macOS apps or system shortcuts | Low -- only affects default binding | Low | Make it configurable in M6. Document the default clearly. |
| Workspace switcher focus management -- ensuring the text field gets focus when the overlay appears, and focus returns correctly when dismissed | Medium -- broken focus is very annoying in a keyboard-driven app | Medium | Use `@FocusState` with `onAppear` to grab focus. Test extensively with keyboard-only usage. |
| Race conditions between window lifecycle and workspace deletion -- user could close window while workspace is being deleted programmatically | Low -- data inconsistency | Low | Funnel all mutations through WorkspaceManager on `@MainActor`. Use workspace ID lookups with nil-coalescing guards in views. |

---

## 17. Open Technical Questions

| # | Question | Context | Impact if Unresolved |
|---|----------|---------|---------------------|
| 1 | Should the workspace switcher support creating a new workspace inline (e.g., typing a name that does not match any existing workspace and pressing a "Create" action)? | PRD Open Question #4 asks this. The switcher UX would need a "Create new" row or shortcut. | Low -- can be added as a follow-up without architectural changes. For M4, create-workspace can remain a separate shortcut (Cmd+Shift+N). |
| ~~2~~ | ~~What is the exact SwiftUI window management API surface on macOS 26?~~ **Resolved:** Using AppKit `NSWindowController` + `NSHostingView` instead of SwiftUI `WindowGroup(for:)`. Research showed `WindowGroup(for:)` has persistent reliability issues (dismissWindow failures, phantom windows, toolbar bugs). AppKit gives deterministic window lifecycle control. This is the same pattern Ghostty uses in production. | Resolved. | Resolved. |
| 3 | Should workspaces that have no window remain in memory (background workspaces), or must every workspace have an open window? | Affects memory usage and the switcher's behavior. If background workspaces exist, the switcher must distinguish "open" vs. "background". | Medium -- for M4, simplest approach is every workspace has a window. Background workspaces can be added in M5 when persistence exists. |
| 4 | How should the app handle the user setting a default working directory to a path that is later deleted or unmounted? | Relevant for both workspace and space defaults. | Low -- validate at pane creation time and fall back to $HOME. Already described in the resolution logic. |
| 5 | Should workspace reorder be part of M4 or deferred? | **Resolved:** Workspace reorder via drag-and-drop is now in M4 scope (Section 7). Implemented in the workspace switcher overlay using SwiftUI's Transferable/onDrag/onDrop pattern. | Resolved. |
