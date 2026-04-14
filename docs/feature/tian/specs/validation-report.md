# Spec Validation Report: tian Milestones M1-M7

**PRD Version:** 1.4 (Approved, 2026-03-24)
**Specs Reviewed:** M1 through M7
**Reviewer:** CTO Agent
**Date:** 2026-03-24

---

## 1. PRD Functional Requirement Coverage

### Coverage Matrix

| FR | Description | Assigned Milestone(s) | Coverage Status | Notes |
|----|-------------|----------------------|-----------------|-------|
| FR-01 | Create, rename, reorder, delete workspaces | M4 | Partial | **Reorder via drag-and-drop is explicitly deferred** in M4 Section 3.2 (marked "Not in M4 scope"). FR-01 requires it. See Issue #1. |
| FR-02 | Create, rename, reorder, delete spaces | M3 | Full | |
| FR-03 | Create, close, reorder tabs | M3 | Full | |
| FR-04 | Horizontal/vertical pane splits, nestable | M2 | Full | |
| FR-05 | Cascading close behavior | M2, M3, M4 | Full | M2 handles pane-to-tab, M3 handles tab-to-space, M4 handles space-to-workspace-to-app. |
| FR-06 | Display current workspace, space, tab | M3, M4 | Full | M3 provides space/tab bars; M4 provides workspace indicator. |
| FR-07 | Workspace switcher with fuzzy search | M4 | Full | |
| FR-08 | Switch spaces via keyboard | M3 | Full | |
| FR-09 | Switch tabs via keyboard (next/prev, go-to-by-number) | M3 | Full | |
| FR-10 | Directional pane focus navigation | M2 | Full | |
| FR-11 | Independent terminal session per pane | M1 | Full | |
| FR-12 | VT100/VT220/xterm escape sequences via libghostty-vt | M1 | Full | |
| FR-13 | 256-color and true-color support | M1 | Full | |
| FR-14 | Configurable scrollback buffer (default 10,000) | M1, M6 | Full | M1 implements; M6 makes configurable. |
| FR-15 | Smooth scrolling at 60fps | M1 | Full | |
| FR-16 | Correct terminal dimensions and SIGWINCH | M1, M2 | Full | |
| FR-17 | Unicode including combining and CJK characters | M1 | Full | |
| FR-18 | GPU rendering via Metal with font atlas and instanced rendering | M1 | Full | |
| FR-19 | Configurable font family and size | M1, M6 | Full | M1 hardcodes; M6 makes configurable. |
| FR-20 | Bold, italic, underline, strikethrough, inverse | M1 | Full | |
| FR-21 | Cursor styles (block, underline, bar) with configurable blinking | M1, M6 | Full | |
| FR-22 | Quit confirmation dialog for foreground processes | M5 | Full | |
| FR-23 | Serialize workspace hierarchy to JSON on quit | M5 | Full | |
| FR-24 | Restore persisted hierarchy on launch | M5 | Full | |
| FR-25 | Shell exit behavior (close on 0, show exit code on non-zero) | M2, M7 | Full | M2 lays groundwork; M7 completes. |
| FR-26 | User-editable configuration file | M6 | Full | |
| FR-27 | Custom keybindings for all operations | M6 | Full | |
| FR-28 | Named profiles (font, color, shell, working directory) | M6 | Full | |
| FR-29 | Profile inheritance (global > workspace > space) | M6 | Full | |
| FR-30 | Named color themes | M6 | Full | |
| FR-31 | Live reload of configuration | M6 | Full | |
| FR-32 | Text selection via mouse and keyboard (Shift+arrow) | M1 | Full | |
| FR-33 | Copy (Cmd+C) and paste (Cmd+V) | M1 | Full | |
| FR-34 | Double-click word select, triple-click line select | M1 | Full | |
| FR-35 | Find-in-scrollback search overlay | M7 | Full | |
| FR-36 | Multiple macOS windows, each displaying one workspace | M4 | Full | |
| FR-37 | Native macOS full-screen mode | M7 | Full | |
| FR-38 | Standard macOS window operations (minimize, zoom, drag-to-resize) | None explicitly | Missing | See Issue #2. |
| FR-39 | Space bar and tab bar visually distinct | M3 | Full | |
| FR-40 | All workspace navigation operable via keyboard | M2, M3, M4 | Full | Covered across multiple milestones. |
| FR-41 | VoiceOver labels for navigation UI | M3 (partial), M7 | Full | M3 adds basic labels; M7 completes. |
| FR-42 | WCAG 2.1 AA contrast ratios | M7 | Full | |
| FR-43 | Pane resize via drag handles, configurable in TOML | M2, M6 | Full | M2 implements drag; M6 makes ratio configurable. |

