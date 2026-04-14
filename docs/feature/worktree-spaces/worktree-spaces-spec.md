# SPEC: Worktree Spaces

**Based on:** docs/feature/worktree-spaces/worktree-spaces-prd.md v1.3
**Author:** CTO Agent
**Date:** 2026-04-07
**Version:** 1.0
**Status:** Draft

---

## 1. Overview

This spec covers the implementation of the Worktree Spaces feature, which automates the creation of git worktree-backed Spaces within tian. The feature spans nine implementation surfaces: a TOML configuration parser for `.tian/config.toml`, a `WorktreeService` that orchestrates git operations and file copying, a `WorktreeOrchestrator` that coordinates the end-to-end creation flow (config parsing, git worktree creation, Space creation, setup command execution, layout application), extensions to `SpaceModel` and `SpaceState` for worktree association tracking, new IPC commands (`worktree.create` and `worktree.remove`), new CLI subcommands (`tian-cli worktree create/remove`), UI components (branch name input popover, floating cancel button, sidebar worktree indicator), and a schema migration for session persistence.

The existing model layer provides everything needed for Space creation, pane splitting, and focus management. The feature builds on top of `SpaceCollection.createSpace()`, `PaneViewModel.splitPane()`, `PaneViewModel.fromState()`, the `SplitTree`/`PaneNode` value types, the `GhosttyApp.surfacePwdNotification` (OSC 7 signal for shell readiness), and `ghostty_surface_text()` for typing commands into terminals. The IPC system (`IPCServer`, `IPCCommandHandler`, `IPCClient`) provides the CLI communication channel. Session persistence (`SessionSerializer`, `SessionRestorer`, `SessionStateMigrator`) handles worktree path survival across app restarts.

---

## 2. TOML Configuration

### 2.1 Parser Dependency

