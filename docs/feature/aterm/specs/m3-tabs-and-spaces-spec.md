# SPEC: Milestone 3 -- Tabs and Spaces

**Based on:** docs/feature/aterm/aterm-prd.md v1.4
**Author:** CTO Agent
**Date:** 2026-03-24
**Version:** 1.0
**Status:** Draft

---

## 1. Overview

Milestone 3 adds the Tab and Space layers of the workspace hierarchy. After M2, the app has a single window containing a single pane grid (with splits). M3 introduces the ability to have multiple tabs within a space, and multiple spaces within a (for now, single implicit) workspace. It delivers the tab bar UI, the space bar UI, keyboard navigation for both, and cascading close behavior. The workspace layer itself (creation, switching, multi-window) is deferred to M4.

M3 produces the foundation that M4 (Workspaces) and M5 (Persistence) build upon. The data models defined here are designed to be extended with workspace ownership and serialization in later milestones.

### Functional Requirements Covered

| FR | Summary | Coverage |
|----|---------|----------|
| FR-03 | Create, close, reorder tabs within a space | Full |
| FR-05 | Cascading close (last pane closes tab, last tab closes space, last space...) | Partial -- up to space level; workspace/app quit behavior deferred to M4 |
| FR-06 | Display current space name and tab in visible indicator | Full |
| FR-08 | Switch between spaces via keyboard | Full |
| FR-09 | Switch between tabs via keyboard (next/prev, go-to-by-number) | Full |
| FR-39 | Space bar and tab bar visually distinct | Full |
| FR-41 | VoiceOver labels for space bar and tab bar | Partial -- basic labels; full VoiceOver pass in M7 |

---

## 2. Data Models

### 2.1 SpaceModel

An observable model object representing a named space. Each space owns an ordered collection of tabs.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Stable identity for the space |
| name | String | User-visible name, editable. Default: "default" for the first space |
| tabs | OrderedCollection of TabModel | Tabs in display order. Must always contain at least one tab (enforced at the model level) |
| activeTabID | UUID | ID of the currently focused tab within this space |
| createdAt | Date | Timestamp of creation, used for default ordering |

**Invariants:**
- `tabs` is never empty. If the last tab is closed, the space itself is removed (cascading close).
- `activeTabID` always references a tab that exists in `tabs`.

### 2.2 TabModel

An observable model object representing a single tab. Each tab owns a pane tree (the split layout from M2).

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Stable identity for the tab |
| name | String | User-visible name, editable. Default: "Tab N" where N is the tab's creation index within its space |
| paneTree | PaneNode (from M2) | The root of the pane split tree for this tab |
| activePaneID | UUID | ID of the currently focused pane within this tab |
| createdAt | Date | Timestamp of creation |

