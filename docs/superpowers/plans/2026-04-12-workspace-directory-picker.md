# Workspace Directory Picker Implementation Plan

> **For agentic workers:** This plan was executed via superpowers:subagent-driven-development. See the spec at `docs/superpowers/specs/2026-04-12-workspace-directory-picker-design.md` for the final design.

**Goal:** Anchor every explicitly-created workspace to a user-chosen directory via an `NSOpenPanel` picker, open fresh launches into an Apple-native empty state rather than auto-creating a default workspace, and fix the sidebar branch-button bug that creates worktree spaces in the wrong workspace.

**Architecture:** A new `WorkspaceCreationFlow` coordinator (`@MainActor enum`) centralizes "pick directory → create workspace" for the menu, sidebar, and empty-state buttons. `WorkspaceCollection` gains an empty-collection init variant; `WorkspaceWindowController` no longer auto-closes on last-workspace removal; a new `WorkspaceEmptyStateView` renders the folder.badge.plus empty state inside `SidebarContainerView.terminalZStack`. The worktree-identity bug is fixed by propagating the clicked workspace's UUID through the existing `showWorktreeBranchInput` notification into `WorktreeOrchestrator.createWorktreeSpace(workspaceID:repoPath:)`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit (`NSOpenPanel`, `NSWindow`), Swift Testing framework (`@Test`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-04-12-workspace-directory-picker-design.md`

---

## Part 1: Bug fix — workspace identity propagation

### Task 1: Pass clicked workspace's ID in the branch-input notification

**Files:**
- Modify: `aterm/View/Sidebar/SidebarContainerView.swift`
- Modify: `aterm/View/Sidebar/SidebarExpandedContentView.swift`

Add `worktreeWorkspaceIDKey = "worktreeWorkspaceID"` to the `Notification` extension in `SidebarContainerView.swift`. Update the sidebar `onNewWorktreeSpace` closure in `SidebarExpandedContentView.swift` to include `Notification.worktreeWorkspaceIDKey: workspace.id` in the userInfo dictionary.

Commit message line 1: `🐛 fix(sidebar): include clicked workspace ID in worktree branch-input notification`.

### Task 2: Thread workspace ID through `BranchInputContext` to `createWorktreeSpace`

**Files:**
- Modify: `aterm/View/Workspace/WorkspaceWindowContent.swift`

Add `workspaceID: UUID?` field to `BranchInputContext`. Extract the ID from userInfo in the `.showWorktreeBranchInput` receiver. In `onSubmit`, copy `ctx` to `let captured = ctx` before clearing `branchInputContext`, then pass `repoPath: captured.repoRoot.path` and `workspaceID: captured.workspaceID` to `createWorktreeSpace`.

Commit message line 1: `🐛 fix(worktree): pass clicked workspace ID and repo path to createWorktreeSpace`.

### Task 3: Regression test — `createWorktreeSpace(workspaceID:)` targets the specified workspace

**Files:**
- Modify: `atermTests/WorktreeOrchestratorTests.swift`

Extend `MockWorkspaceProvider` with `var keyWindowWorkspace: Workspace?`; change `activeWorkspaceForKeyWindow()` to return it (default nil preserves existing tests). Append `createWorktreeSpaceTargetsSpecifiedWorkspaceNotKeyWindow` test: two repos, set mock's key-window to A, call `createWorktreeSpace(repoPath: repoC, workspaceID: workspaceC.id)`, assert space lands in C not A. `defer` cleanup for both repos and the central `.worktrees/<repoCName>` base.

Commit message line 1: `✅ test(worktree): regression for workspace ID targeting in createWorktreeSpace`.

---

## Part 2: Workspace directory picker

### Task 4: Add `WorkspaceCreationFlow` skeleton + `deriveWorkspaceName` (TDD)

**Files:**
- Create: `aterm/WindowManagement/WorkspaceCreationFlow.swift`
- Create: `atermTests/WorkspaceCreationFlowTests.swift`

Create `@MainActor enum WorkspaceCreationFlow` with a single helper:

```swift
static func deriveWorkspaceName(from url: URL) -> String? {
    let basename = url.standardizedFileURL.lastPathComponent
    if basename.isEmpty || basename == "/" { return nil }
    return basename
}
```

Add 5 Swift Testing tests: regular dir → basename, dotfile dir kept as-is, trailing slash standardized, `/` → nil, empty → nil.

After adding the new files run `xcodegen generate` (the `.gitignore` effectively excludes `project.pbxproj`, so the generated project file is not committed; every build runs `xcodegen generate` via `scripts/build.sh`).

Commit message line 1: `✨ feat(workspace): add WorkspaceCreationFlow with name derivation helper`.

### Task 5: Add picker-based `createWorkspace(in:)` to `WorkspaceCreationFlow`

**Files:**
- Modify: `aterm/WindowManagement/WorkspaceCreationFlow.swift`

Add two methods to the enum:

