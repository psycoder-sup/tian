# SPEC: M2 -- Pane Splitting

**Based on:** docs/feature/aterm/aterm-prd.md v1.4
**Author:** CTO Agent
**Date:** 2026-03-24
**Version:** 1.0
**Status:** Draft

---

## 1. Overview

This spec covers Milestone 2 (Pane Splitting), which introduces multi-pane support within a single tab. A user can split any pane horizontally or vertically, navigate between panes directionally, resize panes via drag handles, and close individual panes. The split layout is modeled as a recursive binary tree of value types, where internal nodes represent split containers (with direction and ratio) and leaf nodes represent terminal panes.

M2 depends on M1 (Terminal Fundamentals) providing: a working PTY manager, VT parser integration via libghostty-vt, Metal-based terminal renderer, and a single-pane terminal view. M2 does not introduce tabs, spaces, or workspaces -- the split tree lives inside what will become the "tab content area" in M3.

The core design decision is to use an **immutable value-type binary tree** for the split model. Whenever any split property changes (new split, close, ratio adjustment), a new tree value is produced and the view hierarchy re-renders. This is practical because split trees are small (rarely more than a few dozen nodes) and it simplifies undo, serialization (M5), and SwiftUI integration.

---

## 2. Split Tree Data Model

### Node Types

The split tree is a recursive enum with two cases:

| Case | Description | Fields |
|------|-------------|--------|
| **leaf** | A terminal pane | `paneID` (UUID), `workingDirectory` (String) |
| **split** | A container that divides space between two children | `direction` (horizontal or vertical), `ratio` (Double, 0.0 to 1.0), `first` (PaneNode), `second` (PaneNode) |

**Direction semantics:**
- **horizontal** -- divides space into left and right (a vertical divider line separates them)
- **vertical** -- divides space into top and bottom (a horizontal divider line separates them)

This naming convention matches the user's mental model: "split horizontal" produces side-by-side panes.

### SplitTree Wrapper

A top-level value type wraps the root node and tracks focus state:

| Field | Type | Description |
|-------|------|-------------|
| `root` | PaneNode | The root of the binary tree. Initially a single leaf. |
| `focusedPaneID` | UUID | The pane that currently has keyboard focus. |

### Pane Identity

Each leaf carries a stable UUID (`paneID`) assigned at creation time. This ID is the key used to:
- Look up the associated PTY session in the PTY manager (from M1)
- Look up the associated terminal state / renderer
- Track focus
- Serialize and restore pane identity (M5)

### Immutability Contract

The SplitTree and PaneNode types conform to Swift's value semantics (structs / enums). All mutation operations are expressed as functions that accept the current tree and return a new tree. The owning view model holds a single published property of type SplitTree and replaces it on every operation. SwiftUI diffs the tree to update only the changed portions of the view hierarchy.

---

## 3. Split Operations

### 3.1 Split Pane

**Trigger:** User presses the split shortcut (default: Cmd+Shift+D for horizontal, Cmd+Shift+E for vertical) while a pane has focus.

**Algorithm:**
1. Find the leaf node in the tree whose `paneID` matches `focusedPaneID`.
2. Generate a new UUID for the new pane.
3. Query the PTY manager for the working directory of the focused pane (via `lsof -p <pid>` or `/proc`-equivalent on macOS: `proc_pidinfo` with `PROC_PIDVNODEPATHINFO`).
4. Replace the matched leaf with a new split node:
   - `direction`: the requested split direction
   - `ratio`: 0.5 (equal split)
   - `first`: the original leaf (unchanged)
   - `second`: a new leaf with the new paneID and inherited working directory
5. Spawn a new PTY session in the inherited working directory (delegates to M1 PTY manager).
6. Update `focusedPaneID` to the new pane's ID.
7. Send SIGWINCH to both panes (their terminal dimensions have changed).

**Error handling:**
- If shell spawn fails for the new pane, revert the tree to its previous state (discard the split). The original pane remains unaffected. Show an error overlay on the original pane briefly.
- If working directory retrieval fails, fall back to `$HOME`.

