# Workspace Directory Picker, Empty-State Fresh Launch & Worktree-Space Identity Fix

**Date:** 2026-04-12
**Status:** Implemented

## Context

Two problems motivated this work:

1. **UX:** Today, new workspaces are created with no default working directory (`createWorkspace()` called with no argument from both the menu and the sidebar "+ New Workspace" button). Workspaces resolve to `$HOME` at runtime, so their mental model is fuzzy — a workspace isn't visibly anchored to any project. Fresh launches also auto-create a default workspace, so there's no opportunity for the user to declare intent at launch time.

2. **Bug:** Clicking the "new worktree space" branch button on a workspace header in the sidebar creates the worktree in the *wrong* workspace. If workspaces A, B, C exist and the user clicks C's button while A is active, the worktree is created in A, at a path like `./worktrees/branch2/branch3` — nested inside A's currently-active worktree space. A secondary symptom ("cannot create more than ~3 worktree spaces in a row") has only been observed after this bug triggers and is believed to be a downstream effect of the nested-worktree state confusing git.

Both issues share a root: workspace identity isn't propagated cleanly through the code. Fixing (2) correctly and redesigning (1) around explicit directory choice gives every workspace a clear anchor and eliminates the ambiguity that allowed the bug to surface.

## Goals

- Every new workspace is anchored to a concrete directory chosen by the user.
- Fresh launch opens the window in an Apple-native empty state rather than auto-creating a default workspace or blocking on a modal picker.
- Closing the last workspace leaves the window open in the empty state (only explicit window close quits the app).
- Clicking the sidebar branch button on any workspace creates a worktree scoped to *that* workspace's repo, regardless of which workspace is currently active.

## Non-goals

- Migrating existing workspaces that currently have `defaultWorkingDirectory = nil`. They continue to fall back to `$HOME` via `WorkingDirectoryResolver`.
- Changing the IPC path (`tian` CLI). It already accepts an explicit path.
- Changing the "Set Directory" UI for editing a workspace's base directory after creation.
- Changing session restoration. Restored workspaces use their persisted directory.

## UX rules

- **Explicit workspace creation** (menu `File → New Workspace` / Cmd+Shift+N, sidebar "+ New Workspace" button, empty-state "+ New Workspace" button) runs through an `NSOpenPanel` directory picker.
- Chosen directory becomes `Workspace.defaultWorkingDirectory`. Workspace name = `URL.lastPathComponent`; if the basename is empty or equal to `/`, fall back to the auto-generated `"Workspace N"`. Dotfile basenames (e.g., `.config`) are kept as-is.
- Cancel behavior for explicit creation: abort, no workspace created.
- **Fresh launch** (no saved session to restore):
  - Window opens immediately with an empty `WorkspaceCollection`.
  - Main content area shows an Apple-native empty state: large `folder.badge.plus` icon, "No Workspaces" title, short subtitle, and a prominent "+ New Workspace" action button.
  - Sidebar is visible (so its own "+ New Workspace" bottom button remains a valid entry point), but the workspace list area is blank.
  - Clicking either "+ New Workspace" button (empty-state or sidebar) runs the same directory picker; on selection the workspace is created and activated.
- **Closing the last workspace** leaves the window open and reverts to the empty state. Only explicit window close (or Cmd+Q) quits the app.
- **UI-testing harness** (`--ui-testing` flag) bypasses the empty state and starts with a default workspace at `$HOME`, matching existing test expectations.
- No git-repo validation. Any directory is accepted.

## Architecture

### New file: `tian/WindowManagement/WorkspaceCreationFlow.swift`

Stateless `@MainActor enum` coordinator.

```swift
@MainActor
enum WorkspaceCreationFlow {
    /// Presents a directory picker and, if the user picks a directory,
    /// creates and activates a workspace in `collection`. Returns the
    /// created workspace, or nil if the user cancelled.
    @discardableResult
    static func createWorkspace(in collection: WorkspaceCollection) -> Workspace?

    // Internal helpers (name derivation is unit-tested):
    static func deriveWorkspaceName(from url: URL) -> String?
    private static func runPicker() -> URL?
}
```

### New file: `tian/View/Workspace/WorkspaceEmptyStateView.swift`