```swift
@discardableResult
static func createWorkspace(in collection: WorkspaceCollection) -> Workspace? {
    guard let url = runPicker() else { return nil }
    let standardized = url.standardizedFileURL
    if let name = deriveWorkspaceName(from: standardized) {
        return collection.createWorkspace(name: name, workingDirectory: standardized.path)
    } else {
        return collection.createWorkspace(workingDirectory: standardized.path)
    }
}

private static func runPicker() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    panel.message = "Choose a directory for this workspace"
    return panel.runModal() == .OK ? panel.url : nil
}
```

`WorkspaceCollection.createWorkspace` already activates the new workspace internally — no manual activation required.

Commit message line 1: `✨ feat(workspace): add NSOpenPanel-backed createWorkspace flow`.

### Task 6: Wire the menu "New Workspace" button through `WorkspaceCreationFlow`

**Files:**
- Modify: `aterm/App/WorkspaceCommands.swift`

Replace `controller.workspaceCollection.createWorkspace()` in the "New Workspace" menu action with `WorkspaceCreationFlow.createWorkspace(in: controller.workspaceCollection)`. Cmd+Shift+N shortcut unchanged.

Commit message line 1: `✨ feat(workspace): route File → New Workspace through directory picker`.

### Task 7: Wire the sidebar "+ New Workspace" button through `WorkspaceCreationFlow`

**Files:**
- Modify: `aterm/View/Sidebar/SidebarPanelView.swift`

Replace `workspaceCollection.createWorkspace()` inside `newWorkspaceButton`'s Button action with `WorkspaceCreationFlow.createWorkspace(in: workspaceCollection)`. Label/frame/accessibility unchanged.

Commit message line 1: `✨ feat(sidebar): route New Workspace button through directory picker`.

---

## Part 3: Empty-state fresh launch

### Task 8: Add empty-collection support + stop auto-closing the window when empty

**Files:**
- Modify: `aterm/Workspace/WorkspaceCollection.swift`
- Modify: `aterm/WindowManagement/WindowCoordinator.swift`
- Modify: `aterm/WindowManagement/AtermAppDelegate.swift`
- Modify: `aterm/WindowManagement/WorkspaceWindowController.swift`

1. Add `init(startingEmpty: Bool)` to `WorkspaceCollection` that initializes `workspaces = []` with a sentinel `activeWorkspaceID = UUID()`. Original `init(workingDirectory:)` unchanged.
2. Add `empty: Bool = false` parameter to `WindowCoordinator.openWindow`. When true, create `WorkspaceCollection(startingEmpty: true)`; otherwise `WorkspaceCollection(workingDirectory: initialWorkingDirectory)`.
3. In `AtermAppDelegate.applicationDidFinishLaunching`, add a `else if isUITesting { openWindow() }` branch and a final `else { openWindow(empty: true) }` branch.
4. Remove the `workspaceCollection.onEmpty = { self?.window?.close() }` wiring in `WorkspaceWindowController.init`. Closing the last workspace now leaves the window open; the view layer renders the empty state.

Commit message line 1: `✨ feat(workspace): support empty WorkspaceCollection and keep window open when empty`.

### Task 9: Add `WorkspaceEmptyStateView` + show it when no workspaces exist

**Files:**
- Create: `aterm/View/Workspace/WorkspaceEmptyStateView.swift`
- Modify: `aterm/View/Sidebar/SidebarContainerView.swift`

Create `WorkspaceEmptyStateView` with an Apple-native layout:
- 56pt `folder.badge.plus` SF Symbol, tertiary foreground.
- "No Workspaces" title, `.title2` semibold.
- "Create a workspace to get started." subtitle, `.body` secondary.
- `borderedProminent` "New Workspace" button (`controlSize .large`), bound to Cmd+Shift+N, calling `WorkspaceCreationFlow.createWorkspace(in: workspaceCollection)`.

In `SidebarContainerView.terminalZStack`, add an `else if workspaceCollection.workspaces.isEmpty { WorkspaceEmptyStateView(workspaceCollection: workspaceCollection) }` branch after the existing `if let spaceCollection = displayedSpaceCollection { ... }` block. The sidebar and its bottom "+ New Workspace" button remain visible in empty state (second entry point into Flow A).

Run `xcodegen generate` since a new Swift file was added.

Commit message line 1: `✨ feat(workspace): add Apple-style empty-state view when no workspaces exist`.

---

## Verification

- **Unit tests:** `xcodebuild test -project aterm.xcodeproj -scheme aterm -derivedDataPath .build -only-testing:atermTests`. Expected 486/488 pass (the 2 pre-existing `NotificationManagerTests` failures are unrelated environmental issues — macOS notification permissions in the test host).
- **Manual acceptance:** see spec § Testing.

## Implementation History

This plan was iterated during implementation. An intermediate design explored a blocking modal first-launch picker with a "Quit aterm" accessory button; it was reverted in favor of the empty-state design documented here. The reverted commits remain in the branch history for traceability.