### 3.2 Close Pane

**Trigger:** User presses the close pane shortcut, or the shell process in a pane exits.

**Algorithm:**
1. Find the split node that is the parent of the leaf being closed.
2. Replace the parent split node with the sibling node (the other child). This "promotes" the sibling up one level.
3. If the closed pane was the focused pane, move focus to the sibling (if the sibling is a leaf) or to the first leaf in the sibling subtree (depth-first, first-child traversal).
4. Send SIGHUP to the closed pane's PTY session and clean up its resources.
5. Send SIGWINCH to all panes whose dimensions changed (the sibling subtree).

**Edge case -- last pane in tree:**
- When the root is a single leaf and that pane is closed, the tab closes. Cascading close continues upward: if it is the last tab in a space, the space closes. If the last space in a workspace, the workspace closes. If the last workspace, the app quits via `NSApplication.shared.terminate(nil)`. (In M2 with no tab/space/workspace support yet, closing the last pane quits the app directly.)

**Edge case -- shell exit behavior (FR-25):**
- Exit code 0: close the pane automatically (trigger close algorithm above).
- Non-zero exit code: keep the pane open, display an overlay message "[process exited with code N]" in the pane area. The pane remains in the tree as a leaf but is inert (no PTY session). User must explicitly close it.

### 3.3 Resize Pane (FR-43)

**Trigger:** User drags a divider handle between two panes.

**Algorithm:**
1. Identify which split node owns the divider being dragged. Each divider corresponds to exactly one split node in the tree.
2. Compute the new ratio based on the drag position relative to the split node's allocated frame.
3. Clamp the ratio to a minimum of 0.1 and maximum of 0.9 (prevents panes from being resized to zero). The minimum ensures each side gets at least 10% of the available space.
4. Produce a new tree with the updated ratio.
5. Send SIGWINCH to all panes in both subtrees of the affected split node.

**Drag handle visual:**
- The divider is a 4pt-wide hit target region rendered between the two children of a split node.
- The visible line is 1pt wide, centered within the hit target.
- On hover, the cursor changes to the appropriate resize cursor (horizontal resize for vertical dividers, vertical resize for horizontal dividers).
- During drag, the divider is highlighted (subtle color change) for feedback.

**No keyboard resize shortcuts.** Pane resize is mouse drag-handle only. This avoids shortcut conflicts with space and tab navigation. If keyboard resize is desired in the future, it can be added via the M6 configuration system with non-conflicting chords.

---

## 4. Focus Navigation (FR-10)

### Spatial Navigation Algorithm

Focus navigation uses a **spatial (geometric) approach** rather than tree traversal. This produces intuitive results regardless of tree structure.

**Trigger:** User presses directional shortcut (default: Cmd+Option+Arrow -- configurable in M6).

**Algorithm:**
1. Compute the screen-space bounding rectangle for every leaf pane in the tree (this is a byproduct of the layout algorithm, cached per layout pass).
2. Identify the focused pane's rectangle.
3. Filter candidate panes to those that are in the requested direction from the focused pane:
   - **Left:** candidates whose right edge is at or left of the focused pane's left edge
   - **Right:** candidates whose left edge is at or right of the focused pane's right edge
   - **Up:** candidates whose bottom edge is at or above the focused pane's top edge
   - **Down:** candidates whose top edge is at or below the focused pane's bottom edge
4. If no candidates remain, do nothing (focus stays on current pane -- no wrapping).
5. Among candidates, select the one with the smallest Euclidean distance between the center of the focused pane's relevant edge and the center of the candidate's opposite edge. For example, when moving right, measure from the center of the focused pane's right edge to the center of each candidate's left edge.
6. Update `focusedPaneID` to the selected candidate.

**Why spatial over tree traversal:** Tree-based navigation produces unintuitive results in complex layouts. For example, in a 3-pane layout where pane A is on the left (full height) and panes B (top-right) and C (bottom-right) are stacked on the right, pressing "down" from B should go to C regardless of the tree's internal nesting. Spatial navigation handles this correctly.

