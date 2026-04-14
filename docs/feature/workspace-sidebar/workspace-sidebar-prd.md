# PRD: Workspace Sidebar Redesign

**Author:** psycoder
**Date:** 2026-04-01
**Version:** 1.1
**Status:** Review

---

## 1. Overview

Replace tian's current horizontal navigation chrome (WorkspaceIndicatorView + SpaceBarView + WorkspaceSwitcherOverlay) with a glassmorphism sidebar that displays the current window's workspace and its spaces in a hierarchical tree. The tab bar remains horizontal at the top of the content area. The sidebar uses macOS material effects to show desktop wallpaper behind it, and supports a collapsed icon-rail mode for maximum terminal real estate.

**Target user:** The developer (sole user) who works across multiple project workspaces and git worktree spaces, navigating primarily via keyboard but wanting clear visual hierarchy at a glance.

**Why now:** The current navigation stacks three horizontal bars (workspace indicator, space bar, tab bar) plus a modal overlay for workspace switching. This consumes vertical space, scatters related information across disconnected UI bands, and forces a modal context switch (Cmd+Shift+W overlay) just to see all workspaces. A sidebar consolidates workspace and space navigation into a single persistent, scannable surface.

**Key design decision -- current workspace only:** Each window's sidebar shows only its own workspace and that workspace's spaces. There is no cross-window workspace tree. This keeps the sidebar simple and focused. For switching between workspaces, the user switches windows (Cmd+` or Mission Control). This is an intentional tradeoff: the sidebar provides visual workspace context and space navigation within one workspace, not a global workspace browser.

---

## 2. Background

### Current State

The window layout today (per `WorkspaceWindowContent.swift`):

```
┌──────────────────────────────────────────┐
│  [WorkspaceIndicator] | [SpaceBar ...]   │  28pt, .windowBackgroundColor @ 0.7
├──────────────────────────────────────────┤
│  [TabBar: Tab A | Tab B | (+)]           │  30pt, .windowBackgroundColor
├──────────────────────────────────────────┤
│                                          │
│           Terminal Content                │
│           (SplitTreeView)               │
│                                          │
└──────────────────────────────────────────┘
```

**Components being replaced:**
- `WorkspaceIndicatorView` -- inline breadcrumb showing "Workspace > Space" (11pt text, 28pt bar)
- `SpaceBarView` + `SpaceBarItemView` -- horizontal scrolling capsule pills for spaces
- `WorkspaceSwitcherOverlay` -- modal fuzzy-search overlay triggered by Cmd+Shift+W

**Component being kept (relocated):**
- `TabBarView` + `TabBarItemView` -- horizontal tab bar, moves to the top of the content area (right of sidebar)

**Why change:**
1. The horizontal space bar and workspace indicator compete for the same narrow strip. With many spaces, the space bar scrolls horizontally and the workspace indicator gets squeezed.
2. Workspace switching requires a modal overlay that hides the terminal. A persistent sidebar lets the user see all spaces at all times.
3. The hierarchy (Workspace > Space > Tab > Pane) maps naturally to a tree structure, which is better expressed vertically than horizontally.
4. A sidebar is a well-understood macOS navigation pattern (Finder, Xcode, Terminal.app window groups).

### Prior Art / Inspiration

- **Xcode Navigator** -- collapsible sidebar with hierarchical tree, icon-only mode
- **iTerm2 Profiles Panel** -- side panel for session management
- **macOS Finder sidebar** -- persistent, uses system materials/vibrancy
- **VS Code Activity Bar + Sidebar** -- icon rail that expands to a full sidebar on click
- **Warp** -- sidebar for session/workflow navigation with glass-like treatment

---

## 3. Goals & Non-Goals

### Goals

- **G1:** Consolidate workspace and space navigation into a single persistent sidebar, eliminating the horizontal workspace indicator, space bar, and workspace switcher overlay.
- **G2:** Display the current workspace and its spaces as a hierarchical tree that is always visible (no modal required).
- **G3:** Support a collapsed icon-rail mode that preserves terminal width when the full sidebar is not needed.
- **G4:** Apply macOS glassmorphism (material blur) to the sidebar, showing desktop wallpaper behind it. Use push layout (sidebar sits beside content, not overlaid on top).
- **G5:** Maintain full keyboard navigability for all sidebar interactions -- expand/collapse workspace, select spaces, create/rename/delete items, toggle sidebar visibility.
- **G6:** Keep the tab bar as a horizontal bar at the top of the content area (right of the sidebar), consistent with its current behavior.

### Non-Goals

- **NG1:** Tab management in the sidebar -- tabs remain in the horizontal tab bar.
- **NG2:** Drag-and-drop of spaces between workspaces (cross-workspace move). Reorder within a workspace is in scope.
- **NG3:** Sidebar position customization (left vs. right). Sidebar is always on the left.
- **NG4:** Sidebar width customization via drag handle in v1 (fixed expanded/collapsed widths).
- **NG5:** Search/filter within the sidebar. The fuzzy-search overlay is intentionally removed without a sidebar search replacement. The sidebar provides spatial/visual context; for cross-workspace switching, the user switches windows (Cmd+` or Mission Control). Sidebar search may be revisited post-v1 if the workflow proves inadequate.
- **NG6:** Pinned/favorite spaces or workspaces.
- **NG7:** Badges or status indicators on sidebar items (e.g., running process count, git status). Post-v1.
- **NG8:** Cross-window workspace tree. Each window's sidebar shows only its own workspace.