**Invariants:**
- `paneTree` always contains at least one pane. If the last pane closes, the tab is removed (cascading close, handled by M2's pane close logic notifying the tab).
- `activePaneID` always references a pane that exists in the tree.

**Dependency on M2:** TabModel wraps M2's PaneNode (the recursive split tree). M3 does not modify the pane split logic itself -- it composes it.

### 2.3 SpaceCollection

A model that owns the ordered list of spaces. In M3, this is a singleton (one collection for the whole app). In M4, each Workspace will own one SpaceCollection.

| Field | Type | Description |
|-------|------|-------------|
| spaces | OrderedCollection of SpaceModel | Spaces in display order |
| activeSpaceID | UUID | ID of the currently focused space |

**Invariants:**
- If the last space is closed, the owning workspace closes (cascading close per FR-05). In M3 (before M4 introduces multi-workspace support), closing the last space quits the app via `NSApplication.shared.terminate(nil)`. In M4, this cascades to workspace close, and if it is the last workspace, the app quits.
- `activeSpaceID` always references a space in `spaces`.

### 2.4 Ordered Collection Semantics

Both spaces and tabs need stable ordering that supports user-initiated reordering (drag-and-drop). Use a Swift `Array` as the backing store. Reordering is done by removing and reinserting at the target index. The array index IS the display order -- no separate `sortOrder` field is needed since the array is the source of truth.

---

## 3. State Management

### 3.1 Observable Architecture

All models (SpaceModel, TabModel, SpaceCollection) should be `@Observable` classes (Swift Observation framework, macOS 14+). This gives SwiftUI automatic view invalidation without `@Published` boilerplate.

The ownership graph:

```
SpaceCollection (singleton in M3; per-workspace in M4)
  |-- spaces: [SpaceModel]
  |     |-- tabs: [TabModel]
  |     |     |-- paneTree: PaneNode (from M2)
  |     |-- activeTabID
  |-- activeSpaceID
```

### 3.2 Active-Item Tracking

"Active" means "currently displayed and receiving keyboard focus." At any moment there is exactly one active space, one active tab within it, and one active pane within that tab.

- SpaceCollection.activeSpaceID determines which space is shown.
- SpaceModel.activeTabID determines which tab's content is rendered.
- TabModel.activePaneID determines which pane has keyboard focus.

Switching spaces restores that space's last-active tab and pane. Switching tabs restores that tab's last-active pane.

### 3.3 Cascading Close Logic

When a close event occurs, the cascade proceeds upward:

1. **Pane closes (M2 logic):** M2 removes the pane from the tab's pane tree. If the pane tree becomes empty, M2 signals the tab that it has no content.
2. **Tab becomes empty:** TabModel detects it has no panes. The space removes this tab from its `tabs` array. If it was the active tab, the space activates the nearest tab (prefer the tab to the left; if none, the tab to the right).
3. **Space becomes empty:** SpaceModel detects it has no tabs. SpaceCollection removes this space. If it was the active space, SpaceCollection activates the nearest space (same left-preference logic). If no spaces remain, the workspace closes. In M3 (pre-M4, single implicit workspace), this means the app quits via `NSApplication.shared.terminate(nil)`. In M4, the workspace close cascades further: if it is the last workspace, the app quits. The M5 quit flow (serialize state before quitting) still applies when quit is triggered by cascading close.

The close cascade is synchronous and driven by model-layer logic, not the view layer.

### 3.4 Communication Between Layers

M2's pane-close completion needs to notify the owning TabModel. The recommended pattern: TabModel provides a closure or delegate callback to the PaneNode tree. When M2 determines the last pane in a tree has closed, it invokes this callback. TabModel then signals its owning SpaceModel, and so on.

Alternatively, if M2 uses a more reactive pattern (e.g., the pane tree is `@Observable` and the tab observes `paneTree.isEmpty`), that works too. The key constraint is that the cascade is deterministic and completes in a single run-loop cycle -- no async gaps where the UI shows an empty tab.

---

## 4. View Architecture

### 4.1 View Hierarchy

```
ContentView (top-level, provided by M1)
  |-- VStack (zero spacing)
  |     |-- SpaceBarView          <-- new in M3
  |     |-- TabBarView            <-- new in M3
  |     |-- PaneGridView (from M2, showing the active tab's pane tree)
```

The space bar sits above the tab bar. Both sit above the content area. The workspace indicator (title bar area) is M4 scope.

### 4.2 SpaceBarView

**Purpose:** Displays a horizontal row of space items for the current (implicit in M3) workspace. Allows switching, creating, renaming, and reordering spaces.

**Layout:**
- Full-width horizontal bar
- Background color: a distinct surface color (e.g., a slightly darker or tinted shade compared to the tab bar) per FR-39
- Left-aligned row of space items, each showing the space name
- The active space item has a prominent visual indicator (e.g., a bottom border accent, bolder text, or a filled background pill)
- A "+" button at the trailing end to create a new space
- Height: fixed, approximately 28-32pt

**Space Item:**
- Displays the space name as a text label
- Click to switch to that space
- Double-click (or Enter when focused) to enter inline rename mode
- Right-click (secondary click) opens a context menu with: Rename, Close
- Draggable for reordering within the bar

**Visual Differentiation from Tab Bar (FR-39):**
- The space bar uses a distinctly different background color from the tab bar. For example, if the tab bar uses a standard toolbar gray, the space bar uses a darker or accent-tinted variant.
- Space items use a different visual shape or style than tab items (e.g., space items are pill-shaped labels while tab items are traditional bordered tabs, or vice versa).
- A visible separator (1pt line or shadow) sits between the space bar and tab bar.
- The space bar has slightly taller item height or different font weight than the tab bar.
- These choices should be consistent with the theme system (M6 will make them configurable). For M3, use hardcoded but tasteful defaults.

**Accessibility:**
- The space bar container has accessibilityRole `.tabList` and accessibilityLabel "Spaces"
- Each space item has accessibilityRole `.tab`, accessibilityLabel set to the space name, and accessibilityValue indicating whether it is selected

### 4.3 TabBarView

**Purpose:** Displays a horizontal row of tabs for the currently active space. Allows switching, creating, closing, renaming, and reordering tabs.

**Layout:**
- Full-width horizontal bar, positioned directly below the space bar
- Background color: standard toolbar/chrome color (visually lighter or more neutral than the space bar)
- Left-aligned row of tab items
- A "+" button at the trailing end to create a new tab
- Height: fixed, approximately 28-32pt

**Tab Item:**
- Displays the tab name as a text label
- Displays a close button ("x") on hover or when the tab is active
- Click to switch to that tab
- Double-click (or Enter when focused) to enter inline rename mode
- Right-click opens a context menu with: Rename, Close, Close Other Tabs, Close Tabs to the Right
- Draggable for reordering within the bar

**Active Tab Indicator:**
- The active tab has a visually distinct style (e.g., connected to the content area with no bottom border, a highlighted background, or an underline accent)

**Accessibility:**
- Container: accessibilityRole `.tabList`, accessibilityLabel "Tabs"
- Each tab item: accessibilityRole `.tab`, accessibilityLabel set to the tab name, accessibilityValue for selection state

### 4.4 Inline Rename

Both space items and tab items support inline renaming. The interaction model:

1. User triggers rename (double-click, Enter key when item is focused, or context menu "Rename")
2. The label transforms into a TextField, pre-filled with the current name, text fully selected
3. User edits and presses Enter to confirm, or Escape to cancel
4. On confirm: model updates the name. On cancel: TextField reverts and disappears.
5. Empty names are not allowed -- if the user clears the field and presses Enter, treat as cancel.

This should be a shared component (InlineRenameView or a ViewModifier) used by both SpaceBarView and TabBarView.

### 4.5 Drag-and-Drop Reordering

Both the space bar and tab bar support drag-and-drop reordering of their items.

**Mechanism:** Use SwiftUI's `draggable` and `dropDestination` modifiers (or `onDrag`/`onDrop` for more control). Each item is draggable with a `Transferable` payload containing the item's UUID. The bar view accepts drops and reorders the model array accordingly.

**Constraints:**
- Tabs can only be reordered within the same space (no cross-space tab dragging in M3).
- Spaces can only be reordered within the bar (no cross-workspace space dragging in M3; workspaces don't exist yet).
- Visual feedback during drag: a drop indicator (line or gap) appears at the insertion point.

**Implementation approach:** Define a lightweight `Transferable` struct (e.g., `TabDragItem` and `SpaceDragItem`) conforming to `Transferable` with a custom UTType containing the UUID. The bar view computes the drop index from the drop location and calls a reorder method on the model.

---

## 5. Keyboard Navigation

### 5.1 Tab Navigation (FR-09)

| Action | Default Shortcut | Behavior |
|--------|-----------------|----------|
| Next tab | Cmd+Shift+] | Activate the tab to the right of the current tab. Wraps around to the first tab. |
| Previous tab | Cmd+Shift+[ | Activate the tab to the left. Wraps around to the last tab. |
| Go to tab N | Cmd+N (1-9) | Activate the Nth tab (1-indexed). Cmd+9 always goes to the last tab regardless of count. If N exceeds tab count, no action. |
| New tab | Cmd+T | Create a new tab at the end of the tab list, activate it |
| Rename tab | (no default; available via context menu) | Begin inline rename of the active tab |

Note: There is no dedicated "close tab" shortcut. `Cmd+W` closes the focused pane (defined in M2). Cascading close applies: if the closed pane is the last pane in a tab, the tab closes. If the last tab in a space, the space closes, and so on up to app quit. Tabs can also be closed via the close button on the tab item or the context menu.

### 5.2 Space Navigation (FR-08)

| Action | Default Shortcut | Behavior |
|--------|-----------------|----------|
| Next space | Cmd+Shift+Right | Activate the space to the right. Wraps around. |
| Previous space | Cmd+Shift+Left | Activate the space to the left. Wraps around. |
| New space | Cmd+Shift+T | Create a new space at the end, activate it. New space has one tab, one pane in the inherited working directory. |
| Rename space | (no default; available via context menu) | Begin inline rename of the active space |

Note: There is no dedicated "close space" shortcut. Spaces close via cascading close: when the last tab in a space closes (because its last pane was closed via `Cmd+W`), the space closes automatically. Spaces can also be closed via the context menu on the space bar item. `Cmd+Shift+W` is reserved for the workspace switcher (M4).

### 5.3 Shortcut Integration

All keyboard shortcuts should be registered through a centralized key-binding system that M6 (Configuration) will make user-configurable. For M3, implement a static mapping from action identifiers to key combinations. The architecture should be:

1. Define an enum of action identifiers (e.g., `KeyAction.nextTab`, `KeyAction.previousTab`, `KeyAction.goToTab(Int)`, etc.)
2. Define a `KeyBindingRegistry` that maps `KeyAction` to `KeyEquivalent + EventModifiers`
3. In M3, the registry is populated with hardcoded defaults
4. In M6, the registry will be populated from TOML configuration

Shortcut handling should use SwiftUI's `.keyboardShortcut()` modifier where possible (for menu-representable commands) and `.onKeyPress()` for more dynamic handling (e.g., Cmd+1 through Cmd+9).

### 5.4 Focus Management

When switching spaces or tabs, keyboard focus must land in the correct pane:

- Switching to a space restores that space's activeTabID, then that tab's activePaneID
- Switching to a tab restores that tab's activePaneID
- Creating a new tab or space sets focus to the new pane
- Closing the active tab moves focus to the nearest tab's active pane
- Closing the active space moves focus to the nearest space's active tab's active pane

Use SwiftUI's `@FocusState` to manage which pane has keyboard focus. The pane grid (M2) should already use `@FocusState` for directional pane navigation. M3 extends this by setting the focus target when switching tabs or spaces.

---

## 6. Operations Detail

### 6.1 Create Tab

1. Determine the working directory: inherit from the currently active pane's working directory (or fall back to home)
2. Create a new PaneNode (M2) with a fresh PTY session in that directory
3. Create a new TabModel with the PaneNode as its tree, name "Tab N"
4. Append the TabModel to the active space's `tabs` array
5. Set the space's `activeTabID` to the new tab's ID
6. Focus the new pane

### 6.2 Close Tab

1. Identify the tab to close (the active tab, or a specific tab from context menu)
2. Close all panes in the tab's pane tree (send SIGHUP to each PTY, tear down resources). This uses M2's pane close logic.
3. Remove the tab from the space's `tabs` array
4. If tabs remain: activate the nearest tab (prefer left, else right)
5. If no tabs remain: trigger space close (cascading)

### 6.3 Rename Tab / Space

1. Enter inline rename mode (view concern)
2. On confirm, update `tabModel.name` or `spaceModel.name`
3. Name validation: non-empty, trimmed of leading/trailing whitespace. No uniqueness constraint (users may have duplicate names).

### 6.4 Reorder Tab / Space

1. User drags an item to a new position
2. Determine the source index and destination index
3. Remove the item from the source index and insert at the destination index
4. Model array update triggers SwiftUI re-render with animation

### 6.5 Create Space

1. Determine the working directory (home, or in M4, the workspace's default directory)
2. Create a new PaneNode with a fresh PTY
3. Create a new TabModel wrapping that PaneNode
4. Create a new SpaceModel with that tab, name prompted via inline rename (the space name field starts in edit mode)
5. Append to SpaceCollection.spaces
6. Set activeSpaceID to the new space

### 6.6 Close Space

1. For each tab in the space, close all panes (SIGHUP to PTYs)
2. Remove all tabs
3. Remove the space from SpaceCollection.spaces
4. If spaces remain: activate the nearest space
5. If no spaces remain: the workspace closes. In M3 (pre-M4), this triggers app quit via `NSApplication.shared.terminate(nil)`. The M5 quit flow (serialize state before quitting) still applies.

---

## 7. File Structure

Following a feature-based directory layout appropriate for a Swift/SwiftUI project:

```
aterm/
  Sources/
    App/
      AtermApp.swift              (app entry point, from M1)
      ContentView.swift           (top-level view, modified in M3 to include bars)
    Models/
      SpaceModel.swift            (new in M3)
      TabModel.swift              (new in M3)
      SpaceCollection.swift       (new in M3)
      PaneNode.swift              (from M2)
    Views/
      SpaceBar/
        SpaceBarView.swift        (new in M3)
        SpaceBarItemView.swift    (new in M3)
      TabBar/
        TabBarView.swift          (new in M3)
        TabBarItemView.swift      (new in M3)
      Shared/
        InlineRenameView.swift    (new in M3)
      PaneGrid/
        PaneGridView.swift        (from M2)
    Input/
      KeyAction.swift             (new in M3)
      KeyBindingRegistry.swift    (new in M3)
    DragAndDrop/
      TabDragItem.swift           (new in M3)
      SpaceDragItem.swift         (new in M3)
```

Note: This is a proposed structure. If M1/M2 establish a different convention, follow that convention instead. The key principle is that M3 introduces new files and modifies ContentView -- it should not need to modify M2's pane logic beyond wiring the pane-close callback.

---

## 8. Dependencies on M1 and M2

### From M1 (Terminal Fundamentals)
- **PTY session management:** M3 needs to spawn new PTY sessions when creating tabs and spaces. It calls into M1's PTY spawn API.
- **ContentView:** M3 modifies the top-level ContentView to insert SpaceBarView and TabBarView above the content area.
- **Shell/working directory:** M3 uses M1's mechanism for launching a shell in a given directory.

### From M2 (Pane Splitting)
- **PaneNode:** TabModel wraps a PaneNode as its content. M3 creates PaneNode instances for new tabs.
- **PaneGridView:** The content area renders the active tab's PaneNode using PaneGridView from M2.
- **Pane close notification:** M3 needs to know when a tab's pane tree becomes empty. This requires M2 to expose a callback or observable state for "tree is empty."
- **Active pane tracking:** M2's focus management (activePaneID, @FocusState) is used by M3 to restore focus when switching tabs/spaces.

### Interface Contract with M2

M3 requires the following from M2's PaneNode:

1. A way to create a PaneNode containing a single pane with a given PTY session
2. A way to close all panes in a PaneNode tree (teardown)
3. An observable or callback-based signal when the tree becomes empty (last pane closed)
4. An `activePaneID` property (or equivalent) to track and restore focused pane
5. A `isEmpty` computed property

If M2 does not already expose these, they should be added as part of M3 implementation (or as a preparatory task before M3 begins).

---

## 9. Performance Considerations

### Lazy Tab Content

Only the active tab's pane grid should be actively rendering. Inactive tabs should have their Metal rendering paused (not producing frames) but their PTY sessions remain alive and buffering output. When a tab becomes active, its renderer resumes.

This means the PaneGridView for an inactive tab should not be in the SwiftUI view hierarchy. Instead, only the active tab's PaneGridView is rendered. Tab switching swaps which PaneNode is passed to PaneGridView.

### Memory

Each tab's pane tree holds PTY file descriptors and scrollback buffers even when inactive. With many tabs, this can accumulate. For M3, no mitigation is needed beyond awareness. M7 (Polish) may introduce scrollback eviction for background tabs.

### Drag-and-Drop Performance

With a small number of tabs/spaces (tens, not hundreds), drag-and-drop reordering via array manipulation is fine. No optimization needed.

### Animation

Tab and space switching should use minimal or no animation (instant swap of content). Tab bar reordering and close animations should be brief (0.15-0.2s) to feel responsive. Use SwiftUI's `withAnimation(.easeOut(duration: 0.15))` for reorder and close transitions.

---

## 10. Accessibility

### VoiceOver Support (FR-41, partial)

- SpaceBarView: `.accessibilityElement(children: .contain)`, label "Spaces", role `.tabList`
- Each space item: role `.tab`, label is space name, value is "selected" or "not selected"
- TabBarView: same pattern with label "Tabs"
- Each tab item: role `.tab`, label is tab name, value is selection state
- Close buttons: label "Close tab [name]" or "Close space [name]"
- New tab/space buttons: label "New tab" / "New space"

### Keyboard Accessibility

All operations are keyboard-accessible per the shortcuts table in Section 5. The tab bar and space bar items should be navigable via Tab key (standard keyboard navigation) in addition to the chord shortcuts.

---

## 11. Error Handling

### PTY Spawn Failure on Tab/Space Creation

If the shell fails to launch when creating a new tab or space, the pane should display an error message (using M1's error display mechanism from FR-25). The tab and space are still created -- they just contain an error-state pane. The user can close it normally.

### Close Failures

Closing a pane sends SIGHUP to the PTY. If the process does not exit, the pane should still be removed from the UI after a brief timeout (e.g., 500ms). SIGKILL as a follow-up is acceptable. This is M1/M2 scope but M3 depends on it working reliably for cascading close.

---

## 12. Implementation Phases

### Phase 1: Data Models and Core Logic (no UI)

- Implement SpaceModel, TabModel, SpaceCollection as @Observable classes
- Implement all operations: create, close, rename, reorder for both tabs and spaces
- Implement cascading close logic
- Write unit tests for all model operations, especially cascading close edge cases
- Define KeyAction enum and KeyBindingRegistry with hardcoded defaults

**Deliverable:** All model logic is testable in isolation. No UI yet.

### Phase 2: Tab Bar UI

- Implement TabBarView and TabBarItemView
- Wire tab bar to SpaceModel (shows tabs for active space)
- Implement tab switching via click
- Implement new tab button
- Implement close tab button (on hover)
- Implement keyboard shortcuts for tab navigation (Cmd+Shift+], Cmd+Shift+[, Cmd+1-9, Cmd+T)
- Modify ContentView to include TabBarView above PaneGridView

**Deliverable:** Functional tab bar with keyboard navigation. Spaces not yet visible.

### Phase 3: Space Bar UI

- Implement SpaceBarView and SpaceBarItemView
- Wire space bar to SpaceCollection
- Implement space switching via click
- Implement new space button
- Implement close space button
- Implement keyboard shortcuts for space navigation (Cmd+Shift+Left/Right, Cmd+Shift+T)
- Apply FR-39 visual differentiation (different background, separator, item style)
- Insert SpaceBarView above TabBarView in ContentView

**Deliverable:** Both bars visible and functional.

### Phase 4: Inline Rename and Drag-and-Drop

- Implement InlineRenameView shared component
- Wire inline rename to tab items and space items
- Implement context menus for tabs and spaces
- Implement drag-and-drop reordering for tabs
- Implement drag-and-drop reordering for spaces
- Implement Transferable conformances

**Deliverable:** Full M3 feature set complete.

### Phase 5: Polish and Testing

- Verify focus management across all tab/space switching scenarios
- Verify cascading close in all edge cases (last pane, last tab, last space)
- Add accessibility labels and verify with VoiceOver
- Tune animations and visual details
- Verify no regressions in M1/M2 functionality

**Deliverable:** M3 ready for integration.

---

## 13. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| M2 PaneNode does not expose a clean "tree empty" signal | Blocks cascading close | Medium | Define the interface contract now (Section 8). If M2 is being built concurrently, coordinate on this API before M3 begins. |
| SwiftUI focus management (`@FocusState`) is unreliable when swapping view subtrees | Focus lands in wrong pane or nowhere after tab/space switch | Medium | Test early in Phase 2. Fallback: use `NSApp.keyWindow?.makeFirstResponder()` to programmatically set focus on the Metal view backing the target pane. |
| Drag-and-drop with SwiftUI's `Transferable` feels janky or has visual glitches | Poor reorder UX | Low | Start with SwiftUI-native approach. If unsatisfactory, fall back to NSView-level drag-and-drop via a representable wrapper. |
| Cmd+1-9 conflicts with macOS system shortcuts or other apps | Shortcuts don't fire | Low | These are standard tab-switching shortcuts (used by Safari, Chrome, Terminal.app). SwiftUI `.keyboardShortcut` should capture them. Test early. |
| Cmd+W close behavior ambiguity (close tab vs. close pane) | User confusion | Low | Resolved: Cmd+W always closes the focused pane. Cascading close means the last pane in a tab closes the tab, the last tab in a space closes the space, etc. This is consistent and predictable. |

---

## 14. Open Technical Questions

| # | Question | Context | Impact if Unresolved |
|---|----------|---------|---------------------|
| 1 | Should Cmd+W close the active tab or the focused pane? | **Resolved:** Cmd+W closes the focused pane. Cascading close applies: if it is the last pane in a tab, the tab closes. If the last tab in a space, the space closes. And so on up to app quit. This approach is consistent and avoids needing separate pane-close and tab-close shortcuts. | Resolved. |
| 2 | When creating a new space, should the name prompt be modal or inline in the space bar? | Inline is more seamless but requires the space to be created first with a placeholder name. | Minor UX difference. **Recommendation:** Create space with name "Space N", immediately enter inline rename mode. |
| 3 | Should inactive tab PTY sessions continue to receive and buffer output? | If yes, switching to a tab shows all output generated while it was in the background. If no, output is lost. | Missing output would be surprising. **Recommendation:** Yes, PTYs stay alive and buffer. The rendering is paused but the PTY read loop continues writing to the scrollback buffer. |
| 4 | What are the exact colors and visual treatment for the space bar vs. tab bar? | FR-39 requires visual differentiation but doesn't specify exact styling. | Solvable at implementation time with iteration. Does not block architecture. |
| 5 | How does M2's PaneNode currently expose its structure? | No code exists yet -- M1 and M2 are also pre-implementation. | The interface contract in Section 8 needs to be agreed upon before M2 and M3 are built. |