### Issues Found

**Issue #1: FR-01 workspace reorder via drag-and-drop not fully covered**
- **Specs affected:** M4
- **Severity:** Major
- **Detail:** FR-01 explicitly requires reordering workspaces via drag-and-drop. M4 spec Section 3.2 says "reorderWorkspace -- Not in M4 scope" and suggests deferring it. While the data model supports it, no milestone claims ownership of the drag-and-drop reorder UI for workspaces.
- **Recommended fix:** Either add a Phase 5.1 to M4 or include workspace reorder UI in M7 (daily driver polish). The workspace switcher list is the natural location for drag-and-drop reorder.

**Issue #2: FR-38 (minimize, zoom, drag-to-resize) not explicitly addressed**
- **Specs affected:** None (gap)
- **Severity:** Minor
- **Detail:** FR-38 requires standard macOS window operations. These are default SwiftUI/AppKit behaviors and likely work out of the box, but no spec explicitly verifies this or notes any required configuration. M7 addresses full-screen (FR-37) but does not mention FR-38.
- **Recommended fix:** Add a brief note to M7 or M4 confirming that standard window operations are validated and no special implementation is needed. If `windowStyle(.hiddenTitleBar)` or other customizations are used, they must not break minimize/zoom.

---

## 2. Cross-Milestone Consistency

### 2.1 Data Model Naming

| Concept | M2 Name | M3 Name | M4 Name | M5 Name | Consistent? |
|---------|---------|---------|---------|---------|-------------|
| Split tree root type | `SplitNode` (enum) | `PaneNode` (ref in TabModel) | -- | `SplitNode` / `PaneLeaf` (JSON) | **Inconsistent** -- see Issue #3 |
| Split tree wrapper | `SplitTree` (struct with root + focusedPaneID) | Not referenced | -- | Not referenced | OK (M3 uses TabModel.paneTree + activePaneID instead) |
| Space model | -- | `SpaceModel` | `Space` | `Space` (JSON) | **Inconsistent** -- see Issue #4 |
| Tab model | -- | `TabModel` | -- | `Tab` (JSON) | Minor inconsistency |
| Workspace model | -- | -- | `Workspace` | `Workspace` (JSON) | OK |
| Active pane tracking | `SplitTree.focusedPaneID` | `TabModel.activePaneID` | -- | `Tab.activePaneId` | **Inconsistent field name** -- see Issue #5 |