Apple-style empty state rendered when `workspaceCollection.workspaces.isEmpty`. Contains:
- 56pt `folder.badge.plus` SF Symbol, tertiary foreground.
- "No Workspaces" title (`.title2` semibold).
- "Create a workspace to get started." subtitle (`.body` secondary).
- Prominent `borderedProminent` "+ New Workspace" button (`controlSize .large`), bound to Cmd+Shift+N, invoking `WorkspaceCreationFlow.createWorkspace(in:)`.

Wired into `SidebarContainerView.terminalZStack`'s `else if workspaceCollection.workspaces.isEmpty` branch so it sits in the same layout region that would otherwise render terminal panes.

### Modified files

| File | Change |
|---|---|
| `tian/Workspace/WorkspaceCollection.swift` | New `init(startingEmpty: Bool)` that skips default-workspace creation. Original `init(workingDirectory:)` unchanged. |
| `tian/WindowManagement/WindowCoordinator.swift` | `openWindow` gains `empty: Bool = false`. When true, creates a `WorkspaceCollection(startingEmpty: true)`; otherwise preserves existing behavior. |
| `tian/WindowManagement/TianAppDelegate.swift` | Fresh launch calls `openWindow(empty: true)`. UI-testing path still uses `openWindow()` with defaults. Session-restore path unchanged. |
| `tian/WindowManagement/WorkspaceWindowController.swift` | Removed `workspaceCollection.onEmpty = { window.close() }` wiring so the window stays open in empty state when the last workspace is removed. |
| `tian/App/WorkspaceCommands.swift` | Menu `File → New Workspace` calls `WorkspaceCreationFlow.createWorkspace(in:)`. |
| `tian/View/Sidebar/SidebarPanelView.swift` | Sidebar `+ New Workspace` button calls `WorkspaceCreationFlow.createWorkspace(in:)`. |
| `tian/View/Sidebar/SidebarContainerView.swift` | `terminalZStack` shows `WorkspaceEmptyStateView` when no workspaces exist. |

### Bug fix: workspace-identity propagation

| File | Change |
|---|---|
| `tian/View/Sidebar/SidebarContainerView.swift` | Adds `worktreeWorkspaceIDKey = "worktreeWorkspaceID"` userInfo key. |
| `tian/View/Sidebar/SidebarExpandedContentView.swift` | `showWorktreeBranchInput` notification now includes `workspace.id` under `worktreeWorkspaceIDKey`. |
| `tian/View/Workspace/WorkspaceWindowContent.swift` | `BranchInputContext` gains `workspaceID: UUID?`. Receiver extracts the ID; submit passes `repoPath: ctx.repoRoot.path` and `workspaceID: ctx.workspaceID` to `createWorktreeSpace`. Captures `ctx` into `let captured = ctx` before clearing `branchInputContext` to avoid losing state across the async Task. |
| `tian/Worktree/WorktreeOrchestrator.swift` | No code change — `createWorktreeSpace(branchName:existingBranch:repoPath:workspaceID:)` already supported the arguments. |

`WorkspaceWindowController.handleNewWorktreeSpace` (the keyboard-shortcut path) is unchanged; it implicitly targets the active workspace, which is correct for that entry point.

## Data flows

### Flow A — Explicit workspace creation (menu, sidebar, empty state)

```
User triggers creation (Cmd+Shift+N, sidebar +, or empty-state + button)
  → WorkspaceCreationFlow.createWorkspace(in: collection)
      → NSOpenPanel.runModal() (dir-only, single selection, create-dir enabled)
          → Cancel → return nil, no workspace created
          → Pick directory URL:
              → name = deriveWorkspaceName(from: standardizedURL) ?? "Workspace N"
              → collection.createWorkspace(name:, workingDirectory: path)
                   (createWorkspace already activates the new workspace)
              → return newWorkspace
```

### Flow B — Fresh launch

```
TianAppDelegate.applicationDidFinishLaunching
  → session restorable? → yes: existing restore path (unchanged)
  → UI-testing mode?     → yes: windowCoordinator.openWindow()  // $HOME default
  → otherwise:
        windowCoordinator.openWindow(empty: true)
          → WorkspaceCollection(startingEmpty: true)  // no workspaces
          → showWindow → window visible with empty state
```

