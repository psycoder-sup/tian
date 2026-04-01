# SPEC: Workspace Sidebar Redesign

**Based on:** docs/feature/workspace-sidebar/workspace-sidebar-prd.md v1.1
**Author:** CTO Agent
**Date:** 2026-04-01
**Version:** 2.0
**Status:** Updated for multi-workspace management (in-place switching)

---

## 1. Overview

This spec covers the replacement of aterm's three horizontal navigation components (WorkspaceIndicatorView, SpaceBarView, WorkspaceSwitcherOverlay) with a single glassmorphism sidebar that provides full workspace and space management. The sidebar displays **all workspaces** belonging to the current window as top-level disclosure groups, each containing its spaces as child rows. Workspaces are owned per-window via a new `WorkspaceCollection` type, and switching between workspaces happens **in-place** within the same window (no window-per-workspace mapping).

The sidebar uses a ZStack overlay layout where the sidebar panel sits behind the content layer, with the content offset via leading padding. It supports expanded (284pt) and collapsed (0pt, fully hidden) modes. The tab bar (`TabBarView`) spans the full window width in a top-level row alongside the sidebar toggle button and traffic light clearance. The terminal surface freeze-and-reflow strategy ensures clean animations without visual artifacts.

The implementation touches five layers of the codebase: the **data model** (new `WorkspaceCollection`, modified `WorkspaceManager`), the **input system** (`KeyAction` cases and bindings), the **view hierarchy** (sidebar views, restructured `WorkspaceWindowContent`), the **window controller** (owns `WorkspaceCollection`, keyboard actions), and the **removal of legacy components**.

### 1.1 Architectural Change: Per-Window Workspaces

**Before (v1.x):** Each workspace maps 1:1 to an NSWindow. `WorkspaceManager` owns all workspaces globally. Switching workspaces brings another window to front.

**After (v2.0):** Each window owns a `WorkspaceCollection` containing multiple workspaces. The sidebar shows all workspaces for the current window. Switching workspaces changes which workspace the window displays, in-place. `WorkspaceManager` is simplified to app-level coordination.

```
Before:                              After:
WorkspaceManager                     Window 1
  Workspace A → Window 1               WorkspaceCollection
  Workspace B → Window 2                 Workspace A (active)
  Workspace C → Window 3                 Workspace B
                                     Window 2
                                       WorkspaceCollection
                                         Workspace C (active)
                                         Workspace D
```

---

## 2. State Management

### 2.1 SidebarState (Done)

A `@Observable` class manages per-window sidebar state. Each `SidebarContainerView` owns one instance via `@State`.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| mode | SidebarMode (enum: .expanded, .collapsed) | .expanded | Current sidebar display mode |
| isAnimating | Bool | false | True during the toggle animation. Used to freeze terminal surface sizing. |
| focusTarget | SidebarFocusTarget (enum: .terminal, .sidebar) | .terminal | Tracks keyboard focus location. |
| renamingSpaceID | UUID? | nil | ID of the space currently being renamed inline. |

**SidebarMode enum** has two cases: `.expanded` and `.collapsed`. A computed property `width` returns 284.0 for expanded, 0.0 for collapsed.

**SidebarFocusTarget enum** has two cases: `.terminal` and `.sidebar`.

**Computed property:** `isExpanded: Bool` returns `mode == .expanded`.

**Why a separate class instead of inline `@State` properties:** The sidebar state is referenced by the sidebar content views, the toggle animation logic, and the keyboard monitor. Grouping it into a single observable object makes dependency tracking cleaner and avoids prop-drilling multiple bindings.

### 2.2 New Observable: WorkspaceCollection (Phase 2)