---

## 4. User Stories

| # | As a... | I want to... | So that... |
|---|---------|--------------|------------|
| 1 | developer | see my current workspace and its spaces in a persistent sidebar | I can visually scan my space hierarchy without triggering a modal overlay |
| 2 | developer | click a space in the sidebar to switch to it | I can navigate between branches/worktrees with a single click |
| 3 | developer | collapse the sidebar to an icon rail | I can reclaim horizontal space for terminal content when I know where I am |
| 4 | developer | expand/collapse the workspace disclosure triangle | I can focus on or hide the space list as needed |
| 5 | developer | create a new space from the sidebar | I can start new branches without a separate dialog |
| 6 | developer | rename and delete spaces via context menu in the sidebar | I can keep my space hierarchy organized |
| 7 | developer | reorder spaces within the sidebar via drag-and-drop | I can arrange items in the order I prefer |
| 8 | developer | toggle the sidebar via keyboard shortcut | I can show/hide the sidebar without reaching for the mouse |
| 9 | developer | see which space is currently active | I always know my context at a glance |
| 10 | developer | see a glassmorphism blur effect on the sidebar showing the desktop behind it | the sidebar feels native to macOS and visually lightweight |
| 11 | developer | return focus to the terminal after a sidebar interaction | I can resume typing without extra steps |

---

## 5. Functional Requirements

### Sidebar Layout

**FR-01:** The sidebar must be positioned on the left side of the workspace window, pushing the content area (tab bar + terminal) to the right. This is a side-by-side (push) layout, not an overlay.

**FR-02:** The sidebar must have two modes: expanded and collapsed (icon rail). Only one mode is active at a time per window.

