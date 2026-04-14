# Unified Space Creation Flow — Design

**Date:** 2026-04-14
**Branch:** workspace-creation-flow
**Status:** Draft

## Summary

Replace the two separate space-creation surfaces (regular `+` button / worktree branch-icon button, plus their two keybindings) with one unified modal. The modal contains a single text field and a "Create worktree" checkbox. When unchecked, the input is a space name. When checked, the input is both the branch name and the space name, and a recency-sorted branch list with dropdown-style arrow-key navigation appears below the checkbox.

## Goals

- One entry point — one button, one shortcut.
- Eliminate the auto-generated "Space N" default — space names are user-provided (or derived from a branch name).
- Unify and simplify the mental model: space creation is one flow with an optional worktree toggle.
- Preserve the existing branch-list machinery (fetching, in-use detection, duplicate prevention, collision warnings).

## Non-goals

- Changing the worktree creation pipeline itself (`WorktreeOrchestrator` is unchanged).
- Cross-session persistence of the checkbox state (in-memory only for now).
- Uniqueness enforcement on space names (tian already allows duplicates).
- Changes to session-restore format.

## UX

### Triggers

- **Sidebar button.** `SidebarWorkspaceHeaderView` loses the branch-icon button. The `+` button becomes the sole entry point, with a slightly larger icon / hit area. Accessibility label: "New space". Tooltip: "New space (⇧⌘T)".
- **Keybinding.** `⇧⌘T` (existing `newSpace` binding) opens the modal. `⇧⌘B` (`newWorktreeSpace`) is retired.
- Both paths post a single `Notification.Name("NewSpaceRequested")` carrying `workspaceID`.

### Modal layout

Reuses the current modal-overlay presentation of `BranchNameInputView`. Layout, top-to-bottom:

1. **Title** — "New space"
2. **Text field** — auto-focused on appear; placeholder adapts to the checkbox:
   - unchecked: "Space name"
   - checked:   "Branch name"
3. **Checkbox** — "Create worktree"
   - Default = `workspace.lastCreateWorktreeChoice ?? false` (in-memory, per-workspace, resets on app relaunch).
   - Disabled (grey, tooltip "Not a git repository") when `workspace.defaultWorkingDirectory` is not inside a git repo.
4. **Branch list** — only when checkbox is checked.
   - Empty input → all branches, sorted by recency (local preferred, remotes de-duped).
   - Typed input → filtered list.
   - Rows show badges (local/origin/both), relative commit date, "in use" dimming for branches already in a worktree.
5. **Footer** — resolved worktree path, sync status, or validation error (only one at a time).
6. **Actions** — `[Cancel] [Create]`. Submit label is always "Create".

### Keyboard

- `Tab` cycles field → checkbox → Create.
- `↑/↓` move the highlight in the branch list (only when list visible). The text field is **not** modified by arrow-key movement — highlight and `inputText` are independent.
- `Enter` submits if Create is enabled.
- `Esc` cancels the modal.

### Highlight semantics

- `BranchListViewModel.recomputeRows` already auto-highlights the first selectable row whenever a non-empty filter produces matches. This is preserved.
- New rule: when `query` is empty (browse mode), no row is auto-highlighted. This prevents Enter from silently checking out the most-recent branch when the user just opens the modal and presses Enter without thinking. (The user can still arrow-down to start selecting, which will then assign a highlight.)

### Create button enabled

Create is enabled iff **all** of:

- `inputText` is non-empty (after sanitization).
- If `worktreeEnabled == true`: the workspace is a git repo, `inputText` contains no disallowed git-ref characters, and the resolved branch (see Submit semantics) is not an already-in-use worktree.
- No orchestrator error is currently displayed in the footer (error blocks retry only if the input is still identical; editing clears the error).

### Input sanitization

When worktree is checked, the text field is a branch name. Sanitization rules:

- **Space → `-` live.** Each space keystroke is rewritten to `-` in the field as the user types. Applies to both newly typed and pasted content.
- **Other invalid git-ref characters are not allowed.** Characters that git rejects in ref names (`~`, `^`, `:`, `?`, `*`, `[`, `\`, leading `-`, `..`, etc.) are not rewritten. Instead, the footer shows a validation error and Create is disabled until the user fixes the input.

When worktree is unchecked, no sanitization is applied — spaces and any other printable characters are accepted in a space name.

### Submit semantics

**Unchecked (plain space):**

1. Validate `inputText` non-empty (Create is disabled otherwise).
2. Call `SpaceCollection.createSpace(name: inputText, workingDirectory: <resolved working directory string>)`. Working directory is resolved via the existing `spaceCollection.resolveWorkingDirectory()` helper (returns a `String`).
3. Dismiss modal.

**Checked (worktree):**

1. Resolve the branch reference. The branch list view model is the source of truth for "is this a known branch":
   - If `branchListViewModel.selectedRow()` is non-nil (a row is highlighted) → use that row's branch (checkout existing). The `displayName` is the branch name; if `remoteRef` is set, the orchestrator checks out from the remote.
   - Else, treat `inputText` as a new branch name. (Note: when the user types an exact match of an existing branch, the filter narrows to that one row and the auto-highlight rule selects it — so this path naturally subsumes the "exact-match-while-typing" case.)
2. Dismiss the modal immediately, then call `WorktreeOrchestrator.createWorktreeSpace(branchName: <name>, existingBranch: <bool>, remoteRef: <ref?>, repoPath: <repo path>, workspaceID: <id>)`. The branch name is also used for `SpaceModel.name` (the orchestrator already does this — no API change).
3. On orchestrator failure, the existing alert pipeline (`worktreeOrchestrator.lastError`) surfaces the error. Modal does not stay open.

## Architecture

### Affected files

| File | Change |
|---|---|
| `tian/View/Worktree/BranchNameInputView.swift` | Renamed & refactored to `tian/View/CreateSpace/CreateSpaceView.swift`. Segmented "New/Existing branch" picker removed; checkbox added; placeholder switches; live space→`-` sanitization in worktree mode. |
| `tian/View/Worktree/BranchListViewModel.swift` | Moved to `tian/View/CreateSpace/BranchListViewModel.swift`. One behavior tweak: `recomputeRows()` does **not** auto-highlight when the query is empty. The `Mode` enum becomes unused (kept for backwards-compat with anyone using the type, or deleted in the same change — see plan). |
| `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift` | Remove `arrow.triangle.branch` button and the `onNewWorktreeSpace` parameter. Enlarge `+` icon (font size 14, hit area unchanged). Update accessibility label / context-menu copy from "New Worktree Space..." to "New Space...". `onAddSpace` now posts the unified notification (caller in `SidebarExpandedContentView` posts the notification — see below). |
| `tian/View/Sidebar/SidebarExpandedContentView.swift` | `addSpace(to:)` posts `Notification.Name.showCreateSpaceInput` (renamed from `showWorktreeBranchInput`) with `Notification.createSpaceWorkspaceIDKey`. Removes the `onNewWorktreeSpace` closure. |
| `tian/View/Sidebar/SidebarContainerView.swift` | Renames `Notification.Name.showWorktreeBranchInput` → `showCreateSpaceInput`. Removes `worktreeWorkingDirectoryKey` (no longer needed — the listener resolves the working directory itself from the workspace). Renames `worktreeWorkspaceIDKey` → `createSpaceWorkspaceIDKey`. |
| `tian/Input/KeyAction.swift` | Remove `case newWorktreeSpace`. |
| `tian/Input/KeyBindingRegistry.swift` | Remove the `.newWorktreeSpace` binding. `newSpace` (⇧⌘T) is unchanged. |
| `tian/WindowManagement/WorkspaceWindowController.swift` | Remove the `.newWorktreeSpace` switch case and the `handleNewWorktreeSpace()` helper. The `.newSpace` case stops calling `collection.createSpace(workingDirectory:)` directly and instead posts `Notification.Name.showCreateSpaceInput` with the workspace ID — same path as the sidebar `+` button. |
| `tian/Tab/SpaceCollection.swift` | Add optional `name: String?` parameter to `createSpace(name:workingDirectory:)`. `nil` preserves existing "Space N" auto-naming; non-nil uses the given name verbatim. |
| `tian/Workspace/Workspace.swift` | Add `@Observable` transient property `var lastCreateWorktreeChoice: Bool?` (default `nil`). Not added to `WorkspaceSnapshot` — does not persist across launches. |
| `tian/View/Workspace/WorkspaceWindowContent.swift` | Replace `branchInputContext: BranchInputContext?` with `createSpaceRequest: CreateSpaceRequest?`. Listen for `.showCreateSpaceInput`. Render `CreateSpaceView` as overlay when set. |

### Trigger flow

```
Sidebar "+" button ───┐
                      ├──► post .showCreateSpaceInput
Keybinding ⇧⌘T ──────┘    object: workspaceCollection
                          userInfo: { createSpaceWorkspaceIDKey: <workspace.id> }

WorkspaceWindowContent (filters object === workspaceCollection)
  └──► sets @State createSpaceRequest = CreateSpaceRequest(workspaceID:)
         └──► overlay renders CreateSpaceView(workspace:, ...)
```

### `CreateSpaceView` state

- `@State inputText: String = ""`
- `@State worktreeEnabled: Bool` — initial from `workspace.lastCreateWorktreeChoice ?? false`; when the user toggles, write back to `workspace.lastCreateWorktreeChoice`.
- `@State isGitRepo: Bool? = nil` — resolved asynchronously on appear via the existing repo-root resolver. Checkbox stays disabled until this resolves.
- `@State highlightedRowIndex: Int? = nil` — arrow-key highlight. `nil` when no row is highlighted. Reset on each list reload (filter change).
- `@State branchList: BranchListViewModel` — the app uses `@MainActor @Observable` classes, so `@State` is the correct property wrapper (not `@StateObject`). Created once per modal presentation; kept alive for the life of the modal even when the checkbox is toggled off (toggling is instant, cheap). Only instantiates git subprocesses when `worktreeEnabled` becomes `true` at least once.

### `SpaceCollection.createSpace` change

```swift
// Before
@discardableResult
func createSpace(workingDirectory: String = "~") -> SpaceModel

// After
@discardableResult
func createSpace(name: String? = nil, workingDirectory: String = "~") -> SpaceModel
```

- `name == nil` → existing behavior: auto-name "Space N" (preserved for callers that don't yet supply names — e.g. session restore paths and tests).
- `name != nil` → use `name` verbatim. No trimming beyond what the view already did. No uniqueness check.

Callers updated: `CreateSpaceView` always passes a non-nil name. The `WorktreeOrchestrator` already constructs `SpaceModel` directly (it does not call `createSpace`); it remains unchanged on this axis.

### Retired code

- `newWorktreeSpace` keybinding entry and its dispatch.
- `WorktreeSpaceRequested` notification if it was distinct from a general create-space notification.
- Worktree button in `SidebarWorkspaceHeaderView` and all `onNewWorktreeSpace` closure plumbing up through the sidebar tree.
- The segmented "New branch / Existing branch" picker (UI + any supporting enum/state).

## Errors & edge cases

- **Not a git repo + checkbox somehow checked.** Shouldn't be reachable (checkbox disabled), but as a guard: footer shows "Workspace is not a git repository", Create disabled.
- **Invalid branch characters.** Footer validation error, Create disabled until fixed.
- **Exact-match typed branch already in use as a worktree.** Row dimmed with "in use" badge (existing). Typing exact match → footer shows "In use at `<path>`", Create disabled.
- **Worktree creation failure mid-flight.** Existing orchestrator error propagation; modal stays open, footer shows the error, user can retry or cancel.
- **Branch-list fetch is slow / offline.** Cached list shown with a "syncing…" footer hint (existing behavior preserved).
- **Rapid checkbox toggle.** View model is kept alive for modal lifetime; toggle just hides/shows the list.
- **Empty workspace (no spaces yet).** Same flow; no special-case.

## Testing

**Unit**

- `SpaceCollection.createSpace(name:workingDirectory:)`:
  - `name == nil` → auto-naming "Space N" preserved (regression-guard for session restore).
  - `name == "custom"` → space has that name.
  - Duplicate names allowed (two consecutive calls with the same name both succeed).
- Branch resolution logic (pure function, isolated from the view):
  - Given `inputText` and a branch list snapshot → returns one of `{.existing(Branch), .new(name: String), .invalid(reason)}`.
  - Exact match → `.existing`.
  - No match and valid chars → `.new`.
  - Invalid chars → `.invalid`.
  - Empty string → `.invalid(.empty)` (Create button disabled).
- Sanitization:
  - `" "` → `"-"`.
  - `"foo bar baz"` → `"foo-bar-baz"`.
  - `"foo~bar"` unchanged (flagged as invalid downstream).
  - Applied only when `worktreeEnabled == true`.

**View-level (SwiftUI previews or snapshot tests)**

- `CreateSpaceView` in four states:
  1. worktree-off + empty
  2. worktree-off + typed name
  3. worktree-on + empty (browse mode, list populated)
  4. worktree-on + typed input matching an existing branch (exact-match hint in footer)
- Checkbox disabled state when not a git repo.

**Integration**

- Pressing ⇧⌘T posts `NewSpaceRequested` with the current workspace ID.
- `WorkspaceWindowContent` shows `CreateSpaceView` on receipt.
- ⇧⌘B is unbound (no key handler).

## Open questions

_None — all resolved during brainstorm (see conversation log)._

## Follow-ups (not in scope)

- Persist `lastCreateWorktreeChoice` across app launches (add to `SessionState`).
- Consider auto-highlighting the top list row when the modal first opens with worktree on, so Enter picks the most-recent branch.
- Keyboard shortcut hint in the modal footer.