**Issue #3: Inconsistent naming for pane tree types across M2/M3/M5**
- **Specs affected:** M2, M3, M5
- **Severity:** Major
- **Detail:** M2 defines the type as `SplitNode` (recursive enum with `leaf` and `split` cases). M3 refers to it as `PaneNode` in the TabModel definition ("`paneTree: PaneNode (from M2)`"). M5 defines separate `SplitNode` and `PaneLeaf` types for JSON serialization. The M2 type is `SplitNode` with case `.leaf`, not `PaneNode`. M3 uses `PaneNode` which does not exist in M2.
- **Recommended fix:** Establish a single canonical name. Recommend `SplitNode` (matching M2's definition) for the in-memory type. Update M3 to reference `SplitNode` instead of `PaneNode`. M5's JSON types (`SplitNode`/`PaneLeaf`) are separate serialization representations and can keep their own names, but this should be explicitly documented.

**Issue #4: SpaceModel vs Space naming**
- **Specs affected:** M3, M4
- **Severity:** Minor
- **Detail:** M3 defines the type as `SpaceModel` (an Observable class). M4 refers to `Space` in its Workspace definition. M5 uses `Space` in its JSON schema. These may refer to different layers (model class vs serialization struct), but this should be clarified to avoid confusion during implementation.
- **Recommended fix:** Clarify the naming convention: `SpaceModel` for the Observable runtime class, `Space` for the Codable serialization struct. Apply consistently across all specs.

**Issue #5: focusedPaneID vs activePaneID**
- **Specs affected:** M2, M3
- **Severity:** Minor
- **Detail:** M2 uses `focusedPaneID` in SplitTree. M3 uses `activePaneID` in TabModel. These refer to the same concept. The duplication may cause confusion about which is the source of truth.
- **Recommended fix:** Pick one name. Since M3's TabModel wraps M2's SplitTree, the field should live in one place only. Recommend `activePaneID` on TabModel (which delegates to the split tree). Remove the redundant `focusedPaneID` from SplitTree, or have TabModel delegate to it.

### 2.2 Keyboard Shortcut Conflicts

| Shortcut | M2 Assignment | M3 Assignment | M4 Assignment | M6 Default | Conflict? |
|----------|--------------|--------------|--------------|------------|-----------|
| Cmd+Shift+W | Close pane | Close space | Workspace switcher | `pane_close` AND `workspace_switch` | **CONFLICT** -- see Issue #6 |
| Cmd+Shift+Left/Right | Resize pane | Switch space | -- | `pane_resize_left/right` | **CONFLICT** -- see Issue #7 |
| Cmd+Shift+Up/Down | Resize pane | -- | -- | `pane_focus_up/down` (M6) vs `pane_resize_up/down` (M6) | Partial conflict in M6 |
| Cmd+W | -- | Close tab | -- | `tab_close` | OK |
| Cmd+T | -- | New tab | -- | `tab_create` | OK |

**Issue #6: Cmd+Shift+W is triple-assigned**
- **Specs affected:** M2, M3, M4, M6
- **Severity:** Critical
- **Detail:** M2 assigns Cmd+Shift+W to "Close pane". M3 assigns Cmd+Shift+W to "Close space". M4 assigns Cmd+Shift+W to "Open workspace switcher". M6's keybinding table assigns `pane_close = "cmd+shift+w"` AND `workspace_switch = "cmd+shift+w"`. The same chord cannot map to three different actions.
- **Recommended fix:** Assign distinct shortcuts. Recommended resolution:
  - `workspace_switch` = Cmd+Shift+W (most common operation, deserves the most memorable chord)
  - `pane_close` = Cmd+Shift+X or Cmd+Shift+Q
  - `space_close` = Cmd+Shift+Delete (already suggested in M4 for workspace close, reassign)

  Update M2, M3, M4, and M6 to reflect the agreed assignments.

**Issue #7: Cmd+Shift+Left/Right conflict between pane resize and space switching**
- **Specs affected:** M2, M3, M6
- **Severity:** Critical
- **Detail:** M2 assigns Cmd+Shift+Left/Right to "Resize pane left/right". M3 assigns Cmd+Shift+Right/Left to "Next/previous space". M6's keybinding table reassigns space navigation to `cmd+shift+]` and `cmd+shift+[` for tabs, and `cmd+shift+right/left` for tabs. This is internally inconsistent -- M3 uses Cmd+Shift+Right for space switching, but M6 uses it for tab switching.
- **Recommended fix:** Resolve by establishing a clear modifier convention. Recommended:
  - Tab switching: Cmd+Shift+] and Cmd+Shift+[ (browser-like, per M6)
  - Space switching: Cmd+Shift+Right/Left (per M6's `tab_next`/`tab_prev`... which is mislabeled -- see below)
  - Pane resize: Cmd+Ctrl+Arrow (per M6's resize shortcuts)

  Note: M6 labels `tab_next = "cmd+shift+right"` and `tab_prev = "cmd+shift+left"` but also has `space_next = "cmd+shift+]"` and `space_prev = "cmd+shift+["`. This swaps the M3 assignments where tabs used ] and [ while spaces used arrow keys. This reversal needs to be explicitly decided and all specs updated consistently.

### 2.3 Directory Structure Conflicts

**Issue #8: Inconsistent source directory structures proposed across specs**
- **Specs affected:** M1, M2, M3, M4, M6, M7
- **Severity:** Minor
- **Detail:** Each spec proposes its own directory layout. M1 uses `tian/tian/{layer}/` (e.g., `Core/`, `Renderer/`, `Selection/`). M2 uses `tian/Sources/tian/Features/Pane/`. M3 uses `tian/Sources/App/`, `Models/`, `Views/`, `Input/`. M4 uses `Models/`, `Views/`, `Utilities/`. M6 uses `Sources/tian/Configuration/`, `Keybinding/`, `Theme/`. These are inconsistent -- some use feature-based, some use layer-based organization.
- **Recommended fix:** Since no code exists yet, establish the canonical directory structure in M1 (it runs first). All subsequent specs should defer to M1's convention. Recommend adding a "Project Structure Convention" section to M1 that later specs reference. The M1 spec already has a detailed structure; later specs should adapt to it rather than proposing alternatives.

### 2.4 M5 Persistence Schema vs M2/M3/M4 Data Models

**Issue #9: M5 SplitNode uses `children` array, M2 uses `first`/`second` named fields**
- **Specs affected:** M2, M5
- **Severity:** Major
- **Detail:** M2 defines split nodes with named fields `first` (SplitNode) and `second` (SplitNode). M5's JSON schema defines `children` as "array of exactly 2" elements. While semantically equivalent, this structural mismatch means the Codable serialization will need custom encoding/decoding logic, which M5 Section 2 says should be unnecessary ("SplitNode... will conform to Codable with zero custom serialization logic" -- this claim is in M2 Section 12 but is contradicted by the M5 schema).
- **Recommended fix:** Align the representations. Either M2 should use a `children` array internally, or M5's JSON schema should use `first`/`second` fields. Recommend M5 adopt `first`/`second` to match M2, enabling zero-custom-code Codable conformance as M2 promised.

---

## 3. Dependency Chain Validation

| Spec | Declared Dependencies | Undeclared Dependencies | Forward References | Issues |
|------|----------------------|------------------------|--------------------|--------|
| M1 | None | None | Mentions M6 config, M2 pane splitting, M5 persistence as future | OK |
| M2 | M1 (PTY, renderer, terminal core) | None | Mentions M5 serialization, M6 configurable shortcuts | OK |
| M3 | M1 (PTY spawning), M2 (PaneNode, PaneGridView) | None | Mentions M4 workspace ownership, M6 configurable shortcuts | OK |
| M4 | M1, M2, M3 | None | Mentions M5 persistence, M6 configuration | OK |
| M5 | M1, M2, M3, M4 | None | None | OK |
| M6 | M1, M2, M3, M4, M5 | None | None | OK -- but see Issue #10 |
| M7 | M1, M2, M3, M4, M5, M6 | None | None | OK |

**Issue #10: M6 claims dependency on M5 but does not use M5**
- **Specs affected:** M6
- **Severity:** Minor
- **Detail:** M6 Section 13 says "Persistence (M5) does not persist configuration -- config is always read from the TOML file" and notes that persistence serializes workspace/space names used as config keys. M6 does not actually depend on M5 for any functionality. M6 could be implemented before or in parallel with M5.
- **Recommended fix:** Clarify that M6 has no hard dependency on M5. They can be developed in parallel. The only connection is that M5 persists workspace names that M6 uses as config keys, which is informational, not a build dependency.

---

## 4. Completeness per Spec

### Checklist

| Criterion | M1 | M2 | M3 | M4 | M5 | M6 | M7 |
|-----------|----|----|----|----|----|----|-----|
| Architecture overview | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Data models | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Key algorithms | Yes | Yes | Yes | Yes (fuzzy search) | Yes | Yes | Yes |
| File/module structure | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Error handling | Yes | Yes | Yes | Partial | Yes | Yes | Yes |
| Implementation phases | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Technical risks | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Open questions | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| Performance considerations | Yes | Yes | Yes | Yes | Yes | Yes | Yes |

**Issue #11: M4 lacks detailed error handling section**
- **Specs affected:** M4
- **Severity:** Minor
- **Detail:** M4 covers client-side guards (Section 11) but lacks a dedicated error handling section covering: workspace creation failure, window creation failure, fuzzy search edge cases, and what happens when openWindow/dismissWindow fail.
- **Recommended fix:** Add error handling details for workspace operations. Most are straightforward (log + show alert), but they should be documented.

---

## 5. Gaps and Contradictions

### Gaps

**Issue #12: No spec covers the application menu bar**
- **Specs affected:** All
- **Severity:** Minor
- **Detail:** The PRD implies standard macOS application chrome. No spec defines the menu bar structure (File, Edit, View, Window, Help menus) and which commands are exposed there. M6 mentions that shortcuts should appear in the menu bar (Section 10 deployment checklist), and M4 mentions `.commands { }` blocks, but no spec defines the complete menu structure.
- **Recommended fix:** Add a menu bar specification to M4 or M7. Define which actions appear under which menus. This is important for discoverability.

**Issue #13: Space reordering via drag-and-drop (FR-02) -- specification gap in M3**
- **Specs affected:** M3
- **Severity:** Minor
- **Detail:** M3 covers space reorder via drag-and-drop in Section 4.5, but FR-02 also requires reordering spaces "via drag-and-drop". M3 does address this, but the drag-and-drop for spaces has less detail than for tabs (it shares Section 4.5 rather than having its own detail). This is adequate but terse.
- **Recommended fix:** No action needed -- the shared drag-and-drop section is sufficient.

**Issue #14: Tab renaming in FR-03 -- M3 covers this but FR-03 only says "create, close, reorder"**
- **Specs affected:** M3
- **Severity:** None (positive coverage)
- **Detail:** M3 adds tab renaming, which the PRD does not explicitly require in FR-03 but is a reasonable feature. This is a bonus, not a gap.

**Issue #15: Window geometry persistence gap**
- **Specs affected:** M5, M7
- **Severity:** Major
- **Detail:** M5's JSON schema for workspaces does not include window position/size. M5 Open Question #2 raises this exact issue ("we need to persist window geometry per workspace") and recommends adding `windowFrame` and `isFullscreen`. However, the schema in Section 2 does not include these fields. M7 adds `is_fullscreen` but not window frame (position/size). When restoring, windows would appear at default positions rather than where the user placed them, which degrades the restore experience.
- **Recommended fix:** Add `windowFrame` (x, y, width, height) to the M5 workspace persistence schema. M7 already adds `is_fullscreen`; `windowFrame` should be added alongside it. This is a meaningful part of session restore fidelity.

### Contradictions

**Issue #16: M3 last-space-close behavior contradicts FR-05**
- **Specs affected:** M3, M4
- **Severity:** Major
- **Detail:** FR-05 states: "When the last space in a workspace closes, the workspace closes. When the last workspace closes, the app quits." M3 Section 3.3 says: "If no spaces remain (M3): create a new default space with one tab/pane." M4 acknowledges this needs revision. However, M4 Section 3.2 (deleteWorkspace) says "If this was the last workspace, creates a new default workspace" -- which also contradicts FR-05's "app quits" requirement. Additionally, M4 Section 15 says "closing the last window creates a new default workspace (does not quit)."
- **Recommended fix:** Decide the behavior. The PRD says "app quits" on last workspace close. The specs all create a new default instead. If the PRD is authoritative, update all specs. The current spec behavior (create default) is arguably safer UX. Note this as a deliberate deviation from the PRD with rationale, or update the PRD.

**Issue #17: M2 shell exit behavior (FR-25) partially implemented, then re-implemented in M7**
- **Specs affected:** M2, M7
- **Severity:** Minor
- **Detail:** M2 Section 3.2 specifies FR-25 behavior in detail (exit code 0 closes pane, non-zero keeps pane open with overlay). M7 Section 4 re-specifies FR-25 with more detail (signal handling, restart_shell, persistence of exited state). There is some redundancy and potential for contradiction. M2 says "overlay message" while M7 says "banner rendered within the terminal viewport as styled text" -- these are different rendering approaches.
- **Recommended fix:** M2 should specify only the basic mechanism (detect exit code, trigger close or keep-open). M7 should own the complete FR-25 implementation including rendering approach. Clarify that M2's overlay is a temporary placeholder that M7 replaces with the full banner.

**Issue #18: Profile inheritance direction inconsistency**
- **Specs affected:** M6, PRD
- **Severity:** Minor
- **Detail:** PRD FR-29 says "pane inherits from space, space inherits from workspace, workspace inherits from global." M6 Section 4 describes the resolution chain as: space profile -> workspace profile -> global. These are consistent in direction but the PRD says "pane inherits from space" which implies per-pane profile assignment is possible. M6 does not support per-pane or per-tab profiles -- only per-workspace and per-space. M6 Open Question at the end acknowledges this.
- **Recommended fix:** No action needed for v1. The PRD's mention of "pane inherits from space" describes the inheritance chain, not per-pane assignment. M6's approach is correct.

---

## 6. Technical Feasibility

**Issue #19: SwiftUI WindowGroup(for:) API reliability on macOS 26**
- **Specs affected:** M4
- **Severity:** Major
- **Detail:** M4's multi-window architecture depends heavily on `WindowGroup(for: Workspace.ID.self)` with `openWindow(value:)` and `dismissWindow(value:)`. M4 Open Question #2 raises this concern. These APIs have had behavioral issues on macOS 14/15 (e.g., `dismissWindow` not reliably closing windows, race conditions with rapid open/close). macOS 26 is unreleased, so behavior is unknown.
- **Recommended fix:** M4 already identifies the risk and proposes an `NSWindowController` fallback. This should be elevated from a risk to a Phase 2 gating decision: prototype the SwiftUI approach first and have the `NSWindowController` path ready as a concrete fallback, not just a mentioned option.

**Issue #20: libghostty-vt C ABI stability and scrollback text extraction**
- **Specs affected:** M1, M7
- **Severity:** Major
- **Detail:** M1 depends on libghostty-vt which has an explicitly unstable C ABI. M7's search feature depends on extracting scrollback buffer text from libghostty-vt, but M7 Open Question #1 notes the exact API is unknown. This is the single largest technical uncertainty across all specs.
- **Recommended fix:** Resolve the libghostty-vt version selection and API surface before M1 Phase 1B begins. If scrollback text extraction is not available, M7 should maintain a parallel text buffer as its fallback plan (already mentioned in M7 Section 16). Consider maintaining this parallel buffer from M1 onwards to avoid M7 being blocked.

**Issue #21: Metal renderer per-pane architecture decision**
- **Specs affected:** M1, M2
- **Severity:** Minor (already addressed)
- **Detail:** M2 Open Question #1 asks whether M1 uses a single MTKView or one-per-pane. M2 recommends one-per-pane. M1's spec describes the renderer for a single pane but notes in Section 6.2 that it uses `CAMetalLayer` on an NSView. The architecture supports per-pane instantiation, but M1 does not explicitly state that the renderer is designed for multi-instance usage.
- **Recommended fix:** Add an explicit note to M1 that `TerminalRenderer` and `TerminalMetalView` are designed to be instantiated per-pane (one instance per pane), even though M1 only creates one. This prevents M2 from requiring a renderer refactor.

---

## 7. Summary of Issues by Severity

### Critical (2)

| # | Issue | Specs | Fix Priority |
|---|-------|-------|-------------|
| 6 | Cmd+Shift+W triple-assigned to close pane, close space, and workspace switcher | M2, M3, M4, M6 | Must resolve before M2 implementation begins |
| 7 | Cmd+Shift+Left/Right conflict between pane resize and space/tab switching; M3/M6 swap tab and space shortcut assignments | M2, M3, M6 | Must resolve before M2 implementation begins |

### Major (6)

| # | Issue | Specs | Fix Priority |
|---|-------|-------|-------------|
| 1 | FR-01 workspace reorder via drag-and-drop unowned | M4 | Assign to M4 or M7 |
| 3 | SplitNode vs PaneNode naming inconsistency | M2, M3, M5 | Resolve before M2 implementation begins |
| 9 | M5 JSON children array vs M2 first/second fields | M2, M5 | Resolve before M5 implementation begins |
| 15 | Window geometry (position/size) not in persistence schema | M5, M7 | Add to M5 schema |
| 16 | Last-workspace-close behavior contradicts FR-05 (specs create default instead of quitting) | M3, M4 | Decide and document |
| 19 | SwiftUI WindowGroup(for:) reliability unknown on macOS 26 | M4 | Prototype early in M4 Phase 2 |

### Minor (8)

| # | Issue | Specs | Fix Priority |
|---|-------|-------|-------------|
| 2 | FR-38 (minimize/zoom/resize) not explicitly addressed | Gap | Add verification note |
| 4 | SpaceModel vs Space naming inconsistency | M3, M4 | Clarify naming convention |
| 5 | focusedPaneID vs activePaneID duplication | M2, M3 | Pick one name |
| 8 | Inconsistent directory structures across specs | All | M1 sets convention; others defer |
| 10 | M6 falsely claims dependency on M5 | M6 | Clarify as informational link |
| 11 | M4 lacks detailed error handling | M4 | Add error handling section |
| 12 | No spec covers application menu bar | All | Add to M4 or M7 |
| 17 | M2/M7 FR-25 redundancy with differing rendering approaches | M2, M7 | Clarify M2 as placeholder, M7 as final |

---

## 8. Recommendations

### Immediate Actions (Before Any Implementation)

1. **Resolve keyboard shortcut conflicts** (Issues #6, #7). Produce a single master shortcut map that all specs reference. This is blocking.
2. **Establish canonical type names** (Issues #3, #4, #5). Create a shared type glossary document or add it to M1.
3. **Align split tree representation** between M2 (first/second) and M5 (children array) (Issue #9).

### Pre-M4 Actions

4. **Decide last-workspace-close behavior** (Issue #16). Either update the PRD or update the specs.
5. **Prototype SwiftUI WindowGroup(for:)** on macOS 26 (Issue #19).

### Pre-M5 Actions

6. **Add window geometry to persistence schema** (Issue #15).

### Pre-M7 Actions

7. **Assign workspace reorder ownership** (Issue #1).
8. **Investigate libghostty-vt scrollback text extraction API** (Issue #20). Consider maintaining a parallel text buffer from M1 as insurance.