**FR-03:** In expanded mode, the sidebar must display a single workspace (the current window's workspace) as a disclosure group, with its spaces as children. No other workspaces appear in the sidebar.

**FR-04:** In collapsed mode, the sidebar must display an icon rail showing the current workspace's icon or initial. Clicking the workspace icon expands the sidebar to reveal spaces.

**FR-05:** The sidebar must use a macOS material background (`.ultraThinMaterial` or equivalent) to produce a glassmorphism blur effect, showing desktop content behind the sidebar.

**FR-06:** The sidebar must have a fixed width in each mode: approximately 200pt expanded, approximately 48pt collapsed. These are not user-resizable in v1.

**FR-07:** The tab bar (`TabBarView`) must remain as a horizontal bar at the top of the content area, to the right of the sidebar. Its current behavior (tab selection, close, reorder, new tab button, context menu) is unchanged.

### Sidebar Content -- Expanded Mode

**FR-08:** The current workspace must be rendered as a disclosure group (expandable/collapsible section) in the sidebar. The workspace row must show: the workspace name and a disclosure triangle.

**FR-09:** Each space within the workspace must be rendered as a child row under the workspace disclosure group. The space row must show the space name.

**FR-10:** The workspace name must be visually prominent (e.g., semibold text, primary color) to serve as a header/label.

**FR-11:** The currently active space must be visually distinguished (e.g., selection highlight, accent color background).

**FR-12:** A "+" affordance must be visible within the workspace disclosure group for creating a new space. A separate "+" button at the bottom of the sidebar is not needed (since there is only one workspace per sidebar), but may be included if it aids discoverability.

**FR-13:** The workspace disclosure group must remember its expanded/collapsed state in memory for the lifetime of the app process. State resets on app restart (no disk persistence in v1).

### Sidebar Content -- Collapsed (Icon Rail) Mode

**FR-14:** In collapsed mode, the current workspace must be represented by a single icon or the first letter(s) of the workspace name. Individual spaces are hidden.

**FR-15:** Clicking the workspace icon in collapsed mode must expand the sidebar to reveal the workspace's spaces.

**FR-16:** In collapsed mode, the user must expand the sidebar to navigate between spaces.

### Sidebar Toggle

**FR-17:** The sidebar must be togglable between expanded and collapsed modes via keyboard shortcut. Two shortcuts: Cmd+Shift+S (primary toggle) and Cmd+Shift+W (repurposed from the removed workspace switcher overlay). Both must be registered in `KeyBindingRegistry`.

**FR-18:** The sidebar toggle must also be accessible via a button in the sidebar header (expanded mode) or at the top of the icon rail (collapsed mode).

**FR-19:** The toggle between expanded and collapsed must animate smoothly (~200ms, easeInOut). During the animation, the terminal surface size is frozen at the current size. After the animation completes, a single SIGWINCH is sent with the final dimensions. This avoids visual artifacts from incremental reflowing during the transition.

### Navigation & Selection

**FR-20:** Clicking a space row in the expanded sidebar must activate that space (calls `spaceCollection.activateSpace(id:)`). After selection, focus returns to the terminal.

**FR-21:** Clicking the workspace row (the header) must expand/collapse the workspace's disclosure group. Since the sidebar shows only the current workspace, no window switching is involved.

**FR-22:** All existing keyboard shortcuts for space navigation must continue to work and update the sidebar selection accordingly:
- Cmd+Shift+Right/Left (next/previous space)
- Cmd+Shift+N (new workspace)
- Cmd+Shift+Backspace (close workspace)
- Cmd+Shift+T (new space)

### Focus Management

**FR-23:** The terminal must have focus by default. Sidebar interactions should be "fire and forget" -- the terminal regains focus after most operations.

**FR-24:** Clicking a space row selects it and immediately returns focus to the terminal.

**FR-25:** Clicking a disclosure triangle keeps focus in the sidebar for further navigation (the user may want to expand and then click a space).

**FR-26:** A dedicated keyboard shortcut (Cmd+0, matching Xcode convention) must enter sidebar keyboard focus. While focused, arrow keys navigate sidebar items. Escape returns focus to the terminal.

**FR-27:** Inline rename (via `InlineRenameView`) takes focus when active. Enter commits the rename and returns focus to the terminal. Escape cancels and returns focus to the terminal.

### Context Menus

**FR-28:** Right-clicking the workspace row must show a context menu with: Rename, Close Workspace.

**FR-29:** Right-clicking a space row must show a context menu with: Rename, Close Space.

**FR-30:** Inline rename must use the existing `InlineRenameView` component (double-click to rename, or "Rename" from context menu), consistent with the current space bar and tab bar rename behavior.

### Drag-and-Drop

**FR-31:** Spaces must be reorderable within their parent workspace via drag-and-drop, using the existing `SpaceDragItem` transferable type.

**FR-32:** Drag-and-drop must not allow moving a space to a different workspace (cross-workspace move is NG2).

### Removed Components

**FR-33:** The `WorkspaceIndicatorView` (breadcrumb in the top bar) must be removed from the window layout.

**FR-34:** The `SpaceBarView` (horizontal space capsules) must be removed from the window layout.

**FR-35:** The `WorkspaceSwitcherOverlay` (modal fuzzy-search overlay triggered by Cmd+Shift+W) must be removed. Cmd+Shift+W is repurposed as an alternate sidebar toggle shortcut (see FR-17).

### Narrow Window Behavior

**FR-36:** If the window width is less than the expanded sidebar minimum (600pt) when the user tries to expand the sidebar, the window must auto-resize to 600pt to accommodate the expanded sidebar. If the screen cannot fit 600pt (e.g., extremely small display), the sidebar remains collapsed.

---

## 6. User Flows

### Flow 1: Navigate to a Space via Sidebar (Happy Path)

```
Precondition: Sidebar is expanded. The current workspace has
              multiple spaces.

1. User sees the sidebar with the current workspace expanded,
   showing its spaces. Active space is highlighted.

2. User clicks a different space row within the workspace.

3. System:
   a. Activates the selected space
      (spaceCollection.activateSpace)
   b. Updates sidebar highlight to show new active space
   c. Tab bar updates to show tabs of the newly active space
   d. Terminal content updates to show the active tab's pane grid
   e. Focus returns to the terminal pane

4. User resumes typing in the terminal.
```

### Flow 2: Create a New Space from the Sidebar

```
Precondition: Sidebar is expanded. Workspace disclosure group
              is expanded.

1. User clicks the "+" icon within the workspace's space list.

2. System creates a new space in the workspace
   (spaceCollection.createSpace) with a default name.

3. New space appears as the last child in the workspace's
   disclosure group.

4. System enters inline rename mode on the new space row
   (InlineRenameView becomes active, takes focus).

5. User types a name and presses Enter.

6. Space name is committed. Focus returns to the terminal pane
   in the new space's default tab.

Alternate: User presses Escape during rename -> space keeps
           the default name ("Space N"), focus returns to terminal.
```

### Flow 3: Toggle Sidebar to Collapsed Mode

```
Precondition: Sidebar is in expanded mode.

1. User presses Cmd+Shift+S (or Cmd+Shift+W, or clicks the
   collapse button).

2. System freezes the terminal surface at its current size and
   animates the sidebar from expanded (200pt) to collapsed (48pt)
   icon rail (~200ms, easeInOut).

3. After animation completes:
   a. Content area (tab bar + terminal) expands to fill the
      reclaimed width.
   b. A single SIGWINCH is sent with the final dimensions.
   c. Terminal content reflows to the new width.

4. Sidebar now shows the workspace icon/initial.

5. Focus remains on the terminal throughout.
```

### Flow 4: Navigate from Collapsed Icon Rail

```
Precondition: Sidebar is in collapsed (icon rail) mode.

1. User clicks the workspace icon in the icon rail.

2. System animates sidebar from collapsed to expanded mode
   (same freeze-then-reflow as Flow 3, in reverse).

3. Workspace disclosure group is expanded, showing spaces.

4. User clicks a space row.

5. System activates that space, focus returns to terminal
   (same as Flow 1, step 3).
```

### Flow 5: Reorder Spaces via Drag-and-Drop

```
Precondition: Sidebar is expanded. Workspace has multiple spaces.

1. User long-presses/drags a space row.

2. System begins drag with SpaceDragItem.
   A visual drag preview appears.

3. User drags to a new position in the space list.
   Drop indicator (insertion line) shows between spaces.

4. User releases the drag.

5. System reorders the space within the workspace.
   Sidebar list reflects the new position.
```

### Flow 6: Rename a Space from the Sidebar

```
Precondition: Sidebar is expanded.

1. User double-clicks a space name in the sidebar,
   OR right-clicks and selects "Rename" from the context menu.

2. Space name becomes an inline text field
   (InlineRenameView takes focus).

3. User edits the name and presses Enter.

4. Name is committed. Focus returns to the terminal.
   Sidebar updates with the new name.

Alternate: User presses Escape -> rename is cancelled,
           original name is restored, focus returns to terminal.
Error: User submits an empty name -> rename is rejected,
       field stays active (existing InlineRenameView behavior).
```

### Flow 7: Return Focus to Terminal from Sidebar

```
Precondition: Sidebar has keyboard focus (user pressed Cmd+0).

1. User navigates sidebar items with arrow keys.

2. User presses Escape (or clicks the terminal area).

3. Focus returns to the terminal. Keyboard input goes to
   the terminal PTY.
```

### Key States (ASCII Mockups)

**Expanded sidebar (single workspace, multiple spaces):**
```
┌──────────────────────────────────────────────┐
│  Workspace Window                            │
├─────────┬────────────────────────────────────┤
│ [<]     │  Tab A | Tab B | [+]               │
│─────────├────────────────────────────────────┤
│         │                                    │
│ ▼ proj-a│                                    │
│   main  │       Terminal Content              │
│ ● dev   │       (SplitTreeView)              │
│   staging│                                    │
│   [+]   │                                    │
│         │                                    │
│         │                                    │
│         │                                    │
│         │                                    │
│         │                                    │
│ 200pt   │          remaining width           │
└─────────┴────────────────────────────────────┘

Legend:
  [<]     = collapse toggle button
  ▼       = disclosure triangle (expanded)
  ●       = active space indicator (accent dot or highlight)
  [+]     = create new space (within workspace group)
```

**Collapsed icon rail:**
```
┌──────────────────────────────────────────────┐
│  Workspace Window                            │
├────┬─────────────────────────────────────────┤
│[>] │  Tab A | Tab B | [+]                    │
│────├─────────────────────────────────────────┤
│    │                                         │
│ PA │                                         │
│    │        Terminal Content                  │
│    │        (SplitTreeView)                  │
│    │                                         │
│    │                                         │
│    │                                         │
│    │                                         │
│    │                                         │
│48pt│            remaining width              │
└────┴─────────────────────────────────────────┘

Legend:
  [>]     = expand toggle button
  PA      = workspace initial (first 1-2 letters)
            with accent background
```

**Single workspace, single space (minimal state):**
```
┌──────────────────────────────────────────────┐
│  Workspace Window                            │
├─────────┬────────────────────────────────────┤
│ [<]     │  Tab 1 | [+]                       │
│─────────├────────────────────────────────────┤
│         │                                    │
│ ▼ defaul│                                    │
│ ● defaul│       Terminal Content              │
│   [+]   │                                    │
│         │                                    │
│         │                                    │
│         │                                    │
│         │                                    │
│         │                                    │
└─────────┴────────────────────────────────────┘
```

---

## 7. Design & UX

### Visual Design Direction

**Material:** The sidebar background must use a macOS material (`.ultraThinMaterial` or `.thinMaterial`) to produce translucency and blur. Since the sidebar uses a push layout with the terminal content beside it, the blur will show the desktop wallpaper through the sidebar area. The window's `NSWindow` should have `titlebarAppearsTransparent = true` (already set) and the sidebar region should extend under the title bar for a seamless glass effect.

**Color palette:**
- Sidebar background: macOS material (blur), no solid fill
- Active space row: accent color tint (`.tint` or `.accentColor`) at low opacity (~15-20%) with a rounded rectangle background
- Workspace header: semibold text weight, primary color
- Inactive items: secondary text color, regular weight
- Icon rail indicator: accent color circle/pill behind the workspace initial
- Dividers: `.separator` color, used sparingly (between sidebar and content area only)

**Typography:**
- Workspace name: 12pt system font, semibold
- Space names: 11pt system font, consistent with existing `SpaceBarItemView` and `TabBarItemView` sizing
- Icon rail initial: 13pt system font, semibold, centered in a 32pt circle

**Spacing:**
- Sidebar expanded width: 200pt
- Sidebar collapsed width: 48pt
- Row height: 28pt (workspace header), 26pt (space items)
- Horizontal padding: 12pt
- Disclosure indent: 16pt per level
- Icon rail icon size: 32pt circle within 48pt rail

### Interaction Patterns

**Expand/collapse toggle:** Animated width transition (~200ms, easeInOut). Terminal surface frozen during animation; single SIGWINCH after completion (see FR-19).

**Disclosure triangles:** Standard macOS disclosure behavior -- click to expand/collapse. Animated rotation of the triangle icon.

**Hover effects:** Subtle background highlight on hover (`.quaternary` fill), matching the existing `TabBarItemView` hover pattern.

**Double-click to rename:** Consistent with existing SpaceBarItemView and TabBarItemView behavior, using `InlineRenameView`.

**Drag-and-drop:** Visual drop indicator (insertion line) between items. Uses existing `SpaceDragItem` transferable type.

### Accessibility

**Keyboard navigability:**
- All sidebar items must be reachable via Cmd+0 (enter sidebar focus) + arrow key navigation
- Expand/collapse workspace must work via keyboard (Space or Right/Left arrow)
- All sidebar actions available via context menu and keyboard shortcuts
- Escape returns focus to terminal from any sidebar focus state

**VoiceOver:**
- Sidebar container: accessibility label "Workspace sidebar", role `list`
- Workspace row: accessibility label "[workspace name], [space count] spaces, [expanded/collapsed]"
- Each space row: accessibility label "[space name]", value "selected" or "not selected"
- Toggle button: accessibility label "Toggle sidebar" with value "expanded" or "collapsed"
- "+" button: accessibility label "New space in [workspace name]"

**Contrast:**
- Text on material backgrounds must meet 4.5:1 contrast. macOS materials automatically adapt to the underlying content to maintain readability, but active item highlighting must be tested against both light and dark wallpapers.
- The accent color used for active indicators must be visible against the material background in both light and dark appearance modes.

### Platform-Specific Behavior

| Behavior | macOS |
|----------|-------|
| Material effect | `.ultraThinMaterial` (SwiftUI) / `NSVisualEffectView` with `.underPageBackground` or `.sidebar` material |
| Sidebar position | Left side, under transparent title bar |
| Sidebar toggle animation | Smooth width transition via `withAnimation(.easeInOut(duration: 0.2))` |
| Window resize | Sidebar width is fixed; content area absorbs all resize changes |
| Full-screen mode | Sidebar remains visible, same behavior as in windowed mode |

---

## 8. Edge Cases & Error Handling

### Empty States

| State | What the user sees |
|-------|-------------------|
| No workspaces (impossible -- app quits) | N/A. Cascading close rule ensures this cannot happen. |
| Single workspace, single space | Sidebar shows one workspace disclosure group (expanded) with one space. The "+" button is prominent. The sidebar is still useful as a context indicator. |
| Workspace with no spaces (impossible) | N/A. Creating a workspace always creates a default space. Closing the last space closes the workspace. |
| Very long workspace/space name | Text truncation with trailing ellipsis. Full name visible on hover (tooltip) and in context menu. Expanded sidebar width is fixed at 200pt. |
| Many spaces within one workspace (10+) | The workspace's disclosure group becomes scrollable within the overall sidebar scroll view. |

### Error States

| Condition | Handling |
|-----------|---------|
| Sidebar toggle while drag-and-drop is in progress | Cancel the drag operation before animating. |
| Rename to empty string | Rejected by existing `InlineRenameView` behavior (reverts to original name). |
| Window too narrow for expanded sidebar | If window width < 600pt when expanding, auto-resize window to 600pt. If screen cannot fit 600pt, sidebar remains collapsed (see FR-36). |
| Rapid sidebar toggle (user spams Cmd+Shift+S) | Debounce or coalesce animations. Do not start a new transition while one is in progress. |

### Transition from Current UI

| Concern | Handling |
|---------|---------|
| Existing keyboard shortcuts | All workspace/space shortcuts remain functional. Cmd+Shift+W is repurposed as an alternate sidebar toggle. New shortcut Cmd+Shift+S added as primary sidebar toggle. |
| Existing drag-and-drop | `SpaceDragItem` is reused. Drop targets move from the horizontal bars to the sidebar tree. |
| Sidebar expanded/collapsed state | In-memory only for v1. Resets on app restart. |
| Disclosure group state | In-memory only for v1. Active workspace expanded by default on launch. |
| Users relying on SpaceBarView for reordering | Same interaction (drag-and-drop) is available in the sidebar. |

---

## 9. Permissions & Privacy

No new permissions required. tian is not sandboxed. The sidebar reads from existing in-memory data structures (WorkspaceManager, SpaceCollection). No additional data is collected, stored, or shared.

---

## 10. Analytics & Instrumentation

No analytics instrumentation. tian is a personal tool; success is evaluated by qualitative daily-driver feel, not telemetry.

---

## 11. Success Metrics

Since tian is a personal tool with a single user, success is qualitative:

| Metric | Target |
|--------|--------|
| Navigation consolidation | All space navigation within a workspace is achievable through the sidebar without needing any other UI surface |
| Vertical space reclaimed | The 58pt of horizontal bars (28pt workspace/space bar + 30pt tab bar in separate row) is replaced by the 30pt tab bar only. The sidebar uses horizontal space instead of vertical, giving more terminal rows. |
| Keyboard coverage | All sidebar operations (toggle, select space, create, rename, close) are achievable via keyboard |
| Visual clarity | Active space is identifiable within 200ms of glancing at the sidebar (no reading required -- position + color is sufficient) |
| Terminal reflow correctness | After sidebar toggle animation, all visible panes have correct dimensions (COLUMNS/LINES match, no rendering artifacts) |
| Collapsed mode utility | Icon rail shows workspace context; expanding from it is quick and intuitive |
| Glass effect quality | Sidebar material blur is visible with typical desktop wallpapers in both light and dark mode |
| Focus management | Terminal has focus after every sidebar interaction except explicit sidebar keyboard navigation (Cmd+0) |

---

## 12. Release Strategy

This is a personal tool with no external users to migrate, so no feature flag or gradual rollout is needed.

**Coexistence during development:** During phases 1-4, old components (WorkspaceIndicatorView, SpaceBarView, WorkspaceSwitcherOverlay) remain in the codebase and may remain visible alongside the new sidebar. This allows testing the new sidebar without losing fallback navigation.

**Phase 5 removal:** The removal of old components (FR-33, FR-34, FR-35) is performed as a separate commit so it can be easily reverted if regressions are discovered after the sidebar is feature-complete.

**No force update or OTA concerns:** Single-user desktop app built from source.

---

## 13. Open Questions

| # | Question | Context | Owner | Due Date |
|---|----------|---------|-------|----------|
| 1 | Should sidebar expanded/collapsed state be global or per-window? | If global, toggling in one window toggles all. If per-window, each workspace can have its own preference. Global is simpler; per-window is more flexible. | psycoder | Before implementation |
| 2 | Should the sidebar animate its initial appearance on app launch, or start in its saved state immediately? | Subtle animation could feel polished; immediate state could feel faster. Moot in v1 since state is not persisted, but relevant for post-v1 persistence. | psycoder | During implementation |
| 3 | Should the workspace disclosure group auto-collapse when the sidebar collapses, or remember its state? | If it auto-collapses, expanding the sidebar always shows the collapsed workspace header first. If it remembers, expanding shows the full space list if it was open before collapsing. | psycoder | During implementation |
| 4 | What icon should represent the workspace in the collapsed icon rail? | Options: (a) first 1-2 letters of the workspace name, (b) user-assignable SF Symbols icon per workspace. Option (a) is simplest for v1. | psycoder | Before implementation |

---

## 14. Post-v1

| Item | Notes |
|------|-------|
| Set Default Working Directory (workspace context menu) | Tracked as WORK-261. Adds a "Set Default Working Directory" option to the workspace context menu. Deferred from v1 to keep the context menu minimal. |
| Sidebar expanded/collapsed state persistence to disk | Currently in-memory only. Persist per-workspace sidebar state across app restarts. |
| Disclosure group state persistence to disk | Currently in-memory only. Persist which workspaces are expanded across app restarts. |
| Sidebar search/filter | If window-switching proves insufficient for cross-workspace navigation, add search within the sidebar. |
| User-assignable workspace icons | SF Symbols icons per workspace for richer icon rail. |

---

## 15. Timeline & Milestones

This section defines the logical ordering of work, not calendar estimates. Each phase builds on the previous and produces a testable deliverable.

### Phase 1: Sidebar Shell and Layout

**Goal:** Establish the sidebar container, push layout, and toggle mechanism. No content yet -- just the glass panel and the content area side by side.

**Deliverables:**
- New `SidebarContainerView` wrapping the sidebar and content area in an HStack
- Material background on the sidebar region (`.ultraThinMaterial`)
- Sidebar expanded/collapsed state toggle with Cmd+Shift+S and Cmd+Shift+W shortcuts
- Animated width transition between expanded (200pt) and collapsed (48pt), terminal surface frozen during animation, single SIGWINCH after completion
- Auto-resize window to 600pt if expanding sidebar in a narrow window (FR-36)
- `WorkspaceWindowContent` updated to use the new layout instead of the current VStack
- Tab bar repositioned to the top of the content area (right of sidebar)
- `KeyAction` and `KeyBindingRegistry` updated with `.toggleSidebar` action

**Validates:** Glass effect renders correctly, push layout works, terminal reflows correctly after toggle, narrow window behavior works.

### Phase 2: Sidebar Content -- Expanded Mode

**Goal:** Populate the sidebar with the workspace/space tree in expanded mode.

**Deliverables:**
- Workspace disclosure group with expand/collapse (current workspace only)
- Space rows as children of the workspace
- Active space visual highlighting
- Click to select space (activates space, returns focus to terminal)
- Click workspace header to expand/collapse disclosure group
- "+" button for new space within workspace group
- Cmd+0 to enter sidebar keyboard focus, arrow keys to navigate, Escape to return to terminal
- Disclosure state in memory (resets on app restart)

**Validates:** Full navigation via sidebar in expanded mode. Focus management works correctly.

### Phase 3: Context Menus, Rename, Drag-and-Drop

**Goal:** Parity with existing interaction capabilities.

**Deliverables:**
- Context menu on workspace row (Rename, Close Workspace)
- Context menu on space rows (Rename, Close Space)
- Double-click to rename using `InlineRenameView` (focus returns to terminal on commit/cancel)
- Drag-and-drop reorder for spaces within the workspace (using `SpaceDragItem`)

**Validates:** Feature parity with the removed SpaceBarView. Rename focus management is correct.

### Phase 4: Collapsed Icon Rail Mode

**Goal:** Implement the icon-rail collapsed state with workspace icon/initial.

**Deliverables:**
- Icon rail rendering with workspace initial in a circle
- Click icon to expand sidebar
- Expand/collapse toggle button visual treatment for both modes

**Validates:** Collapsed mode is usable for workspace identification.

### Phase 5: Cleanup and Removal of Old Components

**Goal:** Remove the old navigation components and ensure no regressions. This phase is a separate commit for easy revert.

**Deliverables:**
- Remove `WorkspaceIndicatorView` from `WorkspaceWindowContent`
- Remove `SpaceBarView` and `SpaceBarItemView` (files can be deleted or archived)
- Remove `WorkspaceSwitcherOverlay` and related `SwitcherSearchField` (files can be deleted or archived)
- Remove `Notification.Name.toggleWorkspaceSwitcher` and its handling
- Verify all existing keyboard shortcuts still work (Cmd+Shift+W now toggles sidebar)
- Accessibility audit of the sidebar

**Validates:** Clean removal with no dead code. All navigation works through the new sidebar.