The empty-state view is rendered because `SidebarContainerView.terminalZStack` sees `displayedSpaceCollection == nil` AND `workspaceCollection.workspaces.isEmpty`. From there the user clicks the in-view "+ New Workspace" button (or sidebar's) and proceeds through Flow A.

### Flow C — Sidebar branch button (bug fix)

```
Click branch button on Workspace C header
  → Post .showWorktreeBranchInput with:
        userInfo[worktreeWorkingDirectoryKey] = C.spaceCollection.resolveWorkingDirectory()
        userInfo[worktreeWorkspaceIDKey]      = C.id
  → WorkspaceWindowContent.onReceive (filtered by workspaceCollection identity)
      → resolve repoRoot + worktreeDir via WorktreeService
      → branchInputContext = { repoRoot, worktreeDir, workspaceID: C.id }
  → BranchNameInputView onSubmit(branch, existing)
      → let captured = ctx
        branchInputContext = nil
        orchestrator.createWorktreeSpace(
            branchName:    branch,
            existingBranch: existing,
            repoPath:      captured.repoRoot.path,
            workspaceID:   captured.workspaceID
        )
  → Orchestrator.resolveWorkspace(workspaceID: C.id) returns Workspace C directly
  → Worktree created at the right repo; Space added to the right workspace
```

## Edge cases

### Picker

- **Empty / `/` basename**: fall back to `"Workspace N"`.
- **Dotfile basename** (`.config`): kept as-is.
- **Symlinks**: standardize via `standardizedFileURL` before persisting.
- **Non-existent / unreadable**: `NSOpenPanel` only returns valid directories.
- **Duplicate base directory**: allowed. Two workspaces anchored at the same repo is a legitimate use case.

### Empty state

- **Last workspace closed**: `WorkspaceWindowController` no longer closes the window on `WorkspaceCollection.onEmpty`. The collection becomes empty; the view re-renders the empty-state. User must explicitly close the window (or Cmd+Q) to quit.
- **Sidebar still visible**: the sidebar's bottom "+ New Workspace" button is a second entry point into Flow A, available even when the workspace list is empty.
- **UI tests bypass the empty state** via `--ui-testing` → `openWindow()` default → `$HOME` workspace. Preserves existing test expectations.

### Bug fix

- **Clicked workspace no longer exists when user submits**: `resolveWorkspace(workspaceID: missingID)` returns nil, and the orchestrator falls through to the existing `activeWorkspaceForKeyWindow()` fallback. Rare; matches existing behavior for missing IDs.
- **`repoPath` no longer a valid git repo**: `WorktreeService.resolveRepoRoot` throws; orchestrator's existing error propagation handles it.

### Error handling

- Picker errors and `createWorkspace` returning nil → treat as cancel. No dialog; "nothing happened" is the natural signal to retry.

## Testing

### Unit tests

- **`WorkspaceCreationFlowTests.swift`** (new): 5 tests covering `deriveWorkspaceName(from:)` — regular directory basename, dotfile kept as-is, trailing slash standardized, root returns nil, empty returns nil.
- **`WorktreeOrchestratorTests.swift`** (extended): `MockWorkspaceProvider` gains `keyWindowWorkspace: Workspace?` property. New regression test `createWorktreeSpaceTargetsSpecifiedWorkspaceNotKeyWindow` asserts that an explicit `workspaceID` overrides the fallback.

`NSOpenPanel`-wrapping code and SwiftUI empty-state view aren't unit-tested; AppKit modals and SwiftUI layouts aren't easily mockable without scaffolding that outweighs the value.

### Manual verification (required)

1. Fresh launch, no saved session → window opens, empty-state view visible (folder.badge.plus icon, "No Workspaces" title, "+ New Workspace" button).
2. Empty-state "+ New Workspace" → picker → pick → workspace seeded with that directory.
3. File → New Workspace (Cmd+Shift+N) → picker → pick → workspace added and activated.
4. Sidebar "+ New Workspace" → picker → cancel → no workspace created.
5. Close the last workspace → window stays open, empty state returns (not closed).
6. **Bug 1 regression:** Create workspaces A and C anchored to different git repos. Active = A. Click sidebar branch button on C → enter branch name → worktree space appears in C, inside C's repo.
7. **Bug 2 regression:** Create several worktree spaces in a row across workspaces. The "cannot create more than 3" symptom does not reproduce.

## Notes on Bug 2

Bug 2 has only been observed as a follow-on effect of Bug 1 — the erroneously-created nested worktree (`./worktrees/branch2/branch3`) confuses git's worktree registry, which is why subsequent creation attempts fail and why the problem self-heals after some time (state settles, or the user closes the bogus spaces). Fixing Flow C should eliminate the trigger. The manual verification step 7 confirms this; if it reproduces after the fix, it is tracked as a separate issue with its own root-cause investigation.