A new `@Observable` class manages per-window workspace ownership. Each `WorkspaceWindowController` owns one instance. Follows the `SpaceCollection` pattern.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| workspaces | [Workspace] | (initialized with one default workspace) | Ordered list of workspaces in this window |
| activeWorkspaceID | UUID | (first workspace's ID) | Currently displayed workspace |
| shouldQuit | Bool | false | Set when last workspace is removed and `onEmpty` is nil |
| onEmpty | (() -> Void)? | nil | Called when last workspace is removed. If set, `shouldQuit` is not used. |
| workspaceCounter | Int | 1 | Counter for auto-naming ("Workspace 2", "Workspace 3", ...) |

**Computed properties:**
- `activeWorkspace: Workspace?` — returns workspace matching `activeWorkspaceID`
- `activeSpaceCollection: SpaceCollection?` — shortcut for `activeWorkspace?.spaceCollection`

**Methods** (mirror `SpaceCollection` pattern):

| Method | Description |
|--------|-------------|
| `createWorkspace(name:workingDirectory:)` | Increment counter, create workspace, wire cascading close, append, set as active. |
| `removeWorkspace(id:)` | Cleanup PTY resources, remove from array. If empty: call `onEmpty` or set `shouldQuit`. Otherwise: activate adjacent (prefer left). |
| `activateWorkspace(id:)` | Guard existence, set `activeWorkspaceID`. |
| `nextWorkspace()` | Circular navigation to next workspace. |
| `previousWorkspace()` | Circular navigation to previous workspace. |
| `reorderWorkspace(from:to:)` | Validate indices, reorder array. |
| `renameWorkspace(id:newName:)` | Validate name, update `workspace.name`. Returns Bool. |

**Cascading close chain:**
```
Last tab closes (shell exits)
  → SpaceModel.onEmpty → SpaceCollection.removeSpace()
  → Last space removed → Workspace.onEmpty
  → WorkspaceCollection.removeWorkspace()
  → Last workspace removed → onEmpty callback
  → Window closes
  → Last window → app quits (applicationShouldTerminateAfterLastWindowClosed)
```

**Why a new type instead of reusing WorkspaceManager:** `WorkspaceCollection` is per-window state (each window independently manages its workspaces). `WorkspaceManager` was global. The per-window model enables in-place workspace switching without cross-window coordination.

### 2.3 Modified: WorkspaceManager (Phase 2)

`WorkspaceManager` is **simplified** from workspace owner to app-level coordinator:

| Field | Type | Description |
|-------|------|-------------|
| activeWorkspaceID | UUID? | Globally active workspace (the one in the key window). Updated by `windowDidBecomeKey`. |

**Removed responsibilities:**
- No longer owns `[Workspace]` — workspaces live in per-window `WorkspaceCollection`s
- No longer has `createWorkspace`, `deleteWorkspace`, `switchToWorkspace`, `reorderWorkspace`, `renameWorkspace` — these move to `WorkspaceCollection`
- No longer has `shouldQuit` — window close cascade handles app quit
- No longer has `windowCoordinator` reference — `WindowCoordinator` operates independently

**Retained responsibilities:**
- Tracks `activeWorkspaceID` for app-level concerns (e.g., which workspace is globally focused)
- May provide utility methods like `setDefaultWorkingDirectory(spaceID:)` that search across all windows

**Alternative:** `WorkspaceManager` could be removed entirely, with `activeWorkspaceID` moved to `WindowCoordinator`. The spec does not prescribe which approach; the implementation should choose the cleaner option.

### 2.4 Existing State (No Changes)

The following existing types are read by the sidebar but not modified:

- `Workspace` (id, name, spaceCollection, onEmpty, cleanup) — unchanged
- `SpaceCollection` (spaces, activeSpaceID, activateSpace, createSpace, removeSpace, reorderSpace) — unchanged
- `SpaceModel` (id, name) — unchanged

---

## 3. Type Definitions

### 3.1 New Types

| Type | Kind | Location | Status | Description |
|------|------|----------|--------|-------------|
| SidebarMode | enum | `aterm/View/Sidebar/SidebarState.swift` | Done | Two cases: `.expanded` (284pt), `.collapsed` (0pt). Computed `width: CGFloat` property. |
| SidebarFocusTarget | enum | `aterm/View/Sidebar/SidebarState.swift` | Done | Two cases: `.terminal`, `.sidebar`. |
| SidebarState | @Observable class | `aterm/View/Sidebar/SidebarState.swift` | Done | Per-window sidebar state as described in section 2.1. |
| WorkspaceCollection | @Observable class | `aterm/Models/WorkspaceCollection.swift` | Phase 2 | Per-window workspace ownership as described in section 2.2. Follows `SpaceCollection` pattern. |
| SidebarContainerView | SwiftUI View | `aterm/View/Sidebar/SidebarContainerView.swift` | Done (needs Phase 2 update) | Top-level ZStack wrapping the sidebar panel and content layer. |
| SidebarPanelView | SwiftUI View | `aterm/View/Sidebar/SidebarPanelView.swift` | Done (needs Phase 2 update) | The sidebar glass panel with workspace content and new workspace button. |
| SidebarToggleButton | SwiftUI View | `aterm/View/Sidebar/SidebarToggleButton.swift` | Done | Standalone toggle button using `sidebar.left` SF Symbol. |
| SidebarExpandedContentView | SwiftUI View | `aterm/View/Sidebar/SidebarExpandedContentView.swift` | Done (needs Phase 2 update) | Workspace tree with disclosure groups, space rows, keyboard navigation. |
| SidebarSpaceRowView | SwiftUI View | `aterm/View/Sidebar/SidebarSpaceRowView.swift` | Done | A single space row. Handles selection, hover, keyboard highlight. |
| SidebarWorkspaceHeaderView | SwiftUI View | `aterm/View/Sidebar/SidebarWorkspaceHeaderView.swift` | Done (needs Phase 3 update) | Workspace disclosure header. Needs context menu for rename/close. |

### 3.2 Modified Types

| Type | Location | Modification | Status |
|------|----------|-------------|--------|
| WorkspaceManager | `aterm/Models/WorkspaceManager.swift` | Simplified to app-level coordinator. Remove workspace ownership, CRUD methods, `shouldQuit`, `windowCoordinator`. Retain `activeWorkspaceID`. | Phase 2 |
| WindowCoordinator | `aterm/WindowManagement/WindowCoordinator.swift` | Key by window identity instead of workspace ID. `openWindow()` creates window with `WorkspaceCollection`. `closeWindow()` cleans up all workspaces. | Phase 2 |
| WorkspaceWindowController | `aterm/WindowManagement/WorkspaceWindowController.swift` | Owns `WorkspaceCollection` instead of single workspace reference. Keyboard monitor delegates workspace ops to collection. Displays active workspace. | Phase 2 |
| WorkspaceWindowContent | `aterm/View/Workspace/WorkspaceWindowContent.swift` | Receives `WorkspaceCollection` instead of single `workspaceID`. Passes collection to sidebar. Displays active workspace's space collection. | Phase 2 |
| SidebarContainerView | `aterm/View/Sidebar/SidebarContainerView.swift` | Receives `WorkspaceCollection`. Tab bar and terminal area display active workspace's space collection. | Phase 2 |
| SidebarExpandedContentView | `aterm/View/Sidebar/SidebarExpandedContentView.swift` | Reads from `WorkspaceCollection` instead of `WorkspaceManager`. Workspace activation calls `workspaceCollection.activateWorkspace(id:)`. | Phase 2 |
| SidebarPanelView | `aterm/View/Sidebar/SidebarPanelView.swift` | Passes `WorkspaceCollection` to content. New workspace button delegates to collection. | Phase 2 |
| KeyAction | `aterm/Input/KeyAction.swift` | `.newWorkspace` now means "create in current window". Legacy `.toggleWorkspaceSwitcher` kept for compilation (Phase 5 removes). | Phase 2 |
| KeyBindingRegistry | `aterm/Input/KeyBindingRegistry.swift` | Changed to `[KeyAction: [KeyBinding]]`. `.toggleSidebar` multi-binding (Cmd+Shift+S, Cmd+Shift+W). Cmd+0 special case for `.focusSidebar`. | Done |

### 3.3 Removed Types (Phase 5)

| Type | Location | Reason |
|------|----------|--------|
| WorkspaceIndicatorView | `aterm/View/Workspace/WorkspaceIndicatorView.swift` | Replaced by sidebar workspace header |
| SpaceBarView | `aterm/View/SpaceBar/SpaceBarView.swift` | Replaced by sidebar space list |
| SpaceBarItemView | `aterm/View/SpaceBar/SpaceBarItemView.swift` | Replaced by SidebarSpaceRowView |
| WorkspaceSwitcherOverlay | `aterm/View/Workspace/WorkspaceSwitcherOverlay.swift` | Replaced by sidebar workspace management |
| SwitcherSearchField | `aterm/View/Workspace/WorkspaceSwitcherOverlay.swift` (private) | Removed with overlay |
| WorkspaceSwitcherRow | `aterm/View/Workspace/WorkspaceSwitcherOverlay.swift` (private) | Removed with overlay |
| Notification.Name.toggleWorkspaceSwitcher | `aterm/View/Workspace/WorkspaceWindowContent.swift` | Replaced by sidebar toggle notification |

---

## 4. View Hierarchy Changes

### 4.1 Current View Hierarchy (Before Sidebar)

```
WorkspaceWindowContent
  VStack(spacing: 0)
    HStack(spacing: 0)                    -- 28pt bar
      WorkspaceIndicatorView
      Divider
      SpaceBarView
    Divider
    TabBarView                            -- 30pt bar
    ZStack                                -- terminal content
      ForEach(spaces) -> ForEach(tabs)
        SplitTreeView
    .overlay
      WorkspaceSwitcherOverlay (conditional)
```

### 4.2 New View Hierarchy (Phase 1 — Current Implementation)

```
WorkspaceWindowContent(workspaceID)
  SidebarContainerView(workspaceID, spaceCollection)
    ZStack(alignment: .topLeading)
      SidebarPanelView                    -- 284pt or 0pt, animated
        .glassEffect(.regular) background
        VStack(spacing: 0)
          Spacer(40pt)
          SidebarExpandedContentView      -- workspace tree
          Spacer
          + New Workspace button
      VStack(spacing: 0)                  -- content layer
        HStack(spacing: 6)               -- 44pt tab bar row
          HStack(spacing: 6)             -- traffic light clearance + toggle
            Color.clear(width: 80)       -- traffic light spacer
            SidebarToggleButton          -- sidebar.left icon
          .frame(width: max(sidebarWidth, 104))
          TabBarView                     -- tabs for active space
        .frame(height: 44)
        ZStack                           -- terminal content
          .padding(.leading, sidebarWidth)
          ForEach(spaces) -> ForEach(tabs)
            SplitTreeView
```

### 4.3 Target View Hierarchy (Phase 2 — WorkspaceCollection)

```
WorkspaceWindowContent(workspaceCollection)
  SidebarContainerView(workspaceCollection)
    ZStack(alignment: .topLeading)
      SidebarPanelView(workspaceCollection)
        .glassEffect(.regular) background
        VStack(spacing: 0)
          Spacer(40pt)
          SidebarExpandedContentView(workspaceCollection)
            ScrollView
              VStack
                ForEach(workspaceCollection.workspaces)
                  SidebarWorkspaceHeaderView   -- disclosure + name + "+" button
                  if disclosed:
                    ForEach(workspace.spaces)
                      SidebarSpaceRowView      -- dot + name + highlight
                    + New Space button (inside header hover)
          Spacer
          + New Workspace button
      VStack(spacing: 0)                  -- content layer
        HStack(spacing: 6)               -- 44pt tab bar row
          HStack(spacing: 6)
            Color.clear(width: 80)
            SidebarToggleButton
          .frame(width: max(sidebarWidth, 104))
          TabBarView                     -- tabs for ACTIVE workspace's active space
        .frame(height: 44)
        ZStack                           -- terminal content
          .padding(.leading, sidebarWidth)
          ForEach(activeWorkspace.spaces) -> ForEach(tabs)
            SplitTreeView
```

### 4.4 Key Structural Changes

1. **`WorkspaceWindowContent`** receives `WorkspaceCollection` instead of a single `workspaceID`. It passes the collection to `SidebarContainerView`.

2. **`SidebarContainerView`** observes `workspaceCollection.activeWorkspaceID` to determine which `spaceCollection` to display in the tab bar and terminal ZStack. When the active workspace changes, the tab bar and terminal area update to show the new workspace's content.

3. **`SidebarExpandedContentView`** reads `workspaceCollection.workspaces` (per-window list) instead of `workspaceManager.workspaces` (global list). Activating a workspace calls `workspaceCollection.activateWorkspace(id:)` for in-place switching.

4. **Terminal ZStack** iterates the active workspace's space collection. When the user switches workspaces via the sidebar, the entire terminal area transitions to the new workspace's spaces/tabs.

---

## 5. Component Specifications

### 5.1 SidebarContainerView

**File:** `aterm/View/Sidebar/SidebarContainerView.swift`

**Inputs (Phase 2):**
- `workspaceCollection: WorkspaceCollection`

**State:**
- `@State private var sidebarState = SidebarState()`
- `@State private var lastContainerSize: CGSize = .zero`
- `@State private var nsWindow: NSWindow?`

**Derived properties:**
- `activeWorkspace` — `workspaceCollection.activeWorkspace`
- `spaceCollection` — `activeWorkspace?.spaceCollection`

**Layout:**
- `ZStack(alignment: .topLeading)` containing:
  1. `SidebarPanelView(workspaceCollection:sidebarState:)` with `.frame(width: sidebarState.mode.width)`.
  2. Content `VStack(spacing: 0)`:
     - Tab bar row: traffic light clearance + `SidebarToggleButton` + `TabBarView` for active space.
     - Terminal ZStack: iterates `spaceCollection.spaces` → tabs → `SplitTreeView`. Padded `.leading` by sidebar width.
- `.ignoresSafeArea(.container, edges: .top)`.

**Reactive behavior:**
- Observes `workspaceCollection.activeWorkspaceID` changes. When the active workspace changes, the tab bar and terminal ZStack automatically update because they read from `workspaceCollection.activeWorkspace.spaceCollection`.
- Container size propagation: on workspace switch, the new active tab's `paneViewModel.containerSize` is set to `lastContainerSize`.

**Animation behavior (unchanged from Phase 1):**
- On sidebar toggle, `withAnimation(.easeInOut(duration: 0.2))` animates the width.
- During animation, `GeometryReader.onChange` skips `handleContainerSizeChange`.
- After animation, delivers final size to terminal surfaces.

**Sidebar toggle notification:**
- Listens for `Notification.Name.toggleSidebar` (scoped to window ID) to toggle sidebar.
- Listens for `Notification.Name.focusSidebar` (scoped to window ID) to expand and focus sidebar.

**Focus management:**
- Observes `sidebarState.focusTarget`. When it changes to `.terminal`, calls `returnFocusToTerminal()` which makes the active tab's focused pane the first responder.

### 5.2 SidebarPanelView

**File:** `aterm/View/Sidebar/SidebarPanelView.swift`

**Inputs:**
- `workspaceCollection: WorkspaceCollection`
- `sidebarState: SidebarState`

**Layout:**
- `VStack(spacing: 0)`:
  1. `Spacer().frame(height: 40)` — clearance below titlebar
  2. `SidebarExpandedContentView(workspaceCollection:sidebarState:)`
  3. `Spacer()`
  4. New workspace button (bottom of sidebar)
- `.frame(maxWidth: .infinity, maxHeight: .infinity)`
- `.glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))`
- `.padding(EdgeInsets(top: 4, leading: 4, bottom: 6, trailing: 4))`

**New workspace button:**
- `Button` with `Image(systemName: "plus")` + `Text("New Workspace")`.
- On click: calls `workspaceCollection.createWorkspace(name: "Workspace \(counter)")`.
- After creation, the new workspace becomes active (in-place switch), its disclosure is opened, and the sidebar shows it.
- Frame: 28pt height, `.horizontal` padding 12pt, bottom padding 8pt.

**Accessibility:**
- Container: `.accessibilityElement(children: .contain)`, `.accessibilityLabel("Workspace sidebar")`
- New workspace button: `.accessibilityLabel("New workspace")`

### 5.3 SidebarToggleButton

**File:** `aterm/View/Sidebar/SidebarToggleButton.swift`

**Inputs:**
- `workspaceID: UUID` (used to scope notifications — will change to window ID in Phase 2)

**Behavior:**
- Shows the `sidebar.left` SF Symbol. Clicking posts `Notification.Name.toggleSidebar`.
- Positioned in the tab bar row, to the right of the traffic light clearance area. Always visible regardless of sidebar state.

**Dimensions:**
- Icon: `.font(.system(size: 13, weight: .medium))`, `.foregroundStyle(.secondary)`.
- `.buttonStyle(.plain)`.

**Accessibility:**
- `.accessibilityLabel("Toggle sidebar")`

### 5.4 SidebarExpandedContentView

**File:** `aterm/View/Sidebar/SidebarExpandedContentView.swift`

**Inputs (Phase 2):**
- `workspaceCollection: WorkspaceCollection`
- `sidebarState: SidebarState`

**State:**
- `@State private var selectedIndex: Int?` — keyboard navigation index
- `@State private var disclosedWorkspaces: Set<UUID>` — which workspace disclosure groups are open

**Flat item model:**
- A private `SidebarItem` enum with cases `.workspaceHeader(Workspace)` and `.spaceRow(Workspace, SpaceModel)`.
- A computed `flatItems: [SidebarItem]` property iterates `workspaceCollection.workspaces`, appending headers and (if disclosed) space rows.

**Layout:**
- `ScrollView(.vertical, showsIndicators: false)` containing `VStack(alignment: .leading, spacing: 0)`:
  - `ForEach(flatItems)` producing:
    - `.workspaceHeader` → `SidebarWorkspaceHeaderView`
    - `.spaceRow` → `SidebarSpaceRowView`

**Active workspace highlight:**
- The active workspace's header is visually distinguished (bold name, accent dot or background).
- Space rows for the active workspace show the active space with accent highlight.

**Workspace activation (in-place switching):**
- When user clicks a space row in a non-active workspace: call `workspaceCollection.activateWorkspace(id:)` first, then `spaceCollection.activateSpace(id:)`. This switches the window to display that workspace and selects the space.
- When user clicks a space row in the active workspace: just call `spaceCollection.activateSpace(id:)`.
- After any space selection: set `sidebarState.focusTarget = .terminal`.

**Disclosure behavior:**
- On appear, the active workspace's disclosure is opened.
- When a workspace is activated (via space click or keyboard), its disclosure is opened if not already.
- Left/right arrow keys on a workspace header collapse/expand disclosure.

**Keyboard navigation (when focusTarget == .sidebar):**
- Up/Down arrow keys move through flat items (workspace headers + space rows).
- Enter or Space on a space row activates that space and returns focus to terminal.
- Enter or Space on a workspace header toggles its disclosure.
- Left arrow on workspace header collapses disclosure. Right arrow expands it.
- Escape returns `sidebarState.focusTarget` to `.terminal`.

**Implementation:** Uses a hidden `SidebarKeyboardResponder` (`NSViewRepresentable`) that accepts first responder when `focusTarget == .sidebar` and forwards key events to callback closures.

### 5.5 SidebarWorkspaceHeaderView

**File:** `aterm/View/Sidebar/SidebarWorkspaceHeaderView.swift`

**Inputs:**
- `workspace: Workspace`
- `isExpanded: Bool`
- `isActive: Bool` — whether this is the active workspace in the window
- `isKeyboardSelected: Bool`
- Closure `onToggleDisclosure: () -> Void`
- Closure `onAddSpace: () -> Void`
- Closure `onRename: () -> Void` (Phase 3)
- Closure `onClose: () -> Void` (Phase 3)

**Layout:**
- `HStack(spacing: 6)`:
  1. Disclosure triangle: `Image(systemName: "chevron.right")` rotated 90 degrees when expanded. Animated rotation via `.rotationEffect(.degrees(isExpanded ? 90 : 0))` with `.animation(.easeInOut(duration: 0.15))`.
  2. Workspace name: `Text(workspace.name)` with `.font(.system(size: 12, weight: .semibold))`, `.foregroundStyle(.primary)`, `.lineLimit(1)`.
  3. Spacer
  4. "+" button (visible on hover or keyboard selection): calls `onAddSpace`.
- Frame height: 28pt.
- Horizontal padding: 12pt.
- Click on the entire row toggles disclosure.

**Active workspace styling:**
- When `isActive`: name uses `.foregroundStyle(.primary)` with `.fontWeight(.bold)`, or a subtle accent background.
- When not active: name uses `.foregroundStyle(.secondary)`.

**Context menu (Phase 3):**
- "Rename" — triggers inline rename via `onRename`.
- "Close Workspace" — calls `onClose` which maps to `workspaceCollection.removeWorkspace(id:)`.

**Accessibility:**
- `.accessibilityLabel("\(workspace.name), \(workspace.spaceCollection.spaces.count) spaces, \(isExpanded ? "expanded" : "collapsed")")`

### 5.6 SidebarSpaceRowView

**File:** `aterm/View/Sidebar/SidebarSpaceRowView.swift`

**Inputs:**
- `space: SpaceModel`
- `isActive: Bool` — true when this is the active space in the active workspace
- `isKeyboardSelected: Bool`
- `isRenaming: Binding<Bool>` (Phase 3, bound to `sidebarState.renamingSpaceID == space.id`)
- Closure `onSelect: () -> Void`
- Closure `onClose: () -> Void` (Phase 3)

**Layout:**
- `HStack(spacing: 6)`:
  1. If `isActive`: accent-colored dot (4pt circle, `.accentColor`). Otherwise: clear 4pt circle.
  2. Space name: `Text(space.name)` (or `InlineRenameView` when renaming).
- Frame height: 26pt.
- Left padding: 28pt (12pt sidebar padding + 16pt disclosure indent).
- Right padding: 12pt.

**Active state highlight:**
- When `isActive`: `RoundedRectangle(cornerRadius: 4)` filled with `.accentColor.opacity(0.15)`.

**Hover effect:**
- `.onHover` tracks hover state. On hover (when not active): `.quaternary` fill background.

**Keyboard selection:**
- When `isKeyboardSelected`: 1px accent stroke overlay.

**Interactions:**
- Single click/tap: calls `onSelect`.
- Double click: enters rename mode (Phase 3).

**Context menu (Phase 3):**
- "Rename" — sets `sidebarState.renamingSpaceID = space.id`.
- "Close Space" — calls `onClose` which maps to `spaceCollection.removeSpace(id: space.id)`.

**Accessibility:**
- `.accessibilityLabel(space.name)`
- `.accessibilityValue(isActive ? "selected" : "not selected")`

### 5.7 SidebarCollapsedContentView — REMOVED

The collapsed icon-rail concept has been removed. Collapsed mode is now 0pt (fully hidden). The `SidebarToggleButton` in the tab bar row provides the re-expand affordance, remaining visible at all times.

### 5.8 SidebarAddSpaceButton (Phase 2)

This is integrated into `SidebarWorkspaceHeaderView` as the "+" button that appears on hover/keyboard selection, not a separate file.

**Behavior:**
- On click: calls `onAddSpace()` which maps to `workspace.spaceCollection.createSpace(workingDirectory: ...)`. After creation, the new space becomes active and `sidebarState.renamingSpaceID` is set to the new space's ID to trigger inline rename.

**Accessibility:**
- `.accessibilityLabel("New space in \(workspace.name)")`

---

## 6. Key Binding Changes

### 6.1 KeyAction Cases

| Case | Description | Status |
|------|-------------|--------|
| `.toggleSidebar` | Toggle sidebar between expanded and collapsed modes | Done |
| `.focusSidebar` | Enter keyboard focus into the sidebar (Cmd+0) | Done |
| `.newWorkspace` | Create new workspace **in the current window** (changed from opening new window) | Phase 2 (behavior change) |
| `.closeWorkspace` | Close the active workspace in the current window. Switch to next; close window if last. | Phase 2 (behavior change) |
| `.toggleWorkspaceSwitcher` | Legacy — no binding maps to it. Removed in Phase 5. | Done (no-op) |

### 6.2 Key Binding Summary

| Shortcut | Action | Notes |
|----------|--------|-------|
| Cmd+Shift+S | Toggle sidebar | Primary toggle |
| Cmd+Shift+W | Toggle sidebar | Alternate toggle (repurposed from workspace switcher) |
| Cmd+0 | Focus sidebar | Enter keyboard navigation in sidebar |
| Cmd+Shift+N | Create new workspace in current window | **Changed:** was "open new window" |
| Cmd+Shift+Backspace | Close active workspace | **Changed:** switches to next workspace instead of closing window |
| Cmd+Shift+Right | Next space | Unchanged |
| Cmd+Shift+Left | Previous space | Unchanged |
| Cmd+Shift+T | New space | Unchanged |

**New window:** No dedicated keyboard shortcut. New windows are created via macOS menu (File > New Window) or Dock.

### 6.3 KeyBindingRegistry (Done)

The dictionary type is `[KeyAction: [KeyBinding]]` (array of bindings per action) to support multiple bindings for a single action.

**Bindings registered in `defaults()`:**
- `.toggleSidebar`: two bindings — `Cmd+Shift+S` and `Cmd+Shift+W`
- `.focusSidebar`: handled as a special case in `action(for:)` — `Cmd+0` is detected in the Cmd+digit block (digit 0 returns `.focusSidebar`, digits 1-9 return `.goToTab`).

### 6.4 WorkspaceWindowController Keyboard Monitor

**Updated behavior (Phase 2):**

| Action | Handler |
|--------|---------|
| `.newWorkspace` | `workspaceCollection.createWorkspace(name: "Workspace \(counter)")` — creates in current window, no new window |
| `.closeWorkspace` | `workspaceCollection.removeWorkspace(id: activeWorkspaceID)` — removes active workspace, switches to next |
| `.toggleSidebar` | Posts `Notification.Name.toggleSidebar` (unchanged) |
| `.focusSidebar` | Posts `Notification.Name.focusSidebar` (unchanged) |
| `.toggleWorkspaceSwitcher` | Returns nil (no-op, Phase 5 removes) |

**Text field bypass:** When `NSText` is the first responder, only `.toggleSidebar` and `.focusSidebar` are allowed through.

---

## 7. Focus Management

### 7.1 Default Focus: Terminal

The terminal pane is the default focus target. After most sidebar interactions, focus returns to the terminal.

### 7.2 Focus Return After Space Selection

When the user clicks a space row in the sidebar:
1. If the space is in a different workspace: `workspaceCollection.activateWorkspace(id:)` switches the window to that workspace.
2. `spaceCollection.activateSpace(id:)` selects the space.
3. `sidebarState.focusTarget` is set to `.terminal`.
4. `SidebarContainerView` observes `focusTarget` and makes the focused pane's `TerminalSurfaceView` first responder.

### 7.3 Focus Stays in Sidebar After Disclosure Toggle

Clicking the workspace disclosure triangle does not change focus. Mouse clicks on the disclosure are "fire and forget" for focus.

### 7.4 Cmd+0 Enter Sidebar Focus

1. `WorkspaceWindowController` handles `.focusSidebar` by posting notification.
2. `SidebarContainerView` receives notification, expands sidebar if collapsed, sets `sidebarState.focusTarget = .sidebar`.
3. `SidebarExpandedContentView` initializes `selectedIndex = 0` when focus target becomes `.sidebar`.
4. Arrow keys navigate, Enter activates, Escape returns to terminal.

### 7.5 Focus After Workspace Switch

When the user activates a different workspace (via sidebar click or keyboard):
1. The tab bar and terminal area update to the new workspace's content.
2. Focus returns to the terminal (new workspace's active tab's focused pane).
3. The sidebar remains in its current disclosure/scroll state.

### 7.6 Inline Rename Focus

`InlineRenameView` handles focus correctly:
- On appear, focuses the text field.
- On submit, commits the name change.
- On escape, cancels.
- After rename completes, `sidebarState.renamingSpaceID` is cleared and `focusTarget` is set to `.terminal`.

---

## 8. Animation and Layout

### 8.1 Toggle Animation (Unchanged)

The sidebar toggle between expanded and collapsed follows this sequence:

1. **Pre-animation:** `SidebarState.toggle()` sets `isAnimating = true`.
2. **Animation:** `withAnimation(.easeInOut(duration: 0.2)) { mode = (mode == .expanded ? .collapsed : .expanded) }`.
3. **During animation:** The `GeometryReader.onChange` handler skips `handleContainerSizeChange` when `isAnimating`.
4. **Post-animation:** After 0.22 seconds, `isAnimating` is set to `false`. `onChange(of: sidebarState.isAnimating)` delivers the final size to all visible terminal surfaces.

### 8.2 Debounce Rapid Toggle (Unchanged)

If `isAnimating == true`, `toggle()` returns immediately.

### 8.3 Terminal Surface Freeze Detail (Unchanged)

The freeze gates `handleContainerSizeChange` on the animation state, delivering one final `ghostty_surface_set_size` → one SIGWINCH after animation completes.

### 8.4 Workspace Switch Transition

When the active workspace changes:
- The tab bar immediately updates to show the new workspace's active space.
- The terminal ZStack immediately updates to show the new workspace's active tab's split tree.
- Container size is propagated to the new active tab's `paneViewModel.containerSize`.
- No animation is applied to the workspace switch itself (instant transition).

### 8.5 Window Auto-Resize (FR-36) — Not Yet Implemented

Planned for a future phase. Currently, sidebar toggle and workspace operations do not check window width.

---

## 9. Navigation

### 9.1 Sidebar Toggle

| Trigger | Action |
|---------|--------|
| Cmd+Shift+S | Toggle sidebar expanded/collapsed |
| Cmd+Shift+W | Toggle sidebar expanded/collapsed (alternate) |
| Toggle button click (`sidebar.left` icon) | Toggle sidebar expanded/collapsed |

### 9.2 Space Selection

| Trigger | Action |
|---------|--------|
| Click space row (same workspace) | `spaceCollection.activateSpace(id:)`, return focus to terminal |
| Click space row (different workspace) | `workspaceCollection.activateWorkspace(id:)`, then `spaceCollection.activateSpace(id:)`, return focus to terminal |
| Enter on space row (sidebar keyboard focus) | Same as click |

### 9.3 Workspace Switching (In-Place)

| Trigger | Action |
|---------|--------|
| Click space row in another workspace | Activates that workspace and space in-place |
| Click workspace header | Toggles disclosure only (does not switch workspace) |
| Keyboard Enter on workspace header | Toggles disclosure only |
| `workspaceCollection.nextWorkspace()` | Cycles to next workspace (if shortcut added) |
| `workspaceCollection.previousWorkspace()` | Cycles to previous workspace (if shortcut added) |

### 9.4 Workspace Management

| Trigger | Action |
|---------|--------|
| Cmd+Shift+N | Create new workspace in current window |
| Cmd+Shift+Backspace | Close active workspace (switch to next; close window if last) |
| "New Workspace" button in sidebar | Create new workspace in current window |
| Context menu > Close Workspace | Close that workspace |
| Context menu > Rename | Enter inline rename for workspace name |

### 9.5 Existing Space Shortcuts (Unchanged)

| Shortcut | Action | Sidebar effect |
|----------|--------|----------------|
| Cmd+Shift+Right | Next space in active workspace | Active highlight moves |
| Cmd+Shift+Left | Previous space in active workspace | Active highlight moves |
| Cmd+Shift+T | Create space in active workspace | New space row appears |

### 9.6 Sidebar Keyboard Navigation

| Shortcut | Action |
|----------|--------|
| Cmd+0 | Enter sidebar keyboard focus |
| Up/Down arrow | Move selection through flat items |
| Enter/Space on space row | Activate space (and workspace if different), return to terminal |
| Enter/Space on workspace header | Toggle disclosure |
| Left arrow on workspace header | Collapse disclosure |
| Right arrow on workspace header | Expand disclosure |
| Escape | Return focus to terminal |

---

## 10. Context Menu Implementation

### 10.1 Workspace Header Context Menu (Phase 3)

Applied to `SidebarWorkspaceHeaderView` via `.contextMenu`:

| Item | Action |
|------|--------|
| Rename | Enter inline rename mode for the workspace name. On commit: `workspaceCollection.renameWorkspace(id:newName:)`. |
| Close Workspace | Call `workspaceCollection.removeWorkspace(id:)`. If last workspace, window closes. |

### 10.2 Space Row Context Menu (Phase 3)

Applied to `SidebarSpaceRowView` via `.contextMenu`:

| Item | Action |
|------|--------|
| Rename | Set `sidebarState.renamingSpaceID = space.id`, triggering `InlineRenameView`. |
| Close Space | Call `spaceCollection.removeSpace(id:)`. |

---

## 11. Drag-and-Drop Implementation

### 11.1 Workspace Reorder (Phase 3)

**Drag source:** Each `SidebarWorkspaceHeaderView` is marked as `.draggable(WorkspaceDragItem(workspaceID: workspace.id))`. A new `WorkspaceDragItem` transferable type is needed (analogous to `SpaceDragItem`).

**Drop target:** The workspace list container uses `.dropDestination(for: WorkspaceDragItem.self)`. The drop handler:
1. Extracts the `workspaceID` from the dropped item.
2. Finds source index in `workspaceCollection.workspaces`.
3. Computes destination index from drop location.
4. Calls `workspaceCollection.reorderWorkspace(from:to:)`.

**Drop indicator:** A thin insertion line (2pt height, accent color) between workspace headers at the computed drop position.

**Constraint:** Workspaces can only be reordered within the same window. No cross-window drag.

### 11.2 Space Reorder (Phase 3)

**Drag source:** Each `SidebarSpaceRowView` is marked as `.draggable(SpaceDragItem(spaceID: space.id))`, reusing the existing `SpaceDragItem` transferable type.

**Drop target:** The space list within a disclosure group uses `.dropDestination(for: SpaceDragItem.self)`. The drop handler calls `spaceCollection.reorderSpace(from:to:)`.

**Drop indicator:** Thin horizontal insertion line between rows.

**Cross-workspace prevention:** The drop handler validates that the `spaceID` exists in the current workspace's `spaceCollection.spaces` before accepting.

### 11.3 Cancel Drag on Sidebar Toggle

If a drag is in progress when sidebar toggle is triggered, the drag is cancelled. If `dropIndex != nil`, the toggle is ignored.

---

## 12. Notifications

### 12.1 Notification Names

Defined as extensions on `Notification.Name` in `SidebarContainerView.swift`:

| Name | Object | Purpose |
|------|--------|---------|
| `.toggleSidebar` | `UUID` (window ID) | Toggle sidebar mode. Posted by toggle button and keyboard monitor. |
| `.focusSidebar` | `UUID` (window ID) | Expand sidebar if collapsed, enter keyboard focus. Posted by keyboard monitor on Cmd+0. |

**Note (Phase 2):** The notification object changes from `workspaceID` to a window identifier, since a window now contains multiple workspaces. The window controller posts with a stable window ID.

### 12.2 Removed Notification Names

| Name | Removed In |
|------|-----------|
| `.toggleWorkspaceSwitcher` | Phase 5 |

---

## 13. Accessibility

### 13.1 Labels and Roles

| Element | Label | Role / Value |
|---------|-------|------|
| Sidebar container | "Workspace sidebar" | `.contain` children |
| Workspace header row | "[name], [N] spaces, [expanded/collapsed]" | Activates on click |
| Active workspace header | "[name], active, [N] spaces, [expanded/collapsed]" | Indicates current workspace |
| Space row | "[name]" | Value: "selected" or "not selected" |
| Toggle button | "Toggle sidebar" | Value: "expanded" or "collapsed" |
| Add space button | "New space in [workspace name]" | Button |
| New workspace button | "New workspace" | Button |

### 13.2 Keyboard Accessibility

All sidebar items reachable via Cmd+0 + arrow keys. All actions available via context menu. Escape always returns to terminal.

### 13.3 VoiceOver

The sidebar list uses `List` semantics or `.accessibilityElement(children: .contain)` on the scroll view. Each row is an individual accessibility element. Disclosure state communicated via workspace header label.

---

## 14. Performance Considerations

### 14.1 Terminal Reflow (Unchanged)

The freeze strategy avoids multiple `ghostty_surface_set_size` calls during sidebar toggle animation.

### 14.2 Workspace Switch

Switching workspaces in-place is essentially a state change on `workspaceCollection.activeWorkspaceID`. SwiftUI reactively updates the tab bar and terminal ZStack. Since terminal surfaces are already created and managed by `PaneViewModel` instances within each workspace, switching is instant — no surface creation/destruction needed.

**Important:** All workspaces' terminal surfaces remain alive even when not displayed. This ensures fast switching but increases memory usage proportionally to the number of workspaces. This is acceptable because:
- Typical usage: 2-5 workspaces per window
- Terminal surfaces are lightweight (Ghostty manages the GPU resources; the surface is just a wrapper)

### 14.3 Observable Updates (Unchanged)

The sidebar reads from `workspaceCollection.workspaces` and per-workspace `spaceCollection.spaces`. SwiftUI efficiently diffs these lists. With typically <10 workspaces and <10 spaces each, no lazy loading is needed.

### 14.4 Material Background (Unchanged)

`.glassEffect(.regular)` is hardware-accelerated with negligible CPU cost.

---

## 15. File Organization

### 15.1 New Files

```
aterm/Models/WorkspaceCollection.swift       -- Per-window workspace collection (Phase 2)
aterm/DragAndDrop/WorkspaceDragItem.swift     -- Transferable for workspace drag-and-drop (Phase 3)
```

### 15.2 Sidebar Directory

```
aterm/View/Sidebar/
  SidebarState.swift                -- SidebarMode, SidebarFocusTarget, SidebarState (Done)
  SidebarContainerView.swift        -- ZStack layout, notification defs (Done, Phase 2 update)
  SidebarPanelView.swift            -- Glass panel, workspace content (Done, Phase 2 update)
  SidebarToggleButton.swift         -- Toggle button (Done)
  SidebarExpandedContentView.swift  -- Workspace tree, keyboard nav (Done, Phase 2 update)
  SidebarSpaceRowView.swift         -- Space row (Done, Phase 3 update)
  SidebarWorkspaceHeaderView.swift  -- Workspace header (Done, Phase 3 update)
```

### 15.3 Modified Files

```
aterm/Models/WorkspaceManager.swift                    -- Simplified to app-level coordinator (Phase 2)
aterm/WindowManagement/WindowCoordinator.swift         -- Window-keyed, creates WorkspaceCollection (Phase 2)
aterm/WindowManagement/WorkspaceWindowController.swift -- Owns WorkspaceCollection (Phase 2)
aterm/View/Workspace/WorkspaceWindowContent.swift      -- Receives WorkspaceCollection (Phase 2)
aterm/Input/KeyAction.swift                            -- .newWorkspace behavior change (Phase 2)
aterm/Input/KeyBindingRegistry.swift                   -- Multi-binding support (Done)
```

### 15.4 Deleted Files (Phase 5)

```
aterm/View/Workspace/WorkspaceIndicatorView.swift
aterm/View/SpaceBar/SpaceBarView.swift
aterm/View/SpaceBar/SpaceBarItemView.swift
aterm/View/Workspace/WorkspaceSwitcherOverlay.swift
```

---

## 16. Implementation Phases

### Phase 1: Sidebar Shell and Layout — DONE

**Goal:** Sidebar container, ZStack layout, toggle, glassmorphism.

**Completed:** SidebarState, SidebarContainerView, SidebarPanelView, SidebarToggleButton. KeyAction/KeyBindingRegistry updates. WorkspaceWindowContent delegates to SidebarContainerView. WorkspaceWindowController keyboard monitor handles sidebar actions.

### Phase 2: WorkspaceCollection Architecture + Sidebar Content

**Goal:** Introduce per-window workspace ownership. Populate sidebar with workspace tree. In-place workspace switching.

**Files to create:**
1. `aterm/Models/WorkspaceCollection.swift` — `WorkspaceCollection` class following `SpaceCollection` pattern. Properties: `workspaces`, `activeWorkspaceID`, `shouldQuit`, `onEmpty`, `workspaceCounter`. Methods: `createWorkspace`, `removeWorkspace`, `activateWorkspace`, `nextWorkspace`, `previousWorkspace`, `reorderWorkspace`, `renameWorkspace`. Cascading close wiring.

**Files to modify:**
2. `aterm/Models/WorkspaceManager.swift` — Simplify: remove workspace ownership, CRUD, `shouldQuit`, `windowCoordinator`. Retain `activeWorkspaceID` for app-level tracking.
3. `aterm/WindowManagement/WindowCoordinator.swift` — Rekey from `[UUID: Controller]` (workspace-keyed) to window-keyed. `openWindow()` creates `WorkspaceCollection` with one default workspace, passes to controller. `closeWindow()` cleans up all workspaces in collection.
4. `aterm/WindowManagement/WorkspaceWindowController.swift` — Own `WorkspaceCollection` instead of single workspace. Keyboard monitor delegates `.newWorkspace` and `.closeWorkspace` to collection. Observe active workspace name for window title.
5. `aterm/View/Workspace/WorkspaceWindowContent.swift` — Accept `WorkspaceCollection`. Pass to `SidebarContainerView`.
6. `aterm/View/Sidebar/SidebarContainerView.swift` — Accept `WorkspaceCollection`. Tab bar and terminal ZStack bind to `workspaceCollection.activeWorkspace.spaceCollection`. Observe active workspace changes for container size propagation.
7. `aterm/View/Sidebar/SidebarPanelView.swift` — Accept `WorkspaceCollection`. Pass to `SidebarExpandedContentView`. New workspace button calls `workspaceCollection.createWorkspace()`.
8. `aterm/View/Sidebar/SidebarExpandedContentView.swift` — Read from `WorkspaceCollection` instead of `WorkspaceManager`. Workspace activation calls `workspaceCollection.activateWorkspace(id:)`.
9. `aterm/WindowManagement/AtermAppDelegate.swift` — Update init flow: `WindowCoordinator.openWindow()` now creates `WorkspaceCollection` internally, not via `WorkspaceManager.createWorkspace()`.

**Validation:**
- Sidebar shows all workspaces for current window.
- Clicking a space in another workspace switches in-place.
- Cmd+Shift+N creates workspace in current window.
- Cmd+Shift+Backspace closes active workspace, switches to next.
- Window red button closes all workspaces.
- Last workspace close → window closes → last window → app quits.
- Workspace disclosure, space selection, keyboard nav all work.

### Phase 3: Context Menus, Rename, Drag-and-Drop

**Goal:** Full interaction support for workspaces and spaces.

**Files to create:**
1. `aterm/DragAndDrop/WorkspaceDragItem.swift` — `Transferable` struct with `workspaceID: UUID`.

**Files to modify:**
2. `SidebarWorkspaceHeaderView.swift` — Add `.contextMenu` with Rename and Close Workspace. Add `InlineRenameView` for workspace name. Add `isActive` prop for styling.
3. `SidebarSpaceRowView.swift` — Add `.contextMenu` with Rename and Close Space. Add double-click-to-rename. Wire `InlineRenameView`.
4. `SidebarExpandedContentView.swift` — Add `.dropDestination` for workspace reorder and space reorder. Drop indicator rendering.

**Validation:**
- Workspace header context menu: Rename + Close Workspace.
- Space row context menu: Rename + Close Space.
- Workspace rename (context menu + inline).
- Space rename (double-click + context menu).
- Workspace drag-and-drop reorder.
- Space drag-and-drop reorder.
- Drop indicators visible during drag.

### Phase 4: Collapsed Icon Rail Mode — REMOVED

Collapsed mode is 0pt (fully hidden). No collapsed content view needed.

### Phase 5: Cleanup and Removal of Old Components

**Goal:** Remove legacy components. Single commit for easy revert.

**Files to delete:**
1. `aterm/View/Workspace/WorkspaceIndicatorView.swift`
2. `aterm/View/SpaceBar/SpaceBarView.swift`
3. `aterm/View/SpaceBar/SpaceBarItemView.swift`
4. `aterm/View/Workspace/WorkspaceSwitcherOverlay.swift`

**Files to modify:**
5. `aterm/Input/KeyAction.swift` — Remove `.toggleWorkspaceSwitcher` case.
6. `aterm/View/Workspace/WorkspaceWindowContent.swift` — Remove any remaining references.

**Validation:** Build succeeds. All navigation works through sidebar. Accessibility audit.

---

## 17. Testing Strategy

### 17.1 Unit Tests

| Test | What to Verify |
|------|---------------|
| SidebarMode.width | `.expanded` returns 284.0, `.collapsed` returns 0.0 |
| SidebarState.toggle() | Mode toggles. Returns early if `isAnimating == true`. |
| WorkspaceCollection.createWorkspace | Workspace appended, set as active, counter incremented. |
| WorkspaceCollection.removeWorkspace | Workspace removed. If last: `onEmpty` called or `shouldQuit` set. Otherwise: activates adjacent (prefer left). |
| WorkspaceCollection.activateWorkspace | `activeWorkspaceID` updated. No-op for nonexistent ID. |
| WorkspaceCollection.reorderWorkspace | Workspace moved to new index. Invalid indices no-op. |
| WorkspaceCollection.renameWorkspace | Name updated. Returns false for empty name or not found. |
| WorkspaceCollection cascading close | Last tab → last space → last workspace → `onEmpty` fires. |
| KeyBindingRegistry multi-binding | `.toggleSidebar` matches both Cmd+Shift+S and Cmd+Shift+W |
| KeyBindingRegistry Cmd+0 | `.focusSidebar` matches Cmd+0, does not interfere with Cmd+1..9 |

### 17.2 Integration Tests (Manual)

| Test | Steps | Expected |
|------|-------|----------|
| Sidebar toggle | Press Cmd+Shift+S | Sidebar animates 284pt ↔ 0pt. Terminal reflows once. `tput cols` correct. |
| Space selection (same workspace) | Click space row in active workspace | Tab bar updates, terminal changes, focus returns to terminal. |
| Space selection (different workspace) | Click space row in non-active workspace | Window switches to that workspace in-place. Tab bar and terminal update. Focus returns to terminal. |
| Create workspace | Click "New Workspace" in sidebar | New workspace appears in sidebar, becomes active. Window displays it. |
| Create workspace (keyboard) | Press Cmd+Shift+N | Same as above. |
| Close workspace (has others) | Cmd+Shift+Backspace with 2+ workspaces | Active workspace removed. Window switches to adjacent. |
| Close workspace (last one) | Cmd+Shift+Backspace with 1 workspace | Window closes. |
| Close window | Click red button with multiple workspaces | Window closes. All workspaces cleaned up. |
| Disclosure toggle | Click workspace disclosure triangle | Space list appears/disappears. Focus does not leave terminal. |
| Create space | Click "+" on workspace header (hover) | New space created. |
| Rename workspace | Context menu > Rename on workspace header | Inline rename. Enter commits, Escape cancels. |
| Rename space | Double-click space name | Inline rename. |
| Workspace reorder | Drag workspace header to new position | Drop indicator shows. On drop, workspace reorders. |
| Space reorder | Drag space row to new position | Drop indicator shows. On drop, space reorders. |
| Cmd+0 sidebar focus | Press Cmd+0 | Sidebar items navigable with arrows. Enter selects. Escape returns. |
| Rapid toggle | Press Cmd+Shift+S rapidly 5 times | No crash, no overlapping animations. |
| Material blur | Move window over wallpaper | Sidebar shows blurred background. |

### 17.3 Edge Cases

| Case | Expected Behavior |
|------|-------------------|
| Single workspace, single space | Sidebar shows one workspace with one space. "+" visible. "New Workspace" visible. |
| 5 workspaces, mixed disclosure | Only disclosed workspaces show space rows. Scroll works. |
| Very long workspace name | Truncated with ellipsis at 284pt width. |
| Very long space name | Truncated with ellipsis. |
| Close active space (not last) | Next space becomes active. Sidebar highlight updates. |
| Close last space in workspace | Workspace closes (cascading). Window switches to next workspace. |
| Close last space in last workspace | Window closes. App quits if last window. |
| Toggle during inline rename | Rename committed before animation. |
| Workspace switch during animation | Switch waits until animation completes (or is immediate). |
| Full-screen mode | Sidebar behaves identically to windowed mode. |

---

## 18. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Status |
|------|--------|-----------|--------|
| Terminal surface receives intermediate sizes during animation | Visual artifacts | Medium | **Mitigated:** Freeze strategy gates on `isAnimating`. |
| `.glassEffect(.regular)` rendering | Solid instead of glass | Low | **Resolved:** Works on macOS 26. |
| SwiftUI animation completion timing | Flag cleared too early/late | Low | **Mitigated:** `asyncAfter` with 20ms margin. |
| Multi-binding KeyBindingRegistry | Breaks existing shortcuts | Low | **Resolved:** All bindings verified. |
| Focus management after workspace switch | Keyboard input to wrong terminal | Medium | Mitigate: explicit `makeFirstResponder` after workspace activation. |
| Memory usage with many workspaces | All terminal surfaces alive across all workspaces | Medium | Mitigate: typical 2-5 workspaces. Monitor memory. Future: lazy surface creation. |
| WorkspaceCollection refactor scope | Touches many files (WindowCoordinator, Controller, Manager) | High | Mitigate: implement incrementally. WorkspaceCollection first, then wire to views. |
| Window close vs workspace close confusion | User expects red button to close workspace, not window | Medium | Mitigate: red button closes window (standard macOS). Cmd+Shift+Backspace for single workspace. |
| Cascading close chain correctness | Orphaned resources or premature quit | Medium | Mitigate: unit test the full cascade. Follow SpaceCollection pattern exactly. |

---

## 19. Open Technical Questions

| # | Question | Context | Status |
|---|----------|---------|--------|
| 1 | Should sidebar state (expanded/collapsed) be per-window or global? | | **Decided: per-window.** `SidebarState` is `@State` in `SidebarContainerView`. |
| 2 | Does macOS 26 SwiftUI provide `withAnimation completion:` for reliable post-animation callbacks? | | **Open.** Current `asyncAfter(deadline: .now() + 0.22)` works. |
| 3 | Should workspace disclosure state persist across sidebar toggles? | Collapsed mode is 0pt. | **Decided:** Yes, disclosure state is preserved via `@State` in `SidebarExpandedContentView`. |
| 4 | Should there be workspace navigation shortcuts (Cmd+Ctrl+Left/Right for next/previous workspace)? | Analogous to Cmd+Shift+Left/Right for spaces. | **Open.** Can be added later. Not required for initial implementation. |
| 5 | Should workspace order persist across app restarts? | Currently workspace state is not persisted. | **Open.** Deferred to persistence feature. |
| 6 | Should the notification object change from workspaceID to a window identifier? | With multi-workspace per window, workspaceID is no longer unique to a window. | **Decided:** Yes, use a stable window identifier for notifications. |
| 7 | How should the "File > New Window" menu item work? | No keyboard shortcut for new window. | **Open.** Standard macOS menu item creates a new window with one default workspace. |
| 8 | Should workspaces be movable between windows (drag from one sidebar to another)? | Cross-window workspace management. | **Deferred.** Out of scope for initial implementation. |