**Focus visual indicator:**
- The focused pane has a subtle border highlight (e.g., 2pt accent-colored border on its inner edge) to distinguish it from unfocused panes.
- Unfocused panes dim their cursor (no blink, reduced opacity or outline-only cursor).

---

## 5. Layout Algorithm

### Recursive Layout

The layout algorithm converts the split tree into concrete frames (CGRect) for each pane. It is a simple recursive descent:

**Input:** A PaneNode and the available CGRect.

**For a leaf node:** The entire available rect is assigned to that pane.

**For a split node:**
1. Based on direction and ratio, divide the available rect into two sub-rects:
   - **Horizontal split:** divide width. `first` gets `width * ratio`, `second` gets the remainder. Both get full height.
   - **Vertical split:** divide height. `first` gets `height * ratio`, `second` gets the remainder. Both get full width.
2. Subtract divider thickness (4pt) from the appropriate dimension, splitting it equally between the two sides (2pt each).
3. Recurse into `first` with the first sub-rect, and `second` with the second sub-rect.

**Output:** A dictionary mapping paneID to CGRect, plus a list of divider rects (for hit-testing and rendering).

This runs in O(n) time where n is the number of nodes in the tree. Since split trees are small, performance is not a concern.

### Terminal Dimension Updates

After layout, for each pane whose CGRect changed since the last layout pass:
1. Compute the new column and row count: `columns = floor(rect.width / cellWidth)`, `rows = floor(rect.height / cellHeight)`, where cellWidth and cellHeight come from the font metrics (M1).
2. Update the PTY's window size via `ioctl(fd, TIOCSWINSZ, &winsize)`.
3. The PTY session sends SIGWINCH to the shell process automatically.

---

## 6. Pane Lifecycle

### Pane Creation