A Swift TOML parsing library must be added to `project.yml`. The recommended library is **TOMLKit** (https://github.com/LebJe/TOMLKit), which is a pure Swift package with no platform restrictions. It is added as a Swift Package dependency in `project.yml` and linked to the `tian` target only (not `tian-cli`).

The dependency entry in `project.yml` under `packages`:

| Key | Value |
|-----|-------|
| Package name | `TOMLKit` |
| URL | `https://github.com/LebJe/TOMLKit` |
| Version | `from: "0.6.0"` |

The `tian` target's `dependencies` array gains an entry for the TOMLKit package product.

### 2.2 Configuration Data Model

A new file `tian/Worktree/WorktreeConfig.swift` defines the parsed configuration. All fields are value types (`Sendable`).

**WorktreeConfig** -- top-level parsed configuration:

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| worktreeDir | String | `".worktrees"` | Directory relative to repo root where worktrees are created |
| setupTimeout | TimeInterval | `300` | Timeout in seconds per setup command |
| shellReadyDelay | TimeInterval | `0.5` | Fallback delay in seconds for shell readiness when OSC 7 is not received |
| copyRules | [CopyRule] | `[]` | Files to copy from main worktree to new worktree |
| setupCommands | [String] | `[]` | Ordered shell commands to run during setup |
| layout | LayoutNode? | `nil` | Pane layout tree for the first tab |

**CopyRule** -- a single file copy directive:

| Property | Type | Description |
|----------|------|-------------|
| source | String | Glob pattern relative to repo root (e.g., `.env*`, `config/credentials/*.yml`) |
| dest | String | Destination path relative to repo root. If it ends with `/`, files are placed inside that directory. |

**LayoutNode** -- a recursive layout tree node (mirrors PaneNode structure):

| Case | Properties | Description |
|------|------------|-------------|
| pane | command: String? | Leaf node. `command` is the startup command (nil or empty means plain shell). |
| split | direction: SplitDirection, ratio: Double, first: LayoutNode, second: LayoutNode | Internal split node with two children. |

### 2.3 TOML Parsing Logic

A new file `tian/Worktree/WorktreeConfigParser.swift` contains the parsing logic.

**Entry point:** A static method `parse(fileURL: URL) throws -> WorktreeConfig` that reads the TOML file and produces a `WorktreeConfig`. A companion method `parse(tomlString: String) throws -> WorktreeConfig` accepts raw string content for testing.

**Parsing behavior:**

1. Read the file content as UTF-8 string.
2. Parse with TOMLKit's TOML parser into a `TOMLTable`.
3. Extract top-level scalar fields (`worktree_dir`, `setup_timeout`, `shell_ready_delay`) with defaults for missing fields.
4. Extract the `[[copy]]` array of tables. Each entry must have `source` (String, required) and `dest` (String, required). Log a warning and skip entries missing required fields.
5. Extract the `[[setup]]` array of tables. Each entry must have `command` (String, required). Skip entries missing the field.
6. Extract the `[layout]` table if present. Parse recursively: a table with a `direction` key is a split node (must also have `ratio`, `first`, `second`); a table without `direction` is a pane node (optional `command` field). Validate that `direction` is `"horizontal"` or `"vertical"`, and `ratio` is between 0.0 and 1.0 (clamp if out of range).

**Error handling:** Parsing errors (malformed TOML) are caught and produce an `WorktreeConfigError.parseError(line: Int?, message: String)`. The caller logs the error and falls back to a default `WorktreeConfig()` (FR-002, NFR-003). Individual field validation errors (wrong type, out-of-range) produce warnings via `Log.worktree` and use defaults for that field rather than aborting the parse.

### 2.4 Config File Resolution

The config file path is resolved by `WorktreeService.resolveConfigFile(repoRoot: URL) -> URL?`. It checks for the existence of `<repoRoot>/.tian/config.toml` and returns the URL if it exists, nil otherwise.

---

## 3. Git and Filesystem Service Layer

### 3.1 WorktreeService

A new file `tian/Worktree/WorktreeService.swift` contains all git and filesystem operations. This is a non-UI, non-MainActor type with async methods that run subprocess commands and file I/O on background threads.

**All methods are `static` and return `async throws`. Errors are modeled as `WorktreeError` (see section 3.2).**

**Methods:**

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `resolveRepoRoot(from:)` | `directory: URL` | `URL` | Runs `git -C <dir> rev-parse --show-toplevel`. Throws `notAGitRepo` if exit code is non-zero. |
| `resolveMainWorktreePath(repoRoot:)` | `repoRoot: URL` | `URL` | Runs `git -C <repoRoot> worktree list --porcelain`, parses the first `worktree <path>` line. Throws if parsing fails. |
| `createWorktree(repoRoot:worktreeDir:branchName:existingBranch:)` | `repoRoot: URL`, `worktreeDir: String`, `branchName: String`, `existingBranch: Bool` | `URL` | Constructs the worktree path as `<repoRoot>/<worktreeDir>/<branchName>`. Runs `git worktree add <path> -b <branchName>` (new branch) or `git worktree add <path> <branchName>` (existing). Returns the worktree URL on success. Throws on git errors (branch exists, path exists, etc.) with the raw git stderr. |
| `removeWorktree(repoRoot:worktreePath:force:)` | `repoRoot: URL`, `worktreePath: URL`, `force: Bool` | `Void` | Runs `git -C <repoRoot> worktree remove <path>` (or with `--force`). Throws on failure with git stderr. |
| `pruneEmptyParents(worktreePath:worktreeDir:repoRoot:)` | `worktreePath: URL`, `worktreeDir: String`, `repoRoot: URL` | `Void` | After worktree removal, walks parent directories upward from `worktreePath` to `<repoRoot>/<worktreeDir>` (exclusive). Removes each directory if it is empty. Stops at the first non-empty directory. |
| `copyFiles(copyRules:mainWorktreePath:newWorktreePath:)` | `copyRules: [CopyRule]`, `mainWorktreePath: URL`, `newWorktreePath: URL` | `Void` | For each copy rule, resolves glob patterns against the main worktree path using POSIX `glob()`. Copies matching files to the new worktree, preserving relative paths. Logs a warning per failed file (permission error, missing source) but does not throw (NFR-002). |
| `ensureGitignore(repoRoot:worktreeDir:)` | `repoRoot: URL`, `worktreeDir: String` | `Void` | Checks `<repoRoot>/.gitignore` for the `worktreeDir` value. If not present, appends `\n# tian worktree directory\n<worktreeDir>\n`. If `.gitignore` does not exist, creates it with that content. |
| `branchExists(repoRoot:branchName:)` | `repoRoot: URL`, `branchName: String` | `Bool` | Runs `git -C <repoRoot> rev-parse --verify refs/heads/<branchName>`. Returns `true` if exit code is 0. |
| `worktreePathExists(repoRoot:worktreeDir:branchName:)` | `repoRoot: URL`, `worktreeDir: String`, `branchName: String` | `Bool` | Checks if the directory `<repoRoot>/<worktreeDir>/<branchName>` exists on disk. |

**Subprocess execution:** All git commands are executed using `Process` (Foundation). A private helper method `runGit(arguments:workingDirectory:)` creates a `Process` with `/usr/bin/git`, captures stdout and stderr via `Pipe`, waits for termination, and returns `(exitCode: Int32, stdout: String, stderr: String)`. The helper is `nonisolated` and runs on the caller's async context (which will be a detached task or actor).

**Glob expansion:** The `copyFiles` method uses POSIX `glob()` (via Darwin) to expand source patterns relative to the main worktree path. For each matched file, the relative path within the main worktree is computed, and the file is copied to the same relative path under the new worktree, creating intermediate directories with `FileManager.createDirectory(withIntermediateDirectories: true)`.

### 3.2 WorktreeError

A new enum `WorktreeError` in `tian/Worktree/WorktreeError.swift`:

| Case | Associated Values | Description |
|------|-------------------|-------------|
| notAGitRepo | directory: String | The specified directory is not inside a git repository |
| branchAlreadyExists | branchName: String | Branch exists when trying to create a new one |
| worktreePathExists | path: String | The worktree directory already exists on disk |
| gitError | command: String, stderr: String | Unhandled git error with the full command and stderr |
| uncommittedChanges | path: String | Worktree has uncommitted changes (on remove without force) |
| configParseError | message: String | TOML config parsing failed |
| setupCancelled | | User cancelled setup commands |
| setupTimeout | command: String | A setup command exceeded the timeout |

All cases conform to `Error` and `LocalizedError` with descriptive messages including branch name, worktree path, and the failed command where applicable (FR-031).

---

## 4. Worktree Orchestrator

### 4.1 WorktreeOrchestrator

A new file `tian/Worktree/WorktreeOrchestrator.swift` contains the `WorktreeOrchestrator` class. This is the central coordinator that drives the end-to-end worktree creation and cleanup flows. It is `@MainActor` because it interacts with the model layer (`SpaceCollection`, `SpaceModel`, `PaneViewModel`).

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| windowCoordinator | WindowCoordinator | For resolving existing Spaces across all windows |
| isCreating | Bool (published) | True during creation flow, drives sidebar progress indicator |
| setupCancelled | Bool | Set to true when user cancels setup |

**Creation flow method:** `createWorktreeSpace(branchName:existingBranch:repoPath:workspaceID:) async -> WorktreeCreateResult`

This method implements the full flow from FR-006 through FR-033:

1. **Resolve git repo root** -- Call `WorktreeService.resolveRepoRoot(from: repoPath)`. If `repoPath` is nil, derive it from the active Space's working directory via the SpaceCollection. Fail with `.notAGitRepo` if not in a git repo.

2. **Parse config** -- Call `WorktreeConfigParser.parse(fileURL:)` for `<repoRoot>/.tian/config.toml`. If the file does not exist or parsing fails, use default `WorktreeConfig()`.

3. **Duplicate detection (FR-027)** -- Compute the expected worktree path: `<repoRoot>/<config.worktreeDir>/<branchName>`. Scan all Spaces across all WorkspaceCollections via `windowCoordinator.allWorkspaceCollections`. If any Space has `worktreePath` equal to this URL, focus that Space and return `WorktreeCreateResult(spaceID: existingSpace.id, existed: true)`.

4. **Pre-flight checks** -- If not `existingBranch`, check `WorktreeService.branchExists()`. If the branch exists, throw `branchAlreadyExists`. Check `WorktreeService.worktreePathExists()`. If the path exists but no Space matches, throw `worktreePathExists`.

5. **Set isCreating = true** (drives sidebar progress indicator).

6. **Create worktree on disk** -- Call `WorktreeService.createWorktree()`. This is the first side-effecting step.

7. **Ensure .gitignore (FR-033)** -- Call `WorktreeService.ensureGitignore()`.

8. **Resolve main worktree path (FR-010)** -- Call `WorktreeService.resolveMainWorktreePath()`.

9. **Copy env files** -- Call `WorktreeService.copyFiles()` with the config's copy rules, using the main worktree path as source.

10. **Create Space with single pane (FR-011)** -- On MainActor: call `workspace.spaceCollection.createSpace(workingDirectory: worktreePath.path)`. Set the Space's `name` to `branchName`, `defaultWorkingDirectory` to the worktree URL, and `worktreePath` to the worktree URL. Activate the Space immediately so the user sees it.

11. **Wait for shell readiness (FR-028)** -- Install a one-shot observer on `GhosttyApp.surfacePwdNotification` for the initial pane's surface ID. Use a continuation-based async wait with a timeout of `config.shellReadyDelay`. If OSC 7 arrives, proceed immediately. If timeout fires, proceed with the fallback delay.

12. **Run setup commands (FR-012)** -- For each command in `config.setupCommands`, sequentially:
    - Check `setupCancelled` flag. If true, break.
    - Inject the command text into the pane using `ghostty_surface_text(surface, text, length)` followed by a newline character (`\n`).
    - Wait for shell readiness again (OSC 7 or fallback delay).
    - The timeout per command is `config.setupTimeout` seconds. If readiness is not detected within the timeout, log a warning and proceed to the next command.

13. **Apply layout (FR-013)** -- If `config.layout` is non-nil:
    - Convert the `LayoutNode` tree to a `PaneNodeState` tree. The deepest first child (leftmost leaf, found by traversing `.first` children from root) reuses the initial pane's UUID (FR-032). All other leaves get new UUIDs.
    - Build a new `PaneViewModel` using `PaneViewModel.fromState()` with the constructed `PaneNodeState`, setting `focusedPaneID` to the initial pane's UUID.
    - However, rather than replacing the entire PaneViewModel (which would destroy the initial pane's surface and its history), the orchestrator must apply the layout incrementally. This means: starting from the single-pane state, perform splits to construct the target tree. The implementation walks the `LayoutNode` tree and issues `PaneViewModel.splitPane()` calls in the correct order, matching the target structure. After each new pane is created, wait for shell readiness (OSC 7 or fallback), then type the pane's startup command if any.

    The incremental approach preserves the initial pane's terminal session and its setup output history (FR-032).

14. **Set isCreating = false.** Log success via `Log.worktree`.

15. **Return** `WorktreeCreateResult(spaceID: newSpace.id, existed: false)`.

**Layout application algorithm (step 13, detailed):**

The algorithm traverses the `LayoutNode` tree recursively. At each split node, it:
1. Focuses the pane that corresponds to the "first" child position (which is the current leaf being split).
2. Calls `paneViewModel.splitPane(direction:)` to create the split.
3. Recurses into the first child (which is the original pane, now the first child of the split).
4. Recurses into the second child (which is the newly created pane).

At each leaf node, if a startup command is defined and the leaf is not the initial pane (which already ran setup commands), the orchestrator waits for shell readiness and types the command.

For the initial pane (deepest first child of the layout tree), the startup command is still typed after all splits are applied and shell readiness is detected. Setup command output remains visible because the terminal session is preserved.

**Cleanup flow method:** `removeWorktreeSpace(spaceID:force:workspaceID:) async throws`

1. Resolve the Space by ID across all WorkspaceCollections.
2. Check `space.worktreePath` is non-nil. If nil, this is not a worktree Space -- just close it normally.
3. Resolve the repo root from the worktree path (the worktree's parent chain leads back to the repo).
4. Attempt `WorktreeService.removeWorktree(force: force)`.
5. If removal fails with uncommitted changes and `force` is false, throw `uncommittedChanges`.
6. On success, call `WorktreeService.pruneEmptyParents()`.
7. Remove the Space from its SpaceCollection.

### 4.2 WorktreeCreateResult

A simple value type returned by the creation flow:

| Property | Type | Description |
|----------|------|-------------|
| spaceID | UUID | The ID of the created or found Space |
| existed | Bool | True if an existing Space was focused instead of creating a new one |

### 4.3 Shell Readiness Detection

A new utility `ShellReadinessWaiter` in `tian/Worktree/ShellReadinessWaiter.swift` encapsulates the OSC 7 detection logic.

**Method:** `waitForReady(surface: GhosttyTerminalSurface, timeout: TimeInterval) async`

Implementation:
1. Create an `AsyncStream` or use `withCheckedContinuation`.
2. Install a `NotificationCenter` observer for `GhosttyApp.surfacePwdNotification`, filtering by the surface's UUID.
3. Set a `Task.sleep` timer for `timeout` seconds.
4. Whichever fires first (OSC 7 notification or timeout) resumes the continuation.
5. Remove the observer.

This is reused for every point where shell readiness must be detected: initial pane after Space creation, between setup commands, and for each new pane during layout application.

### 4.4 Text Injection

A new method on `GhosttyTerminalSurface`:

**`sendText(_ text: String)`** -- Wraps `ghostty_surface_text(surface, cString, length)`. The method appends a newline to the text to simulate pressing Enter. This is the mechanism for "typing" commands into the terminal (FR-012, FR-013).

The method requires the surface to be created and running. It is `@MainActor` because `ghostty_surface_text` must be called with a valid surface pointer.

### 4.5 Setup Cancellation

The `WorktreeOrchestrator` exposes a `cancelSetup()` method that sets `setupCancelled = true`. This flag is checked before each setup command in the loop (step 12). Two UI triggers call this method:

1. **Floating cancel button** -- A SwiftUI overlay on the pane view.
2. **Ctrl+C interception** -- During setup, Ctrl+C is intercepted before being sent to the terminal. The interception installs a temporary `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` that checks for Ctrl+C (keyCode 8 with `.control` modifier) and calls `cancelSetup()` instead of forwarding to the terminal. The monitor is removed after setup completes.

When cancelled, the orchestrator logs the cancellation and proceeds directly to layout application (FR-014).

---

## 5. Model Layer Changes

### 5.1 SpaceModel Extension

In `tian/Tab/SpaceModel.swift`, add:

| Property | Type | Description |
|----------|------|-------------|
| worktreePath | URL? | Filesystem path of the associated git worktree. When non-nil, identifies this Space as worktree-backed. |

This is a simple stored `var` property, initialized to `nil` in both existing initializers. The `WorktreeOrchestrator` sets it after creating the Space.

### 5.2 SpaceState Extension

In `tian/Persistence/SessionState.swift`, modify `SpaceState`:

| New Property | Type | Description |
|--------------|------|-------------|
| worktreePath | String? | Persisted worktree path string. Nil for non-worktree Spaces. |

This property is added as an optional `Codable` field. Existing JSON files without this field decode correctly because the field is optional (Codable treats missing optional keys as nil).

### 5.3 SessionSerializer Update

In `SessionSerializer.snapshot()`, the `SpaceState` construction now includes:

`worktreePath: space.worktreePath?.path`

### 5.4 SessionRestorer Update

In `SessionRestorer.buildWorkspaceCollection()`, after creating each `SpaceModel` from `SpaceState`, set:

`space.worktreePath = spaceState.worktreePath.flatMap { URL(fileURLWithPath: $0) }`

Add validation: if `worktreePath` is non-nil but the directory does not exist on disk, set `worktreePath` to nil and log a warning (FR-026). This is done in the `validate()` method alongside existing directory resolution.

### 5.5 SessionStateMigrator Version Bump

The `SessionSerializer.currentVersion` increments from `1` to `2`. A migration `migrations[1]` is registered in `SessionStateMigrator`:

The v1-to-v2 migration iterates through all workspaces, spaces, and adds `"worktreePath": null` to each space object. This is a no-op structurally (the new field is optional), but the migration ensures the version number is correctly bumped for downgrade detection.

Actually, since the new field is optional and Codable handles missing keys gracefully, the migration body can be a simple passthrough that only bumps the version number. The migration function receives a JSON dictionary, iterates nothing, and returns the dictionary as-is (the version bump is handled by the `migrateIfNeeded` method after the chain runs). The key purpose is having the migration entry exist so the version chain is correct.

---

## 6. IPC Layer

### 6.1 New IPC Commands

Two new commands added to the IPC protocol. The `IPCCommandHandler.handle()` switch statement gains two new cases.

**`worktree.create`**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| branchName | String | Yes | The branch name for the worktree |
| existing | Bool | No (default false) | If true, check out an existing branch instead of creating new |
| path | String | No | Override repo root detection. Absolute path to the repository. |
| workspaceId | String (UUID) | No | Target workspace. Defaults to env workspace. |

Response on success: `{ "space_id": "<uuid>", "existed": <bool> }`

The handler resolves the workspace from params or env, creates a `WorktreeOrchestrator`, and calls `createWorktreeSpace()`. Since the creation flow is async (git operations, shell readiness waits), the IPC handler method must be `async`. The existing `IPCCommandHandler.handle()` method is already `async`, so this fits naturally.

Error responses:
- Not a git repo: code 1, message includes directory path
- Branch already exists: code 1, message suggests `--existing`
- Worktree path exists: code 1, message includes path
- Git error: code 1, raw git error message

**`worktree.remove`**

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| spaceId | String (UUID) | Yes | The Space to close and remove the worktree for |
| force | Bool | No (default false) | Force remove even with uncommitted changes |

Response on success: empty `{}`

Error responses:
- Space not found: code 1
- Not a worktree Space: code 1
- Uncommitted changes: code 1, message offers `--force`
- Git error: code 1, raw git error

### 6.2 IPCCommandHandler Integration

In `tian/Core/IPCCommandHandler.swift`:

1. Add a stored property `worktreeOrchestrator: WorktreeOrchestrator` initialized in `init()` with the same `windowCoordinator`.
2. Add two new cases to the `handle()` switch: `"worktree.create"` mapping to `handleWorktreeCreate()` and `"worktree.remove"` mapping to `handleWorktreeRemove()`.
3. Both handler methods are `async` (matching the existing `handleNotify` pattern).

---

## 7. CLI Layer

### 7.1 New CLI Subcommands

A new command group `WorktreeGroup` in `tian-cli/CommandRouter.swift`:

**WorktreeGroup** -- registered in `TianCLI.configuration.subcommands`:

| Subcommand | Definition |
|------------|------------|
| `worktree create` | `WorktreeCreate` struct |
| `worktree remove` | `WorktreeRemove` struct |

**WorktreeCreate:**

| Argument/Option | Type | Description |
|-----------------|------|-------------|
| `branchName` | @Argument String | The branch name (required) |
| `--existing` | @Flag Bool | Check out existing branch instead of creating new |
| `--path` | @Option String? | Override repo root path |
| `--workspace` | @Option String? | Target workspace UUID |

Sends IPC command `worktree.create` with params `branchName`, `existing`, `path`, `workspaceId`. On success, prints the Space UUID to stdout (matching existing create command pattern). Captures `existed` field from response.

**WorktreeRemove:**

| Argument/Option | Type | Description |
|-----------------|------|-------------|
| `spaceId` | @Argument String | The Space UUID to close and remove worktree |
| `--force` | @Flag Bool | Force remove |

Sends IPC command `worktree.remove` with params `spaceId`, `force`.

### 7.2 Entry Point Registration

In `tian-cli/main.swift`, add `WorktreeGroup.self` to `TianCLI.configuration.subcommands`.

---

## 8. UI Components

### 8.1 Branch Name Input Popover

A new SwiftUI view `tian/View/Worktree/BranchNameInputView.swift`:

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| repoRoot | URL | Resolved git repo root, shown in description line |
| worktreeDir | String | Configured worktree directory, shown in description line |
| onSubmit | (String, Bool) -> Void | Callback with (branchName, isExistingBranch) |
| onCancel | () -> Void | Dismiss callback |

**Layout:**
- TextField for branch name, auto-focused on appear using `@FocusState`.
- Segmented Picker with two segments: "New branch" (default) and "Existing branch".
- Description line: small gray text showing `<repoRoot>/<worktreeDir>/<typed-branch-name>` that updates as the user types.
- Enter submits (via `.onSubmit` modifier). Escape cancels (via `.onExitCommand` modifier or key handler).

**Presentation:** Shown as a `.popover` anchored to the "+" button in `SidebarWorkspaceHeaderView`, or as a small `.sheet` on the workspace window. The trigger comes from the keyboard shortcut handler or the context menu action. The popover is presented via a `@State private var showingWorktreeInput: Bool` binding on the `SidebarExpandedContentView` or `WorkspaceWindowContent`.

### 8.2 Floating Cancel Button

A new SwiftUI view `tian/View/Worktree/SetupCancelButton.swift`:

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| onCancel | () -> Void | Callback when tapped |

**Layout:** A small capsule-shaped button in the bottom-right corner of the pane, overlaid using `.overlay(alignment: .bottomTrailing)` in the pane's view hierarchy. Semi-transparent background, "Cancel Setup" label, appears only while setup commands are executing.

**Integration point:** The overlay is added in `PaneView.swift` (the view that hosts a single terminal pane). A new `@State` or environment-based flag `isRunningSetup: Bool` on `PaneView` controls visibility. The `WorktreeOrchestrator` sets this flag (via a binding or notification) when setup starts and clears it when setup ends.

### 8.3 Sidebar Worktree Indicator

In `tian/View/Sidebar/SidebarSpaceRowView.swift`:

When `space.worktreePath != nil`, display a small SF Symbol icon (e.g., `"arrow.triangle.branch"`) next to the Space name, before the tab count badge. The icon uses `.secondary` foreground style and a size of 10pt to remain subtle (matching the existing visual weight).

### 8.4 Sidebar Progress Indicator

In `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift`:

When `WorktreeOrchestrator.isCreating` is true, display a small `ProgressView()` (indeterminate spinner) next to the workspace header's "+" button, with a label "Creating worktree...". The `isCreating` state is accessed via an environment object or a published property on a model accessible from the sidebar.

### 8.5 Worktree Cleanup Confirmation Dialog

A new dialog presented when closing a worktree-backed Space. Follows the pattern established by `CloseConfirmationDialog`.

**New enum `WorktreeCloseDialog`** in `tian/View/Worktree/WorktreeCloseDialog.swift`:

**Static method:** `confirmClose(worktreePath: URL, branchName: String, onRemoveAndClose:, onCloseOnly:, onCancel:)`

Presents an `NSAlert` as a sheet:
- Message: "Remove worktree at `<relative-path>`?"
- Informative text: "Branch: `<branchName>`"
- Buttons: "Remove Worktree & Close" (destructive), "Close Only", "Cancel"

**Integration:** The Space close flow is intercepted in `SidebarExpandedContentView` (sidebar context menu "Close Space" action) and in `SpaceCollection.removeSpace()` (called from keyboard shortcut and CLI). The interception checks if the Space has a `worktreePath`. If so, it presents the dialog before proceeding.

The interception is best placed as a wrapper method on the `WorktreeOrchestrator` or as a static helper that is called from both the sidebar view and the IPC handler before calling `removeSpace()`.

For the CLI path (`worktree.remove` IPC command), the confirmation is handled by the CLI (the user explicitly issued the remove command), so no dialog is shown -- the Space is closed and worktree removed directly.

---

## 9. Keyboard Shortcut and Context Menu

### 9.1 KeyAction Extension

In `tian/Input/KeyAction.swift`, add a new case:

`case newWorktreeSpace`

### 9.2 KeyBindingRegistry Extension

In `tian/Input/KeyBindingRegistry.swift`, in the `defaults()` method, register:

`newWorktreeSpace` mapped to Cmd+Shift+B (characters `"b"`, modifiers `[.command, .shift]`).

### 9.3 WorkspaceWindowController Handler

In `tian/WindowManagement/WorkspaceWindowController.swift`, in the `installKeyboardMonitor()` method's switch statement, add a case for `.newWorktreeSpace`:

1. Resolve the active Space's working directory.
2. Present the `BranchNameInputView` popover/sheet on the current window.
3. When the user submits, create a `WorktreeOrchestrator` and call `createWorktreeSpace()` on a detached Task.

### 9.4 Context Menu Entry

In `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift`, add a new item to the `.contextMenu`:

`Button("New Worktree Space...") { ... }`

This triggers the same flow as the keyboard shortcut: present the branch name input, then create the worktree Space.

---

## 10. Logging

### 10.1 New Logger Category

In `tian/Utilities/Logger.swift`, add:

`static let worktree = Logger(subsystem: "com.tian.app", category: "worktree")`

### 10.2 Logging Points

All log entries include the branch name and worktree path where applicable.

| Stage | Level | Message Pattern |
|-------|-------|-----------------|
| Config parse success | info | "Parsed .tian/config.toml: N copy rules, M setup commands, layout=yes/no" |
| Config parse failure | warning | "Failed to parse .tian/config.toml: <error>. Proceeding without config." |
| Config not found | info | "No .tian/config.toml found at <path>. Using defaults." |
| Repo root resolved | info | "Resolved git repo root: <path>" |
| Duplicate Space found | info | "Worktree Space already exists for <path>, focusing existing Space <id>" |
| Git worktree create | info | "Creating git worktree: <full-command>" |
| Git worktree create success | info | "Created worktree at <path> for branch <name>" |
| Git worktree create failure | error | "Failed to create worktree: <stderr>" |
| File copy success | info | "Copied <N> files from main worktree to <path>" |
| File copy partial failure | warning | "Failed to copy <file>: <error>" |
| .gitignore updated | info | "Appended <worktreeDir> to .gitignore" |
| Space created | info | "Created worktree Space '<name>' (id: <uuid>)" |
| Shell readiness (OSC 7) | debug | "Shell ready (OSC 7) for pane <id>" |
| Shell readiness (timeout) | debug | "Shell ready (fallback delay <N>s) for pane <id>" |
| Setup command start | info | "Running setup command <N>/<M>: <command>" |
| Setup cancelled | info | "Setup cancelled by user after <N>/<M> commands" |
| Setup timeout | warning | "Setup command timed out after <N>s: <command>" |
| Layout applied | info | "Applied layout with <N> panes" |
| Worktree removal success | info | "Removed worktree at <path>" |
| Worktree removal failure | error | "Failed to remove worktree: <stderr>" |
| Parent pruning | debug | "Pruned empty directory: <path>" |
| Restore stale worktree | warning | "Worktree path <path> no longer exists on disk for Space '<name>'. Removing association." |

---

## 11. Type Definitions Summary

### New Files

| File Path | Type | Description |
|-----------|------|-------------|
| `tian/Worktree/WorktreeConfig.swift` | Structs/Enums | `WorktreeConfig`, `CopyRule`, `LayoutNode` |
| `tian/Worktree/WorktreeConfigParser.swift` | Enum (static methods) | TOML parsing logic |
| `tian/Worktree/WorktreeService.swift` | Enum (static async methods) | Git and filesystem operations |
| `tian/Worktree/WorktreeError.swift` | Enum | Error types for worktree operations |
| `tian/Worktree/WorktreeOrchestrator.swift` | Class (@MainActor) | End-to-end creation and cleanup coordinator |
| `tian/Worktree/WorktreeCreateResult.swift` | Struct | Return type from creation flow |
| `tian/Worktree/ShellReadinessWaiter.swift` | Enum (static methods) | OSC 7 + fallback delay shell readiness detection |
| `tian/View/Worktree/BranchNameInputView.swift` | SwiftUI View | Branch name input popover |
| `tian/View/Worktree/SetupCancelButton.swift` | SwiftUI View | Floating cancel button overlay |
| `tian/View/Worktree/WorktreeCloseDialog.swift` | Enum (static methods) | Worktree cleanup confirmation dialog |

### Modified Files

| File Path | Changes |
|-----------|---------|
| `tian/Tab/SpaceModel.swift` | Add `worktreePath: URL?` property |
| `tian/Persistence/SessionState.swift` | Add `worktreePath: String?` to `SpaceState` |
| `tian/Persistence/SessionSerializer.swift` | Include `worktreePath` in snapshot; bump `currentVersion` to 2 |
| `tian/Persistence/SessionStateMigrator.swift` | Add migration `[1]` (passthrough for version bump) |
| `tian/Persistence/SessionRestorer.swift` | Set `worktreePath` on restored SpaceModels; validate directory exists |
| `tian/Core/IPCCommandHandler.swift` | Add `worktreeOrchestrator` property; add `worktree.create` and `worktree.remove` handlers |
| `tian/Core/GhosttyTerminalSurface.swift` | Add `sendText(_ text: String)` method |
| `tian/Input/KeyAction.swift` | Add `newWorktreeSpace` case |
| `tian/Input/KeyBindingRegistry.swift` | Register Cmd+Shift+B for `newWorktreeSpace` |
| `tian/WindowManagement/WorkspaceWindowController.swift` | Handle `.newWorktreeSpace` action |
| `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift` | Add "New Worktree Space..." context menu item; add progress indicator |
| `tian/View/Sidebar/SidebarSpaceRowView.swift` | Add worktree branch icon indicator |
| `tian/View/PaneView.swift` | Add setup cancel button overlay |
| `tian/Utilities/Logger.swift` | Add `Log.worktree` category |
| `tian-cli/CommandRouter.swift` | Add `WorktreeGroup`, `WorktreeCreate`, `WorktreeRemove` |
| `tian-cli/main.swift` | Register `WorktreeGroup.self` in subcommands |
| `project.yml` | Add TOMLKit package dependency; add `tian/Worktree/` to sources |

---

## 12. Performance Considerations

**Async operations:** All git subprocess calls and file I/O run off the main thread via Swift's structured concurrency (`async`/`await`). The `WorktreeService` methods are non-isolated. The `WorktreeOrchestrator` is `@MainActor` but dispatches heavy work to `WorktreeService` via `await`.

**Shell readiness waits:** Each wait has a bounded timeout (`shellReadyDelay`, default 0.5s). In the worst case (no OSC 7 support, N setup commands + M panes in layout), the total wait time is `(N + M) * shellReadyDelay`. With typical values (2 setup commands, 4 panes, 0.5s delay), this is 3 seconds. The setup commands themselves (e.g., `npm install`) dominate the wall time.

**Sidebar responsiveness:** The `isCreating` flag is the only observable state read by the sidebar during creation. The sidebar does not poll or re-render on git operation progress.

**Layout application:** The incremental split approach (calling `splitPane()` multiple times) creates surfaces one at a time. Each `ghostty_surface_new` call takes approximately 10-30ms (per existing `AppMetrics`). For a typical 3-4 pane layout, this is under 100ms of surface creation time.

**No bundle size impact:** TOMLKit is a lightweight pure-Swift package (no binary dependencies).

---

## 13. Migration and Deployment

### 13.1 Schema Migration

`SessionSerializer.currentVersion` changes from 1 to 2. `SessionStateMigrator.migrations` gains an entry at key `1`:

The migration function receives a v1 JSON dictionary and returns it unchanged. The purpose is version tracking only -- the new `worktreePath` field is optional and defaults to `null` when absent from the JSON. The `migrateIfNeeded` method automatically sets the `version` field to `currentVersion` after the migration chain runs.

### 13.2 XcodeGen

After adding new source files, run `xcodegen generate` to regenerate the Xcode project. The new `tian/Worktree/` and `tian/View/Worktree/` directories are automatically picked up because `project.yml` sources from the `tian` directory recursively.

The TOMLKit package dependency must be added to `project.yml` under `packages` and referenced in the `tian` target's `dependencies`.

### 13.3 Rollback

If the feature needs to be rolled back:
- The v2 schema is forward-compatible: v1 code ignores the unknown `worktreePath` field when decoding. However, `SessionStateMigrator` will detect a future version and return nil, causing the restorer to fall back to default state. This is the existing behavior for downgrade scenarios.
- Removing the feature code and decrementing the version to 1 is sufficient. Existing session files with version 2 will be treated as "future version" by the v1 code and ignored gracefully.

---

## 14. Implementation Phases

### Phase 1: TOML Parsing and Config Model
**Files:** `WorktreeConfig.swift`, `WorktreeConfigParser.swift`, `WorktreeError.swift`
**Dependencies:** TOMLKit package added to `project.yml`
**Testable:** Unit tests for TOML parsing (valid config, missing fields, invalid types, nested layout parsing)
**Deliverable:** Config parsing works in isolation. No UI or model changes.

### Phase 2: Git and Filesystem Service
**Files:** `WorktreeService.swift`
**Dependencies:** Phase 1 (for `CopyRule` type)
**Testable:** Integration tests against a real git repository (create temp repo, create worktree, copy files, remove worktree, prune directories, gitignore management)
**Deliverable:** All git and filesystem operations work in isolation.

### Phase 3: Model Layer and Persistence
**Files:** Modified `SpaceModel.swift`, `SessionState.swift`, `SessionSerializer.swift`, `SessionRestorer.swift`, `SessionStateMigrator.swift`
**Dependencies:** None beyond existing code
**Testable:** Unit tests for serialization round-trip with worktreePath, migration from v1 to v2, restore with missing directory
**Deliverable:** Worktree path persists across app restarts.

### Phase 4: Shell Readiness and Text Injection
**Files:** `ShellReadinessWaiter.swift`, modified `GhosttyTerminalSurface.swift`
**Dependencies:** None beyond existing code
**Testable:** Manual test: create a pane, wait for OSC 7, inject text. Verify command appears in terminal.
**Deliverable:** Can programmatically type commands into terminals with shell readiness detection.

### Phase 5: Worktree Orchestrator (Core Flow)
**Files:** `WorktreeOrchestrator.swift`, `WorktreeCreateResult.swift`
**Dependencies:** Phases 1-4
**Testable:** End-to-end test: call orchestrator with a branch name, verify worktree created, Space created, setup commands run, layout applied.
**Deliverable:** Complete creation and cleanup flows work programmatically (no UI trigger yet).

### Phase 6: IPC and CLI
**Files:** Modified `IPCCommandHandler.swift`, new CLI commands in `CommandRouter.swift`, modified `main.swift`
**Dependencies:** Phase 5
**Testable:** End-to-end test: run `tian-cli worktree create <branch>` from within an tian terminal, verify Space created.
**Deliverable:** CLI-driven worktree creation and removal works.

### Phase 7: UI Components
**Files:** `BranchNameInputView.swift`, `SetupCancelButton.swift`, `WorktreeCloseDialog.swift`, modified `SidebarSpaceRowView.swift`, `SidebarWorkspaceHeaderView.swift`, `PaneView.swift`
**Dependencies:** Phase 5 (orchestrator to trigger from UI)
**Testable:** Manual test: press Cmd+Shift+B, enter branch name, verify full flow. Close worktree Space, verify confirmation dialog.
**Deliverable:** Full feature available from both UI and CLI.

### Phase 8: Keyboard Shortcut and Input Registration
**Files:** Modified `KeyAction.swift`, `KeyBindingRegistry.swift`, `WorkspaceWindowController.swift`
**Dependencies:** Phase 7 (branch input view)
**Testable:** Manual test: press Cmd+Shift+B, verify input appears.
**Deliverable:** Keyboard shortcut triggers the full flow.

### Phase 9: Logging and Polish
**Files:** Modified `Logger.swift`, logging calls throughout orchestrator and service
**Dependencies:** All prior phases
**Testable:** Verify log output in Console.app during creation and cleanup
**Deliverable:** Production-ready with comprehensive logging.

---

## 15. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| `ghostty_surface_text()` does not work as expected for injecting commands | High -- core mechanism for setup and startup commands | Low -- function exists in the API and is used by Ghostty's own paste functionality | Verify early in Phase 4 with a simple test. Fallback: use `ghostty_surface_key` to synthesize individual keystrokes (matching the existing `sendTextToSurface` pattern in `TerminalSurfaceView`). |
| OSC 7 not emitted by some shells (fish pre-3.1, custom PS1 without `\e]7;...`) | Medium -- setup commands may be sent before shell is ready | Medium -- depends on user's shell configuration | Fallback delay (configurable, default 0.5s) handles this. Document shell requirements in config file comments. |
| TOML parsing library (TOMLKit) introduces unexpected issues or compile-time overhead | Low -- affects build time, not runtime | Low -- TOMLKit is mature and widely used | Pin to a specific version. If issues arise, TOML parsing can be replaced with a simple hand-written parser for the limited syntax used. |
| Long-running setup commands (e.g., `npm install` for large projects) block the orchestrator | Medium -- user waits for setup, but UI is not blocked since setup runs visibly | Medium | Per-command timeout (configurable, default 300s). Setup runs visibly so user can diagnose hangs. Cancel button and Ctrl+C provide escape hatch. |
| `git worktree add` fails on repos with complex submodule or sparse-checkout configurations | Low -- worktree is created with unexpected state | Low | tian passes through the git error verbatim. User can debug and retry. Out of scope for v1 to handle these edge cases. |
| Race condition between Space close (removing surface) and async worktree removal | Medium -- orphaned worktree directory if removal fails after Space is gone | Low | Remove worktree FIRST (step 4 in cleanup flow), then remove the Space (step 7). If worktree removal fails, the Space remains open so the user can intervene. |
| Ctrl+C interception during setup conflicts with terminal's own Ctrl+C handling | Medium -- could cause unexpected behavior if interception is not clean | Medium | The interception monitor runs at the `NSEvent.addLocalMonitorForEvents` level, which fires before the event reaches the terminal's NSView. The monitor consumes the event (returns nil) and calls `cancelSetup()`. After setup ends, the monitor is removed and Ctrl+C works normally. |
| Concurrent worktree creation requests (user triggers twice rapidly) | Low -- could create duplicate worktrees or race on Space creation | Low | Duplicate detection (FR-027) catches this: the second request finds the Space created by the first and focuses it. Additionally, the `isCreating` flag prevents the UI from triggering a second creation while one is in progress. |

---

## 16. Open Technical Questions

| Question | Context | Impact if Unresolved |
|----------|---------|---------------------|
| Should `ghostty_surface_text()` be preferred over `ghostty_surface_key()` for text injection? | `ghostty_surface_text()` takes a string directly. `ghostty_surface_key()` requires constructing key events. The Ghostty source uses `ghostty_surface_text()` for paste operations. | Low -- both approaches work. Phase 4 will validate `ghostty_surface_text()` first. |
| Should the layout application create all splits first, then send all startup commands, or interleave? | Creating all splits first is simpler. Interleaving (send command to each pane as it is created) means earlier panes start running sooner. | Low -- the difference is milliseconds for the split operations themselves. Spec recommends: create all splits first, then send commands to all panes after shell readiness. This avoids complexity with partially-built trees. |
| Can the floating cancel button coexist with the terminal's mouse tracking (ghostty captures mouse events)? | The cancel button is a SwiftUI overlay above the NSView-based terminal. SwiftUI handles hit testing before the terminal view. | Low -- SwiftUI overlays correctly intercept clicks before the underlying NSView. Standard SwiftUI hit testing handles this. |