1. A new UUID is generated.
2. A PTY session is spawned via the M1 PTY manager, in the specified working directory.
3. A terminal state instance (libghostty-vt) is created for the new pane.
4. A Metal renderer instance is created (or the existing renderer is configured to render an additional pane -- depends on M1's renderer architecture).
5. The pane is inserted into the split tree as a leaf.
6. Layout is recomputed, SIGWINCH sent.

### Pane Destruction

1. The pane's PTY session is terminated (SIGHUP, then cleanup).
2. The terminal state instance is deallocated.
3. The renderer resources for this pane are released.
4. The leaf is removed from the split tree (replaced by sibling).
5. Layout is recomputed, SIGWINCH sent to affected panes.

### Resource Ownership

Each pane owns three resources that must be lifecycle-managed:

| Resource | Created | Destroyed | Owner |
|----------|---------|-----------|-------|
| PTY session (file descriptor + process) | On pane creation | On pane close (SIGHUP) | PTY manager (M1) |
| Terminal state (libghostty-vt instance) | On pane creation | On pane close | Pane controller / view model |
| Renderer state (Metal buffers, font atlas ref) | On pane creation | On pane close | Renderer (M1) |

The paneID is the join key between the split tree (which is a pure data structure) and these runtime resources. A separate registry (dictionary keyed by paneID) maps pane IDs to their associated PTY session, terminal state, and renderer state.

---

## 7. Component Architecture

### Feature Directory Structure

All M2 code lives within the existing source tree. Proposed structure (to be refined when M1 establishes the project layout):

```
aterm/
  Sources/
    aterm/
      Features/
        Pane/
          PaneNode.swift           -- PaneNode enum, SplitTree struct, all tree operations
          SplitLayout.swift        -- Layout algorithm: tree + rect -> pane frames + divider rects
          SplitNavigation.swift    -- Spatial focus navigation algorithm
          PaneView.swift           -- SwiftUI view for a single terminal pane (wraps M1 TerminalView)
          SplitTreeView.swift      -- Recursive SwiftUI view that renders the split tree
          DividerView.swift        -- Drag handle view for resizing
          PaneOverlayView.swift    -- Overlay for exit code messages, errors
          PaneRegistry.swift       -- Maps paneID -> PTY session, terminal state, renderer
          PaneViewModel.swift      -- Observable object owning the SplitTree, handles commands
      Extensions/
        CGRect+Split.swift        -- Rect subdivision helpers
```

### View Hierarchy

```
ContentView (M1, will become tab content area in M3)
  SplitTreeView(tree: splitTree, focusedID: focusedPaneID)
    -- recursively renders:
    if leaf:
      PaneView(paneID: id, isFocused: bool)
        TerminalMetalView (M1)       -- Metal rendering surface
        PaneOverlayView (conditional) -- exit code message when pane is inert
        FocusBorderView (conditional) -- accent border when focused
    if split:
      HSplitContainer or VSplitContainer
        SplitTreeView(first child)
        DividerView(axis, onDrag callback)
        SplitTreeView(second child)
```

### PaneViewModel

This is the central coordinator for M2. It is an `@Observable` class that owns:

| Property | Type | Description |
|----------|------|-------------|
| `splitTree` | SplitTree | The current split tree state. Published; drives SwiftUI. |
| `paneRegistry` | PaneRegistry | Maps paneID to runtime resources (PTY, terminal state, renderer). |
| `paneFrames` | Dictionary of UUID to CGRect | Cached layout output. Recomputed when tree or container size changes. |
| `dividerRects` | Array of DividerInfo | Cached divider positions for hit-testing. |

| Method | Description |
|--------|-------------|
| `splitPane(direction:)` | Splits the focused pane in the given direction. |
| `closePane(id:)` | Closes the specified pane. |
| `moveFocus(direction:)` | Moves focus in the given direction using spatial navigation. |
| `resizeSplit(dividerID:, newRatio:)` | Updates the ratio of the specified split node. |
| `updateLayout(containerSize:)` | Recomputes pane frames and divider rects. |

### DividerView

| Prop | Type | Description |
|------|------|-------------|
| `axis` | Axis (horizontal or vertical) | Determines cursor and drag direction |
| `onDrag` | Callback with delta | Reports drag offset to PaneViewModel |

Behavior: Renders a 4pt-wide transparent hit target with a 1pt visible line. Changes cursor on hover. Reports continuous drag deltas during gesture.

### PaneView

Wraps the M1 terminal rendering surface (TerminalMetalView / NSViewRepresentable for Metal) and adds:
- Focus border (2pt colored border when this pane is focused)
- Overlay for error/exit messages
- Click-to-focus gesture (clicking an unfocused pane updates `focusedPaneID`)

---

## 8. Keyboard Shortcut Registration

M2 introduces the following default shortcuts (all configurable in M6):

| Action | Default Shortcut | Description |
|--------|-----------------|-------------|
| Split horizontal | Cmd+Shift+D | Split focused pane into left and right |
| Split vertical | Cmd+Shift+E | Split focused pane into top and bottom |
| Close pane | Cmd+W | Close the focused pane. Cascading close: if it is the last pane in a tab, the tab closes. If the last tab in a space, the space closes. If the last space in a workspace, the workspace closes. If the last workspace, the app quits. |
| Focus left | Cmd+Option+Left | Move focus to pane on the left |
| Focus right | Cmd+Option+Right | Move focus to pane on the right |
| Focus up | Cmd+Option+Up | Move focus to pane above |
| Focus down | Cmd+Option+Down | Move focus to pane below |

Shortcuts are registered at the SwiftUI window level using `.onKeyPress` or via NSEvent monitoring (depending on M1's input architecture). They are only active when the terminal content area has focus.

---

## 9. Working Directory Inheritance

When a pane is split, the new pane inherits the current working directory of the source pane. The current working directory is determined at split time (not at source pane creation time) because the user may have `cd`'d since opening the pane.

**Retrieval method (macOS):**
1. Get the PID of the foreground process group in the PTY via `tcgetpgrp(fd)`.
2. Use `proc_pidinfo` with `PROC_PIDVNODEPATHINFO` to get the working directory of that process.
3. If this fails (process exited, permission issue), fall back to the working directory stored in the pane's leaf node (the directory it was originally opened with).
4. If that also fails, fall back to `$HOME`.

---

## 10. Dependency on M1 Components

M2 assumes the following M1 interfaces exist. These are the integration points:

| M1 Component | M2 Usage | Required Interface |
|--------------|----------|-------------------|
| PTY Manager | Spawn new sessions, get fd, get foreground PID, send SIGHUP | `spawnSession(workingDirectory:, shell:) -> PTYSession`, `PTYSession.fd`, `PTYSession.foregroundPID`, `PTYSession.terminate()` |
| Terminal State (libghostty-vt) | Create per-pane VT state, resize | `createTerminal(rows:, columns:) -> TerminalHandle`, `resize(handle:, rows:, columns:)`, `destroy(handle:)` |
| Metal Renderer | Render terminal content in a given rect | `render(terminalHandle:, in: CGRect)` or per-pane MTKView |
| Font Metrics | Compute cell dimensions for row/column calculation | `cellWidth: CGFloat`, `cellHeight: CGFloat` |
| TerminalView | The SwiftUI/AppKit view that displays a single terminal | Wrappable in PaneView; must accept a terminal handle and frame |
| Input Router | Route keyboard input to the focused pane's PTY | Must support routing by paneID or focused pane concept |

If M1 uses a single MTKView for rendering, M2 will need to either (a) extend it to render multiple pane regions in a single draw call, or (b) switch to one MTKView per pane. Option (b) is simpler and recommended for M2 -- one MTKView per pane, each sized to its layout rect.

---

## 11. Performance Considerations

**Layout recomputation:** O(n) where n is number of tree nodes. Triggered on split, close, resize, and window resize. With practical tree sizes (under 50 nodes), this is sub-microsecond.

**SIGWINCH batching:** During a drag-resize, ratio changes fire continuously. Debounce SIGWINCH delivery to at most once per 16ms (one frame at 60fps) to avoid overwhelming shell processes with resize signals.

**Renderer overhead:** Each pane has its own Metal rendering surface. With many panes, this means many draw calls per frame. For M2, this is acceptable (users rarely have more than 6-8 panes). If profiling reveals issues, a future optimization can batch all panes into a single Metal render pass.

**Memory:** Each pane carries its own scrollback buffer (default 10,000 lines from FR-14). With 8 panes, that is 80,000 lines of scrollback in memory. This is acceptable for modern hardware.

**View diffing:** Because SplitTree is a value type, SwiftUI can efficiently diff the old and new tree. Only changed subtrees trigger view updates. The tree structure itself is small; the heavy rendering (Metal) is decoupled.

---

## 12. Serialization Considerations (Forward-Looking for M5)

Although persistence is M5 scope, the split tree data model is designed to be trivially serializable:

- PaneNode is a recursive enum with only primitive fields (UUID, String, Double, Direction enum). It will conform to Codable with zero custom serialization logic.
- The paneID stability means the serialized tree can be matched to restored PTY sessions.
- The ratio field directly captures the resize state.

No M2 work is needed for serialization, but the data model must not include non-serializable fields (closures, view references, file descriptors). All runtime state lives in PaneRegistry, not in the tree.

---

## 13. Implementation Phases

### Phase 1: Split Tree Core (estimated: 2-3 days)

- Implement PaneNode enum and SplitTree struct with value semantics
- Implement tree operations: insert split, remove leaf (promote sibling), update ratio, find leaf by ID, enumerate all leaves
- Implement layout algorithm (tree + rect -> pane frames + divider rects)
- Unit tests for all tree operations and layout computation

### Phase 2: Basic Split UI (estimated: 3-4 days)

- Implement SplitTreeView (recursive SwiftUI view)
- Implement PaneView wrapping M1's TerminalView
- Implement PaneRegistry mapping paneID to PTY/terminal/renderer resources
- Implement PaneViewModel with splitPane and closePane operations
- Wire split shortcuts (Cmd+Shift+D, Cmd+Shift+E) and close shortcut (Cmd+W)
- Verify: can split a pane, see two terminals side by side, type in each, close one

### Phase 3: Focus Navigation (estimated: 2 days)

- Implement spatial navigation algorithm in SplitNavigation
- Wire directional focus shortcuts
- Implement focus visual indicator (border highlight, cursor dimming)
- Implement click-to-focus on unfocused panes
- Verify: can navigate between panes with keyboard, visual feedback is correct

### Phase 4: Resize via Drag Handles (estimated: 2-3 days)

- Implement DividerView with drag gesture
- Implement drag-to-resize updating split ratio with clamping
- Implement SIGWINCH debouncing during continuous resize
- Implement resize cursor on divider hover
- Verify: can drag dividers smoothly, pane contents reflow correctly

### Phase 5: Working Directory Inheritance and Polish (estimated: 1-2 days)

- Implement working directory retrieval via proc_pidinfo
- Implement fallback chain (proc_pidinfo -> stored directory -> $HOME)
- Implement exit code overlay for non-zero exits (FR-25)
- Implement shell-exit-triggered pane close for exit code 0
- Implement last-pane-close quits app behavior
- End-to-end testing of all flows

---

## 14. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| M1 renderer architecture does not support multiple render surfaces | High -- blocks all of M2 | Medium | Design M1 with per-pane MTKView from the start, or plan for the refactor at M2 start. Communicate this requirement to M1 spec. |
| proc_pidinfo fails to retrieve working directory for some shells (fish, nushell) | Low -- only affects directory inheritance | Low | Fallback chain handles this. Document that $HOME is used if retrieval fails. |
| SwiftUI performance with many nested views in deep split trees | Medium -- jank during split/close | Low | Split trees are small. If needed, drop to AppKit (NSView) for the split container layer, similar to Ghostty's approach. |
| SIGWINCH storm during resize causes shell rendering artifacts | Medium -- visual glitches | Medium | Debounce to 60fps. Tested in Phase 4. |
| Keyboard shortcut conflicts with terminal applications (vim, emacs) | Medium -- unusable shortcuts | Medium | Use Cmd+Shift and Cmd+Option chords that terminal apps do not capture. Make configurable in M6. |
| Resource leak if pane close fails to clean up PTY/terminal/renderer | High -- fd leak, memory leak | Low | PaneRegistry enforces cleanup on pane removal. Add assertions in debug builds that registry size matches leaf count. |

---

## 15. Open Technical Questions

| # | Question | Context | Impact if Unresolved |
|---|----------|---------|---------------------|
| 1 | Does M1 use a single MTKView or one-per-pane? | If single, M2 must either refactor it or implement multi-region rendering in one view. | Blocks Phase 2. Must resolve before M2 starts. |
| 2 | How does M1 route keyboard input to the terminal? | M2 needs to route input to the focused pane only. If M1 hardcodes a single terminal, M2 must introduce a routing layer. | Blocks Phase 2. |
| 3 | Should the minimum pane dimension be configurable or hardcoded? | The 10% ratio clamp is a simple approach but may be too restrictive for some layouts. An absolute minimum (e.g., 80px) might be more useful. | Low -- can adjust in M7 polish. Start with 10% ratio clamp. |
| 4 | Should divider double-click equalize the split ratio (reset to 50%)? | Nice UX polish, low effort. | None -- optional enhancement, can be added in any phase. |
| 5 | What is the exact Cmd+Shift vs Cmd+Option chord assignment policy? | Resolved: Cmd+W closes focused pane (cascading). Cmd+Option+Arrow navigates pane focus. Keyboard resize shortcuts have been removed; resize is mouse drag-handle only. Cmd+Shift+D/E for split. No conflicts remain. | Resolved. |
