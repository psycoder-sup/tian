# SPEC: CLI Tool (`aterm`)

**Based on:** docs/feature/cli-tool/cli-tool-prd.md v1.2
**Author:** CTO Agent
**Date:** 2026-04-05
**Version:** 1.0
**Status:** Draft

---

## 1. Overview

This spec covers the implementation of a command-line tool (`aterm-cli`) that communicates with the running aterm application over a Unix domain socket to manage the workspace hierarchy, report pane status to the sidebar, and trigger macOS system notifications. The feature spans eight implementation surfaces: a new Swift executable target for the CLI binary, a Unix domain socket IPC server embedded in the app, environment variable injection into the ghostty surface config at PTY spawn time, IPC command handlers that dispatch to the existing `@MainActor` model layer, an observable status model for sidebar integration, `UNUserNotificationCenter` integration with lazy authorization and click-to-focus, a file-based command log, and XcodeGen build integration for the new target.

The existing model layer (`WorkspaceCollection`, `SpaceCollection`, `SpaceModel`, `TabModel`, `PaneViewModel`, `SplitTree`) already provides all CRUD and navigation methods the CLI needs. The IPC handlers are thin dispatchers that validate inputs, check process safety via `ProcessDetector`, perform `@MainActor` calls into the model layer, and serialize responses. The CLI binary is a stateless client that serializes a request, writes it to the socket, reads a response, and exits.

---

## 2. IPC Protocol

### 2.1 Socket Location and Lifecycle

The socket path uses the pattern `$TMPDIR/aterm-<uid>.sock` where `<uid>` is the numeric user ID from `getuid()`. Using `$TMPDIR` (which resolves to a per-user temporary directory on macOS, typically `/var/folders/.../T/`) avoids path length issues that `~/Library/Application Support/` could cause (Unix domain socket paths are limited to 104 bytes on macOS).

**Server lifecycle** (managed by a new `IPCServer` actor in the app):

| Event | Action |
|-------|--------|
| App launch (`applicationDidFinishLaunching` in `AtermAppDelegate`, line 9) | Create `IPCServer` instance. Call `start()` which: (1) checks for stale socket file and removes it, (2) creates the socket with `socket(AF_UNIX, SOCK_STREAM, 0)`, (3) binds to the path, (4) sets file permissions to `0o600` via `chmod`, (5) calls `listen()` with backlog 5, (6) begins accepting connections in an async task. |
| App termination (`applicationShouldTerminate` in `AtermAppDelegate`, line 37, after `QuitFlowCoordinator` completes) | Call `stop()` which: (1) closes the listening socket, (2) cancels all in-flight connection tasks, (3) removes the socket file via `unlink`. |
| App crash recovery (next launch) | The `start()` method checks if the socket file already exists. If it does, it attempts `connect()` to verify. If `connect()` fails with `ECONNREFUSED`, the file is stale and is removed before binding. If `connect()` succeeds, another aterm instance is running -- log a warning and skip socket creation. |

### 2.2 Message Format

All messages are newline-delimited JSON. Each request and response is a single JSON object followed by a newline (`\n`). This allows simple framing: read until newline.

**Request envelope:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| version | Integer | Yes | Protocol version. v1 for this spec. |
| command | String | Yes | The command identifier (e.g., `workspace.create`, `status.set`). |
| params | Object | Yes | Command-specific parameters (may be empty object `{}`). |
| env | Object | Yes | The caller's environment context, sent with every request. |

**The `env` object** carries the caller's `ATERM_*` environment variables so the server can identify the source pane and validate hierarchy consistency:

| Field | Type | Description |
|-------|------|-------------|
| paneId | String (UUID) | Value of `ATERM_PANE_ID` |
| tabId | String (UUID) | Value of `ATERM_TAB_ID` |
| spaceId | String (UUID) | Value of `ATERM_SPACE_ID` |
| workspaceId | String (UUID) | Value of `ATERM_WORKSPACE_ID` |

**Response envelope:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| version | Integer | Yes | Protocol version (echo back). |
| ok | Boolean | Yes | `true` for success, `false` for error. |
| result | Object or null | Yes (on success) | Command-specific result data. |
| error | Object or null | Yes (on error) | Error details. |

**Error object:**

| Field | Type | Description |
|-------|------|-------------|
| code | Integer | Exit code the CLI should use (1, 2, 3, or 4). |
| message | String | Human-readable error message. |

### 2.3 Command Identifiers

| Command | Params | Result |
|---------|--------|--------|
| `workspace.create` | `name` (String), `directory` (String, optional) | `id` (UUID string) |
| `workspace.list` | (none) | `workspaces` (Array of workspace objects) |
| `workspace.close` | `id` (UUID string), `force` (Boolean) | (empty) |
| `workspace.focus` | `id` (UUID string) | (empty) |
| `space.create` | `name` (String, optional), `workspaceId` (UUID string, optional -- defaults to env) | `id` (UUID string) |
| `space.list` | `workspaceId` (UUID string, optional -- defaults to env) | `spaces` (Array of space objects) |
| `space.close` | `id` (UUID string), `workspaceId` (UUID string, optional), `force` (Boolean) | (empty) |
| `space.focus` | `id` (UUID string), `workspaceId` (UUID string, optional) | (empty) |
| `tab.create` | `spaceId` (UUID string, optional -- defaults to env), `directory` (String, optional) | `id` (UUID string) |
| `tab.list` | `spaceId` (UUID string, optional -- defaults to env) | `tabs` (Array of tab objects) |
| `tab.close` | `id` (UUID string, optional -- defaults to env), `force` (Boolean) | (empty) |
| `tab.focus` | `target` (UUID string or integer) | (empty) |
| `pane.split` | `paneId` (UUID string, optional -- defaults to env), `direction` (String: `horizontal` or `vertical`) | `id` (UUID string) |
| `pane.list` | `tabId` (UUID string, optional -- defaults to env) | `panes` (Array of pane objects) |
| `pane.close` | `paneId` (UUID string, optional -- defaults to env) | (empty) |
| `pane.focus` | `target` (UUID string or direction string), `paneId` (UUID string, optional -- defaults to env) | (empty) |
| `status.set` | `label` (String) | (empty) |
| `status.clear` | (none) | (empty) |
| `notify` | `message` (String), `title` (String, optional), `subtitle` (String, optional) | (empty) |

### 2.4 Version Mismatch Handling

If the server receives a request with a `version` it does not support, it returns an error response with code 1 and message "Protocol version mismatch: client sent vN, server supports vM. Update your CLI." The CLI detects this and prints the message to stderr.

### 2.5 Concurrency Model

The `IPCServer` actor accepts connections in a loop. Each connection is handled in its own child `Task`. The handler reads exactly one request (one line), processes it, writes one response, and closes the connection. This is a one-shot-per-connection model matching the CLI's request-response pattern.

All model mutations dispatch to `@MainActor` using `await MainActor.run { ... }` inside the handler. Because model methods like `WorkspaceCollection.createWorkspace()` and `PaneViewModel.splitPane()` are `@MainActor`-isolated, the handler naturally serializes mutations through the main actor. Concurrent CLI invocations are safe: each waits its turn on `@MainActor`.

---

## 3. Environment Variable Injection

### 3.1 Injection Point

Environment variables are injected via the `ghostty_surface_config_s` struct's `env_vars` and `env_var_count` fields (defined in `aterm/Vendor/ghostty.h`, lines 453-454). The struct also has `working_directory` (line 451) which is already used.

The injection happens in `GhosttyTerminalSurface.createSurface(view:workingDirectory:)` (`aterm/Core/GhosttyTerminalSurface.swift`, line 19). Currently this method builds a `ghostty_surface_config_s`, sets `working_directory`, and calls `ghostty_surface_new()`. It must be extended to also set `env_vars` and `env_var_count`.

### 3.2 Method Signature Change

The `createSurface` method signature changes to accept an environment dictionary:

**Current** (line 19): `func createSurface(view: TerminalSurfaceView, workingDirectory: String? = nil)`

**New**: `func createSurface(view: TerminalSurfaceView, workingDirectory: String? = nil, environmentVariables: [String: String] = [:])`

The caller builds the `[String: String]` dictionary with the `ATERM_*` keys and values plus the modified `PATH`. Inside `createSurface`, this dictionary is converted to a C array of `ghostty_env_var_s` structs. The array and its string data must remain alive for the duration of the `ghostty_surface_new()` call, using the same `withCString` scoping pattern already used for `working_directory`.

### 3.3 Variables to Inject

| Variable | Value | Source |
|----------|-------|--------|
| `ATERM_SOCKET` | Absolute path to the Unix domain socket (e.g., `/var/folders/.../T/aterm-501.sock`) | `IPCServer.socketPath` (static, computed once at server start) |
| `ATERM_PANE_ID` | UUID string of the pane being created | The `paneID` parameter passed through the creation chain |
| `ATERM_TAB_ID` | UUID string of the owning tab | Known by `TabModel` which owns the `PaneViewModel` |
| `ATERM_SPACE_ID` | UUID string of the owning space | Known by `SpaceModel` which owns the `TabModel` |
| `ATERM_WORKSPACE_ID` | UUID string of the owning workspace | Known by `Workspace` which owns the `SpaceCollection` |
| `ATERM_CLI_PATH` | Absolute path to the CLI binary inside the app bundle | `Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("aterm-cli").path` |
| `PATH` | Original `PATH` with the app bundle's `MacOS` directory prepended | `Bundle.main.executableURL!.deletingLastPathComponent().path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "")` |

### 3.4 Propagation Through the Model Hierarchy

Currently, surfaces are created indirectly: `PaneViewModel.init()` creates a `GhosttyTerminalSurface` and `TerminalSurfaceView`, sets `initialWorkingDirectory` on the view, and the surface is created lazily in `TerminalSurfaceView.viewDidMoveToWindow()` (line 60-61 of `TerminalSurfaceView.swift`).

The environment dictionary must flow through this chain. The approach:

1. **Add a stored property** `var environmentVariables: [String: String] = [:]` on `TerminalSurfaceView` (alongside `initialWorkingDirectory` at line 23).

2. **Set it at creation time.** In `PaneViewModel.init()` (line 42), after setting `surfaceView.initialWorkingDirectory`, also set `surfaceView.environmentVariables`. Same in `PaneViewModel.splitPane()` (line 176) and `PaneViewModel.fromState()` (line 55, for restore).

3. **Pass it to `createSurface`.** In `TerminalSurfaceView.viewDidMoveToWindow()` (line 61), change the call to pass the stored env vars: `terminalSurface.createSurface(view: self, workingDirectory: initialWorkingDirectory, environmentVariables: environmentVariables)`.

4. **Provide a builder method.** A new static method `EnvironmentBuilder.buildPaneEnvironment(socketPath:paneID:tabID:spaceID:workspaceID:cliPath:)` on a new `EnvironmentBuilder` enum (in a new file `aterm/Core/EnvironmentBuilder.swift`) computes the dictionary. This keeps the environment logic centralized and testable.

### 3.5 Hierarchy Context Propagation

`PaneViewModel` currently does not know which tab, space, or workspace it belongs to. To inject `ATERM_TAB_ID`, `ATERM_SPACE_ID`, and `ATERM_WORKSPACE_ID`, the hierarchy context must be available at pane creation time.

**Approach:** Add a lightweight struct `PaneHierarchyContext` that carries the IDs:

| Field | Type |
|-------|------|
| socketPath | String |
| workspaceID | UUID |
| spaceID | UUID |
| tabID | UUID |
| cliPath | String |

This context is set on `PaneViewModel` as a stored property (similar to `directoryFallback` which is set by the owning `SpaceModel` at line 161 of `SpaceModel.swift`). The wiring happens:

- `SpaceModel.wireDirectoryFallback(_:)` already accesses the tab. A parallel `wireHierarchyContext(_:)` method sets `tab.paneViewModel.hierarchyContext` with the space ID, workspace ID, and static values (socket path, CLI path). The workspace ID propagation follows the same pattern as `workspaceDefaultDirectory` in `SpaceCollection.propagateWorkspaceDefault()` (line 151 of `SpaceCollection.swift`).

- `Workspace.init()` propagates the workspace ID down through `spaceCollection`, which propagates to each `SpaceModel`, which propagates to each `TabModel.paneViewModel`.

When `PaneViewModel.splitPane()` creates a new pane (line 173), it reads `self.hierarchyContext` to build the environment variables for the new `TerminalSurfaceView`. The new pane gets a fresh `ATERM_PANE_ID` (the `newPaneID` generated at line 174) while inheriting the tab/space/workspace IDs from the context.

---

## 4. CLI Binary

### 4.1 Target Configuration

A new command-line tool target `aterm-cli` in `project.yml`:

| Setting | Value |
|---------|-------|
| type | `tool` |
| platform | macOS |
| sources | `aterm-cli/` |
| product name | `aterm-cli` |
| bundle identifier | `com.aterm.cli` |
| deployment target | macOS 26.0 |
| Swift version | 6.0 |
| strict concurrency | complete |
| dependencies | None (no GhosttyKit, no app frameworks) |

The CLI target must be added as a dependency of the `aterm` app target so it is built and embedded. A copy files build phase copies the `aterm-cli` binary into `Contents/MacOS/` of the app bundle.

In `project.yml`, this is expressed by adding the CLI target to the app target's `dependencies` array and adding a `postCompileScripts` or `copyFiles` entry (XcodeGen supports `copyFiles` under the target's `settings`).

The scheme `aterm` must also include the `aterm-cli` target in its build targets.

### 4.2 Source Directory Structure

```
aterm-cli/
  main.swift              -- Entry point, argument parsing, dispatch
  CLIError.swift          -- Error types and exit codes
  IPCClient.swift         -- Socket connection, request/response I/O
  CommandRouter.swift     -- Maps parsed subcommand to IPCRequest
  IPCMessage.swift        -- Shared Codable types (request/response envelopes)
  OutputFormatter.swift   -- Table and JSON formatters for list output
  CommandLogger.swift     -- Appends to ~/Library/Logs/aterm/cli.log
```

### 4.3 Argument Parsing

The CLI uses Swift's `ArgumentParser` library (via SPM). The top-level command is `AtermCLI` with subcommands for each resource. The subcommand tree:

```
aterm-cli
  workspace
    create <name> [--directory <path>]
    list [--format json|table]
    close <id> [--force]
    focus <id>
  space
    create [<name>] [--workspace <id>]
    list [--workspace <id>] [--format json|table]
    close <id> [--workspace <id>] [--force]
    focus <id> [--workspace <id>]
  tab
    create [--space <id>] [--directory <path>]
    list [--space <id>] [--format json|table]
    close [<id>] [--force]
    focus <id-or-index>
  pane
    split [--pane <id>] [--direction horizontal|vertical]
    list [--tab <id>] [--format json|table]
    close [--pane <id>]
    focus <id-or-direction> [--pane <id>]
  status
    set --label <text>
    clear
  notify <message> [--title <title>] [--subtitle <subtitle>]
  --version
  --help
```

Note: the binary is named `aterm-cli` on disk, but the `PATH` injection (Section 3.3) makes the `MacOS/` directory available. To make the command invocable as `aterm` (matching the PRD's UX examples), the `CommandRouter` registers the `ArgumentParser` command with `commandName: "aterm"`. The actual binary filename (`aterm-cli`) avoids collision with the app executable (`aterm`), but the user types `aterm workspace list` because `ArgumentParser` uses the configured command name, not the binary name, for help text and error messages.

Additionally, a symlink named `aterm` pointing to `aterm-cli` is created in the `MacOS/` directory during the build. This is done via a post-build script in `project.yml` under the `aterm` app target's `postCompileScripts`.

### 4.4 Execution Flow

Every CLI command follows this sequence:

1. **Environment check.** Read `ATERM_SOCKET` from environment. If absent, print error to stderr and exit with code 2.
2. **Socket check.** Verify the socket file exists at the path. If not, print error to stderr and exit with code 2.
3. **Parse arguments.** `ArgumentParser` handles this. Invalid arguments exit with code 1.
4. **Build IPC request.** `CommandRouter` maps the parsed command to an `IPCRequest` struct, including the `env` object read from environment variables.
5. **Send request.** `IPCClient` connects to the socket, writes the JSON-encoded request followed by `\n`, then reads until `\n` for the response. Timeout: 5 seconds (configurable via `ATERM_CLI_TIMEOUT` env var, undocumented, for debugging).
6. **Process response.** If `ok` is `true`, format and print `result` to stdout, exit 0. If `ok` is `false`, print `error.message` to stderr, exit with `error.code`.
7. **Log.** `CommandLogger` appends a log entry regardless of outcome.

### 4.5 Exit Codes

| Code | Meaning | When |
|------|---------|------|
| 0 | Success | Command completed successfully |
| 1 | General error | Invalid arguments, entity not found, empty name, stale env var mismatch |
| 2 | Connection error | `ATERM_SOCKET` not set, socket file missing, connection refused, timeout |
| 3 | Process safety error | Running processes detected and `--force` not specified |
| 4 | Permission denied | Notification permission denied by the macOS user |

---

## 5. IPC Server (App Side)

### 5.1 IPCServer Actor

A new file `aterm/Core/IPCServer.swift` containing an actor that manages the Unix domain socket:

| Property | Type | Description |
|----------|------|-------------|
| socketPath | String | The computed socket path (`$TMPDIR/aterm-<uid>.sock`) |
| listeningFD | Int32? | The file descriptor of the listening socket |
| connectionTasks | [Task<Void, Never>] | Active connection handler tasks (for cancellation on stop) |
| commandHandler | IPCCommandHandler | Reference to the handler that processes commands |

**Methods:**

| Method | Description |
|--------|-------------|
| `start()` | Clean up stale socket, create and bind socket, listen, begin accept loop. |
| `stop()` | Cancel connection tasks, close listening FD, unlink socket file. |
| `acceptLoop()` | Async loop: `accept()` on listening FD, spawn a child task for each connection via `handleConnection(fd:)`. Uses `withCheckedContinuation` to bridge the blocking `accept()` call to structured concurrency via `DispatchIO` or a detached task on a background thread. |
| `handleConnection(fd:)` | Read request line from FD, decode JSON, call `commandHandler.handle(request:)`, encode response JSON, write to FD, close FD. |

The `IPCServer` is instantiated and started in `AtermAppDelegate.applicationDidFinishLaunching()` (after `windowCoordinator` setup at line 11). It is stopped in a new `applicationWillTerminate(_:)` method on `AtermAppDelegate`.

### 5.2 IPCCommandHandler

A new file `aterm/Core/IPCCommandHandler.swift` containing a `@MainActor` class (not an actor, because it needs direct access to `@MainActor`-isolated model types):

| Property | Type | Description |
|----------|------|-------------|
| windowCoordinator | WindowCoordinator | To resolve hierarchy from UUIDs (via `allWorkspaceCollections`) |
| statusManager | PaneStatusManager | To set/clear pane status |
| notificationManager | NotificationManager | To send notifications |

The handler receives a decoded `IPCRequest`, switches on `command`, validates params, performs the operation, and returns an `IPCResponse`. All model access happens on `@MainActor` (the handler itself is `@MainActor`-isolated). The `IPCServer` actor calls into the handler via `await MainActor.run { handler.handle(request) }`.

### 5.3 Hierarchy Resolution

Many commands need to find a specific entity by UUID. The handler provides resolution methods that traverse `WindowCoordinator.allWorkspaceCollections`:

| Method | Input | Output | Error |
|--------|-------|--------|-------|
| `resolveWorkspace(id:)` | UUID | `(WorkspaceCollection, Workspace)` | "Workspace not found: <id>" (code 1) |
| `resolveSpace(id:workspaceId:)` | UUID, UUID? | `(Workspace, SpaceModel)` | "Space not found: <id>" (code 1) |
| `resolveTab(id:spaceId:)` | UUID, UUID? | `(SpaceModel, TabModel)` | "Tab not found: <id>" (code 1) |
| `resolvePane(id:tabId:)` | UUID, UUID? | `(TabModel, PaneViewModel, UUID)` | "Pane not found: <id>" (code 1) |

For the single-window v1, `allWorkspaceCollections` contains one element. The resolution methods iterate all collections, all workspaces, all spaces, all tabs, and all panes to find the target by UUID. This is O(N) over the total entity count, which is trivially fast for single-digit workspace counts.

### 5.4 Stale Environment Detection

When a command uses the `env` object's workspace/space/tab IDs (e.g., the default workspace for `space.create`), the handler verifies that the pane identified by `env.paneId` actually exists in the hierarchy at the location specified by `env.tabId`, `env.spaceId`, and `env.workspaceId`. If the pane exists but its actual parent hierarchy does not match the env values (because a tab or space was dragged to a different workspace after the shell started), the handler returns an error with code 1: "Stale environment detected. Pane <id> is no longer in workspace <workspaceId>."

This check is performed by `resolvePane(id: env.paneId)` and comparing the found workspace/space/tab IDs against the env values.

---

## 6. IPC Command Handlers

Each command maps to existing model layer methods. This section specifies the exact dispatch for each command.

### 6.1 Workspace Commands

**`workspace.create`**

1. Validate `name` is non-empty (error code 1 if empty).
2. Find the first `WorkspaceCollection` from `windowCoordinator.allWorkspaceCollections` (single-window v1).
3. Call `collection.createWorkspace(name: name, workingDirectory: directory)` (method at `WorkspaceCollection.swift` line 63).
4. The method already returns `Workspace?`. If `nil` (empty name after trimming), return error code 1.
5. Return `{ "id": "<workspace.id>" }`.

**`workspace.list`**

1. Iterate `windowCoordinator.allWorkspaceCollections[0].workspaces`.
2. For each workspace, build an object: `id`, `name`, `spaceCount` (from `workspace.spaceCollection.spaces.count`), `active` (whether `workspace.id == collection.activeWorkspaceID`).
3. Return `{ "workspaces": [...] }`.

**`workspace.close`**

1. Resolve workspace via `resolveWorkspace(id:)`.
2. If `force` is not `true`, check for running processes. Iterate all spaces, tabs, panes in the workspace and call `ProcessDetector.needsConfirmation(surface:)` for each surface (same pattern as `ProcessDetector.detectRunningProcesses` at `ProcessDetector.swift` line 17). If any process is detected, return error code 3 with message including the count.
3. Call `workspace.cleanup()` (line 89 of `Workspace.swift`) to free surfaces, then `collection.removeWorkspace(id:)` (line 85 of `WorkspaceCollection.swift`).

**`workspace.focus`**

1. Resolve workspace via `resolveWorkspace(id:)`.
2. Call `collection.activateWorkspace(id:)` (line 107 of `WorkspaceCollection.swift`).

### 6.2 Space Commands

**`space.create`**

1. Resolve the target workspace (from `params.workspaceId` or fall back to `env.workspaceId`).
2. Call `workspace.spaceCollection.createSpace(workingDirectory:)` (line 53 of `SpaceCollection.swift`).
3. **Model change needed:** `SpaceCollection.createSpace()` currently returns `Void`. Change it to `@discardableResult func createSpace(...) -> SpaceModel` and return the created space. The caller (IPC handler) reads `space.id` to return.
4. Return `{ "id": "<space.id>" }`.

**`space.list`**

1. Resolve the target workspace.
2. Iterate `workspace.spaceCollection.spaces`.
3. For each space: `id`, `name`, `tabCount`, `active` (whether `space.id == spaceCollection.activeSpaceID`).
4. Return `{ "spaces": [...] }`.

**`space.close`**

1. Resolve the space via `resolveSpace(id:workspaceId:)`.
2. Process safety check (same pattern as workspace close, scoped to tabs in this space).
3. Call `workspace.spaceCollection.removeSpace(id:)` (line 63 of `SpaceCollection.swift`). The method already handles cleanup internally.

**`space.focus`**

1. Resolve the space.
2. Call `workspace.spaceCollection.activateSpace(id:)` (line 88 of `SpaceCollection.swift`).
3. Also call `collection.activateWorkspace(id: workspace.id)` (line 107 of `WorkspaceCollection.swift`) to ensure the workspace is active.

### 6.3 Tab Commands

**`tab.create`**

1. Resolve the target space (from `params.spaceId` or fall back to `env.spaceId`).
2. Resolve working directory: if `params.directory` is provided, use it. Otherwise, use `spaceCollection.resolveWorkingDirectory()` (line 121 of `SpaceCollection.swift`).
3. Call `space.createTab(workingDirectory:)` (line 56 of `SpaceModel.swift`).
4. **Model change needed:** `SpaceModel.createTab()` currently returns `Void`. Change it to `@discardableResult func createTab(...) -> TabModel` and return the created tab. The caller reads `tab.id`.
5. Return `{ "id": "<tab.id>" }`.

**`tab.list`**

1. Resolve the target space.
2. Iterate `space.tabs`.
3. For each tab: `id`, `title` (from `tab.title`, which reads the focused pane's terminal title at `TabModel.swift` line 40), `paneCount` (from `tab.paneViewModel.splitTree.leafCount`), `active` (whether `tab.id == space.activeTabID`).
4. Return `{ "tabs": [...] }`.

**`tab.close`**

1. Resolve the tab (from `params.id` or fall back to `env.tabId`).
2. Process safety check scoped to this tab using `ProcessDetector.runningProcessCount(in:)` (line 60 of `ProcessDetector.swift`).
3. Call `space.removeTab(id:)` (line 65 of `SpaceModel.swift`).

**`tab.focus`**

1. Parse `params.target`: if it parses as a UUID, focus by ID. If it parses as an integer, focus by index.
2. For UUID: call `space.activateTab(id:)` (line 82 of `SpaceModel.swift`).
3. For index: call `space.goToTab(index:)` (line 103 of `SpaceModel.swift`). Index 9 always goes to the last tab (existing behavior).

### 6.4 Pane Commands

**`pane.split`**

1. Resolve the target pane (from `params.paneId` or fall back to `env.paneId`). This gives the `TabModel` and its `PaneViewModel`.
2. Parse direction: default to `vertical` if not specified. Map `"horizontal"` to `SplitDirection.horizontal` and `"vertical"` to `SplitDirection.vertical` (defined at `PaneNode.swift` lines 4-9).
3. **Model change needed:** `PaneViewModel.splitPane(direction:)` (line 173) currently creates the new pane internally and returns `Void`. It must be changed to accept an optional target pane ID (default: focused pane) and return the new pane's UUID. Change signature to: `@discardableResult func splitPane(direction:targetPaneID:) -> UUID?`. The method already generates `newPaneID` at line 174 -- just return it.
4. Ensure the focused pane ID is set to the target pane before splitting (since `insertSplit` splits the focused pane). If `targetPaneID` differs from `splitTree.focusedPaneID`, temporarily set focus, split, then restore.
5. Return `{ "id": "<newPaneID>" }`.

**`pane.list`**

1. Resolve the target tab (from `params.tabId` or fall back to `env.tabId`).
2. Get `tab.paneViewModel.splitTree.allLeaves()` (line 46 of `SplitTree.swift`).
3. For each pane ID, look up state from `paneViewModel.paneStates[paneID]` (line 13 of `PaneViewModel.swift`) and working directory from the tree via `splitTree.findLeaf(paneID:)`.
4. For each pane: `id`, `workingDirectory`, `state` (mapped: `.running` -> `"running"`, `.exited(code:)` -> `"exited"`, `.spawnFailed` -> `"spawn-failed"`), `focused` (whether `paneID == splitTree.focusedPaneID`).
5. Return `{ "panes": [...] }`.

**`pane.close`**

1. Resolve the target pane (from `params.paneId` or fall back to `env.paneId`).
2. No separate process safety check for individual pane close (PRD only specifies `--force` for workspace, space, and tab close). The pane closes directly.
3. Call `paneViewModel.closePane(paneID:)` (line 194 of `PaneViewModel.swift`). Cascading close is handled by the existing `onEmpty` chain: last pane -> tab empty -> space removes tab -> etc.

**`pane.focus`**

1. Parse `params.target`: if it is one of `"up"`, `"down"`, `"left"`, `"right"`, treat as directional focus. Otherwise, treat as UUID.
2. For UUID: call `paneViewModel.focusPane(paneID:)` (line 213 of `PaneViewModel.swift`).
3. For direction: map to `NavigationDirection` enum (defined at `SplitNavigation.swift` line 5) and call `paneViewModel.focusDirection(_:)` (line 220 of `PaneViewModel.swift`). This uses `SplitNavigation.neighbor()` (line 18 of `SplitNavigation.swift`) with the existing spatial algorithm.

### 6.5 Status Commands

**`status.set`**

1. Read `env.paneId` to identify the source pane.
2. Validate the pane still exists (resolve via the hierarchy).
3. Call `statusManager.setStatus(paneID: env.paneId, label: params.label)`.
4. The `PaneStatusManager` (see Section 7) is `@Observable` and fires a UI update immediately.
5. Return success.

**`status.clear`**

1. Read `env.paneId`.
2. Call `statusManager.clearStatus(paneID: env.paneId)`.
3. Return success.

### 6.6 Notify Command

**`notify`**

1. If the `NotificationManager` has not yet requested authorization, request it now (lazy, per FR-27 / TB-07). The `UNUserNotificationCenter.requestAuthorization(options:)` call is `async` -- the handler `await`s it.
2. If authorization is denied, return error code 4: "Notification permission denied. Enable notifications for aterm in System Settings > Notifications."
3. Build a `UNMutableNotificationContent` with:
   - `title`: `params.title ?? "aterm"`
   - `subtitle`: `params.subtitle` (if provided)
   - `body`: `params.message`
   - `sound`: `.default`
   - `userInfo`: `["paneId": env.paneId.uuidString]` (for click-to-focus routing)
4. Create a `UNNotificationRequest` with a unique identifier (UUID string) and `nil` trigger (immediate delivery).
5. Add the request via `UNUserNotificationCenter.current().add(request)`.
6. Return success.

---

## 7. Status Model

### 7.1 PaneStatusManager

A new file `aterm/Models/PaneStatusManager.swift` containing an `@MainActor @Observable` class:

| Property | Type | Description |
|----------|------|-------------|
| statuses | `[UUID: PaneStatus]` | Map from pane ID to status. Only panes with active status are present. |

| Method | Description |
|--------|-------------|
| `setStatus(paneID:label:)` | Insert or update the status for the given pane. Sets `updatedAt` to `Date()`. |
| `clearStatus(paneID:)` | Remove the status entry for the given pane. |
| `clearAll(for paneIDs: Set<UUID>)` | Remove status entries for multiple panes (used on bulk close). |
| `latestStatus(for spaceID: UUID, in tab: TabModel) -> PaneStatus?` | Return the most recently updated status among all panes in all tabs of the given space. Used by the sidebar for display. |

**PaneStatus struct:**

| Field | Type | Description |
|-------|------|-------------|
| label | String | The status text (e.g., "Thinking...") |
| updatedAt | Date | Timestamp of the last update (for most-recent-wins display) |

The `PaneStatusManager` is a singleton (`static let shared`) or owned by `AtermAppDelegate` and injected into the view hierarchy via SwiftUI environment. The singleton pattern is simpler and matches `AppMetrics.shared`.

### 7.2 Cleanup on Pane Close

When a pane is closed via `PaneViewModel.closePane(paneID:)` (line 194 of `PaneViewModel.swift`), the status for that pane must be cleared. Add `PaneStatusManager.shared.clearStatus(paneID: paneID)` after the surface cleanup at line 199.

### 7.3 Sidebar Integration

The sidebar displays status inline with the space row. The modification is in `SidebarSpaceRowView` (`aterm/View/Sidebar/SidebarSpaceRowView.swift`).

**Current layout** (lines 21-45): HStack containing a green/gray circle, space name (InlineRenameView), spacer, and tab count badge.

**New layout**: Add a VStack wrapping the space name and an optional status label below it. The status label appears only when a pane in that space has an active status.

The status text is resolved by computing the most-recently-updated status across all panes in all tabs of the space. The `SidebarSpaceRowView` reads from `PaneStatusManager.shared.statuses` (which is `@Observable`, so SwiftUI tracks changes automatically).

**Status label styling:**
- Font: `.system(size: 10)` (10pt system font, per PRD)
- Color: `.secondary` (secondary text color)
- Truncation: single line, truncated with ellipsis if the text exceeds the available width
- Max display length: 50 characters (truncate before display)
- Hidden when no status is active (no empty-state placeholder)

**Resolution logic for which status to show:**

Given a `SpaceModel`, iterate all `space.tabs`, for each tab iterate `tab.paneViewModel.splitTree.allLeaves()`, check `PaneStatusManager.shared.statuses[paneID]`. Return the entry with the most recent `updatedAt`. This is computed as a helper function on `PaneStatusManager` to keep the view simple.

---

## 8. Notification Handling

### 8.1 NotificationManager

A new file `aterm/Core/NotificationManager.swift` containing a class that wraps `UNUserNotificationCenter`:

| Property | Type | Description |
|----------|------|-------------|
| hasRequestedAuthorization | Bool | Whether `requestAuthorization` has been called this session |
| isAuthorized | Bool? | Cached result of the last authorization check. `nil` means unknown. |

| Method | Description |
|--------|-------------|
| `ensureAuthorized() async throws` | If `hasRequestedAuthorization` is false, call `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])`. Cache the result. If denied, throw a `NotificationError.permissionDenied` error. If already cached and denied, throw immediately. |
| `sendNotification(message:title:subtitle:paneID:) async throws` | Call `ensureAuthorized()`, then build and submit the notification request (as described in Section 6.6). |

### 8.2 UNUserNotificationCenterDelegate

The `AtermAppDelegate` must conform to `UNUserNotificationCenterDelegate` and register itself as the delegate in `applicationDidFinishLaunching()`. This is needed for two reasons:

1. **Foreground delivery.** Implement `userNotificationCenter(_:willPresent:withCompletionHandler:)` to call the completion handler with `[.banner, .sound]` so notifications are displayed even when aterm is in the foreground.

2. **Click-to-focus.** Implement `userNotificationCenter(_:didReceive:withCompletionHandler:)` to handle notification clicks. Extract `paneId` from `response.notification.request.content.userInfo["paneId"]`, resolve it to the containing workspace/space/tab via the hierarchy resolution methods, activate the workspace, activate the space, activate the tab, focus the pane, and bring the window to front via `NSApp.activate()` and `controller.window?.makeKeyAndOrderFront(nil)`.

### 8.3 Notification Content

| Field | Value |
|-------|-------|
| title | `params.title` or `"aterm"` if not provided |
| subtitle | `params.subtitle` if provided |
| body | `params.message` |
| sound | `UNNotificationSound.default` |
| userInfo | `["paneId": "<pane-uuid-string>"]` |
| identifier | A unique UUID string per notification |
| trigger | `nil` (immediate) |
| categoryIdentifier | Not set (no custom actions in v1) |
| threadIdentifier | Not set (no grouping in v1) |

---

## 9. Command Logging

### 9.1 Log File

Location: `~/Library/Logs/aterm/cli.log`

The `CommandLogger` (in the CLI binary, not the app) creates the directory if it does not exist and appends a line for each invocation.

### 9.2 Log Entry Format

Each line is a single JSON object (JSONL format) for easy machine parsing:

| Field | Type | Description |
|-------|------|-------------|
| timestamp | String (ISO 8601) | When the command was invoked |
| command | String | Full command string (e.g., `workspace create "my-project" --directory ~/Code`) |
| exitCode | Integer | The exit code |
| result | String or null | UUID for creates, null for other successes |
| error | String or null | Error message for failures |
| durationMs | Integer | Wall-clock time from invocation to exit |

### 9.3 Rotation

The CLI checks the log file size before appending. If it exceeds 10 MB, the CLI renames the current file to `cli.log.1` (overwriting any existing `.1` file) and starts a new `cli.log`. This is a simple single-rotation scheme that caps total disk usage at approximately 20 MB.

---

## 10. Build Integration

### 10.1 project.yml Changes

Add the `aterm-cli` target under `targets`:

| Key | Value |
|-----|-------|
| type | `tool` |
| platform | macOS |
| sources.path | `aterm-cli` |
| settings.PRODUCT_BUNDLE_IDENTIFIER | `com.aterm.cli` |
| settings.PRODUCT_NAME | `aterm-cli` |
| settings.SWIFT_VERSION | `6.0` |
| settings.SWIFT_STRICT_CONCURRENCY | `complete` |
| settings.MACOSX_DEPLOYMENT_TARGET | `26.0` |
| dependencies | (none -- the CLI has no framework dependencies) |

Add `swift-argument-parser` as an SPM dependency. In `project.yml` under the top-level `packages` key:

| Key | Value |
|-----|-------|
| swift-argument-parser.url | `https://github.com/apple/swift-argument-parser` |
| swift-argument-parser.from | `1.5.0` |

The `aterm-cli` target's `dependencies` array includes `{ package: swift-argument-parser, product: ArgumentParser }`.

Modify the `aterm` app target:

1. Add `aterm-cli` to the `dependencies` array.
2. Add a `postCompileScripts` entry to create the `aterm` symlink: `ln -sf aterm-cli "$BUILT_PRODUCTS_DIR/aterm.app/Contents/MacOS/aterm"`.

Update the `aterm` scheme to include `aterm-cli` in the build targets list.

### 10.2 Shared Types

The IPC message types (`IPCRequest`, `IPCResponse`, `IPCError`, `IPCEnv`) must be identical between the CLI and the app. Rather than creating a shared framework (which adds linker complexity and violates TB-01), duplicate the types. The CLI has its own `IPCMessage.swift` and the app has `aterm/Core/IPCMessage.swift`. These are simple `Codable` structs with no logic -- the risk of drift is low, and any mismatch manifests immediately as a decode failure with a clear error message.

An alternative considered was a shared Swift package. This was rejected because: (1) the CLI must not link against GhosttyKit or any app framework (TB-01), (2) a shared package for six small structs adds build complexity disproportionate to the benefit, and (3) protocol version checking (Section 2.4) provides a safety net for format mismatches.

### 10.3 Code Signing

The `aterm-cli` binary must be signed with the same team identity as the app (TB-08). XcodeGen inherits the project-level signing settings, so no additional configuration is needed as long as the project's `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` are set at the project level. If they are set only on the `aterm` app target, they must be duplicated to the `aterm-cli` target.

---

## 11. Type Definitions

### 11.1 IPC Types (shared between CLI and app)

**IPCRequest**

| Field | Type | Description |
|-------|------|-------------|
| version | Int | Protocol version (1) |
| command | String | Command identifier |
| params | [String: IPCValue] | Command parameters |
| env | IPCEnv | Caller's environment context |

**IPCEnv**

| Field | Type | Description |
|-------|------|-------------|
| paneId | String | UUID string of the calling pane |
| tabId | String | UUID string of the calling tab |
| spaceId | String | UUID string of the calling space |
| workspaceId | String | UUID string of the calling workspace |

**IPCResponse**

| Field | Type | Description |
|-------|------|-------------|
| version | Int | Protocol version (echo) |
| ok | Bool | Success or failure |
| result | [String: IPCValue]? | Result data on success |
| error | IPCError? | Error data on failure |

**IPCError**

| Field | Type | Description |
|-------|------|-------------|
| code | Int | Exit code (1-4) |
| message | String | Human-readable error |

**IPCValue** -- a lightweight JSON value enum (similar to `AnyCodable`):

| Case | Description |
|------|-------------|
| .string(String) | String value |
| .int(Int) | Integer value |
| .bool(Bool) | Boolean value |
| .array([IPCValue]) | Array of values |
| .object([String: IPCValue]) | Object |
| .null | Null |

This avoids importing third-party JSON libraries. The enum conforms to `Codable` with a custom encoder/decoder that maps to standard JSON.

### 11.2 App-Side Types

**PaneHierarchyContext**

| Field | Type | Description |
|-------|------|-------------|
| socketPath | String | IPC socket path |
| workspaceID | UUID | Owning workspace ID |
| spaceID | UUID | Owning space ID |
| tabID | UUID | Owning tab ID |
| cliPath | String | Path to CLI binary |

**PaneStatus**

| Field | Type | Description |
|-------|------|-------------|
| label | String | Status text |
| updatedAt | Date | Last update timestamp |

---

## 12. Permissions and Security

### 12.1 Socket Permissions

The socket file is created with `chmod(socketPath, 0o600)` (owner read+write only). This prevents other users on the machine from connecting to the socket.

### 12.2 No Authentication

Within the socket, there is no authentication token or secret. The rationale: the socket is restricted to the current user via file permissions, and the CLI can only run inside aterm (it requires `ATERM_SOCKET` which is only set in aterm-spawned shells). This matches the threat model of a single-user desktop app.

### 12.3 Input Validation

All UUIDs received from the CLI are parsed with `UUID(uuidString:)`. Invalid UUIDs result in error code 1. All string params are validated for length (e.g., workspace name must be non-empty; status label is accepted at any length but truncated at display time).

### 12.4 No Arbitrary Execution

The IPC protocol has a fixed command set. The app never interprets freeform strings as commands or code (NG1). The `params` object is decoded into typed fields, not evaluated.

---

## 13. Performance Considerations

### 13.1 IPC Latency

The target is under 100ms round-trip (NFR-01). The expected breakdown:

| Phase | Expected Time |
|-------|---------------|
| CLI startup (process launch, arg parse) | ~20-40ms |
| Socket connect + write | <1ms |
| MainActor dispatch + model operation | <1ms |
| Response write + CLI read | <1ms |
| CLI output formatting + exit | <5ms |

The CLI binary size target is under 5 MB (NFR-03). With no GhosttyKit dependency and minimal imports (Foundation + ArgumentParser), this is achievable.

### 13.2 Concurrent Requests

Multiple CLI processes may send requests simultaneously (NFR-02). Each connection is handled in its own task, and all model mutations serialize through `@MainActor`. This prevents state corruption. The `IPCServer` actor's `acceptLoop()` handles connections concurrently, but the `@MainActor` bottleneck ensures serial execution of mutations.

### 13.3 Status Update Latency

Status updates must appear in the sidebar within 100ms (PRD UX note). The `PaneStatusManager` is `@Observable`, so SwiftUI picks up changes on the next render cycle (typically 16ms at 60fps). No polling is involved.

### 13.4 Socket Timeout

The CLI sets a 5-second `SO_RCVTIMEO` on the socket after connecting. If the app is unresponsive (e.g., stuck on the main thread), the CLI times out and exits with code 2 rather than hanging (NFR-04).

---

## 14. Migration and Deployment

### 14.1 No Data Migration

This feature adds no persistent storage. Status is ephemeral (FR-24). The socket is a runtime artifact. The log file is append-only and self-rotating. No database schema changes. No session state format changes (the CLI does not modify the session serialization format in `SessionState.swift`).

### 14.2 Deployment Order

1. Build and verify the `aterm-cli` target independently.
2. Integrate the IPC server into the app and verify socket lifecycle.
3. Add environment variable injection and verify variables appear in spawned shells.
4. Wire up command handlers and verify end-to-end CLI round-trips.
5. Add status model and sidebar integration.
6. Add notification handling.
7. Add command logging.

### 14.3 Rollback

If the feature needs to be disabled, removing the environment variable injection (reverting `GhosttyTerminalSurface.createSurface` to its original signature) effectively disables the CLI -- it will fail with "Not running inside aterm" because `ATERM_SOCKET` will be absent. The IPC server can remain running harmlessly. No data migration rollback is needed.

---

## 15. Implementation Phases

### Phase 1: IPC Foundation

**Goal:** CLI binary can send a request to the app and receive a response.

**Deliverables:**
- `aterm-cli/` source directory with `main.swift`, `CLIError.swift`, `IPCClient.swift`, `IPCMessage.swift`
- `aterm/Core/IPCServer.swift` (socket lifecycle, accept loop, connection handling)
- `aterm/Core/IPCMessage.swift` (shared message types, duplicated in CLI)
- `aterm/Core/IPCCommandHandler.swift` (stub that returns success for a `ping` command)
- `project.yml` updated with `aterm-cli` target, `swift-argument-parser` dependency, copy phase, symlink script
- `AtermAppDelegate` starts and stops the `IPCServer`
- Verify: build both targets, launch app, run `aterm-cli ping` from a regular terminal (with `ATERM_SOCKET` set manually), confirm response

### Phase 2: Environment Variable Injection

**Goal:** Every shell session spawned by aterm has the `ATERM_*` variables and `PATH` modification.

**Deliverables:**
- `aterm/Core/EnvironmentBuilder.swift` (computes the env var dictionary)
- `PaneHierarchyContext` struct
- Modified `GhosttyTerminalSurface.createSurface()` to accept and inject `environmentVariables`
- Modified `TerminalSurfaceView` to store and pass env vars
- Modified `PaneViewModel` to accept `hierarchyContext` and thread it through to surface creation
- Propagation wiring through `Workspace` -> `SpaceCollection` -> `SpaceModel` -> `TabModel` -> `PaneViewModel`
- Verify: launch app, open terminal, run `env | grep ATERM`, confirm all six variables are present. Split a pane, confirm the new pane has a different `ATERM_PANE_ID` but same tab/space/workspace IDs.

### Phase 3: Workspace/Space/Tab/Pane CRUD Commands

**Goal:** All CRUD and navigation commands work end-to-end.

**Deliverables:**
- Full `CommandRouter.swift` with argument parsing for all subcommands
- Full `OutputFormatter.swift` with table and JSON formatters
- Full `IPCCommandHandler` implementation for all 18 commands
- Model changes: `SpaceCollection.createSpace()` returns `SpaceModel`, `SpaceModel.createTab()` returns `TabModel`, `PaneViewModel.splitPane()` returns `UUID?` and accepts optional target pane ID
- Hierarchy resolution methods on `IPCCommandHandler`
- Stale environment detection
- Process safety checks for close operations (workspace, space, tab)
- Verify: from within aterm, run the full command set (`aterm workspace create`, `aterm workspace list`, `aterm space create`, `aterm tab create`, `aterm pane split`, focus/close operations)

### Phase 4: Status Reporting

**Goal:** `aterm status set` and `aterm status clear` work, and status appears in the sidebar.

**Deliverables:**
- `aterm/Models/PaneStatusManager.swift`
- `IPCCommandHandler` handlers for `status.set` and `status.clear`
- Modified `SidebarSpaceRowView` with status label display
- Status cleanup on pane close (in `PaneViewModel.closePane`)
- Verify: run `aterm status set --label "Thinking..."`, confirm label appears in sidebar. Run `aterm status clear`, confirm label disappears. Close the pane, confirm no stale status.

### Phase 5: Notifications

**Goal:** `aterm notify` sends a macOS notification. Clicking it focuses the source pane.

**Deliverables:**
- `aterm/Core/NotificationManager.swift`
- `AtermAppDelegate` as `UNUserNotificationCenterDelegate`
- `IPCCommandHandler` handler for `notify`
- Lazy authorization flow
- Click-to-focus routing in `didReceive` delegate method
- Verify: run `aterm notify "Test"`, confirm notification banner. Click the notification, confirm aterm comes to foreground with the correct pane focused. Deny permissions in System Settings, confirm exit code 4.

### Phase 6: Command Logging and Polish

**Goal:** All CLI invocations are logged. Version, help, and error handling are polished.

**Deliverables:**
- `aterm-cli/CommandLogger.swift` with JSONL format and 10 MB rotation
- `--version` flag
- `--help` and subcommand help
- All error messages match PRD examples
- Verify: run several commands, confirm `~/Library/Logs/aterm/cli.log` has entries. Check `--version`, `--help` output.

---

## 16. Model Layer Changes Summary

This section consolidates all changes to existing model layer files required by the CLI feature.

### 16.1 Return Types for Create/Split Methods

| File | Method | Current Return | New Return |
|------|--------|---------------|------------|
| `aterm/Tab/SpaceCollection.swift` line 53 | `createSpace(workingDirectory:)` | `Void` | `@discardableResult SpaceModel` |
| `aterm/Tab/SpaceModel.swift` line 56 | `createTab(workingDirectory:)` | `Void` | `@discardableResult TabModel` |
| `aterm/Pane/PaneViewModel.swift` line 173 | `splitPane(direction:)` | `Void` | `@discardableResult UUID?` (new pane ID) |

The `@discardableResult` annotation preserves backward compatibility -- existing callers that ignore the return value compile without changes.

### 16.2 PaneViewModel.splitPane Target Pane Support

`splitPane` gains an optional `targetPaneID` parameter (default: `nil`, meaning use `focusedPaneID`). When a target is specified, the method temporarily sets `focusedPaneID` to the target, performs the split, and the focus naturally moves to the new pane (existing `insertSplit` behavior at `SplitTree.swift` line 64).

### 16.3 PaneHierarchyContext Propagation

New stored property on `PaneViewModel`: `var hierarchyContext: PaneHierarchyContext?`

Set by the owning chain during construction. The propagation mirrors the existing `directoryFallback` pattern (set by `SpaceModel.wireDirectoryFallback` at `SpaceModel.swift` line 159).

### 16.4 PaneStatusManager Cleanup Hook

In `PaneViewModel.closePane(paneID:)` (line 194 of `PaneViewModel.swift`), add a call to `PaneStatusManager.shared.clearStatus(paneID: paneID)` after the surface cleanup block (after line 199).

### 16.5 GhosttyTerminalSurface.createSurface Signature

New parameter: `environmentVariables: [String: String] = [:]`. Inside the method, after building the config and before calling `ghostty_surface_new`, the dictionary is converted to a C array of `ghostty_env_var_s` and assigned to `config.env_vars` and `config.env_var_count`. The array and its C strings must be kept alive (stack-allocated or in a temporary buffer) until `ghostty_surface_new` returns.

---

## 17. New Files Summary

| File Path | Layer | Description |
|-----------|-------|-------------|
| `aterm/Core/IPCServer.swift` | Core | Unix domain socket server actor |
| `aterm/Core/IPCMessage.swift` | Core | Codable request/response types |
| `aterm/Core/IPCCommandHandler.swift` | Core | Command dispatch to model layer |
| `aterm/Core/EnvironmentBuilder.swift` | Core | Builds ATERM_* env var dictionary |
| `aterm/Core/NotificationManager.swift` | Core | UNUserNotificationCenter wrapper |
| `aterm/Models/PaneStatusManager.swift` | Models | Observable pane status store |
| `aterm/Models/PaneHierarchyContext.swift` | Models | Struct carrying hierarchy IDs |
| `aterm-cli/main.swift` | CLI | Entry point, ArgumentParser setup |
| `aterm-cli/CLIError.swift` | CLI | Error types and exit codes |
| `aterm-cli/IPCClient.swift` | CLI | Socket connection and I/O |
| `aterm-cli/IPCMessage.swift` | CLI | Codable types (duplicated from app) |
| `aterm-cli/CommandRouter.swift` | CLI | Subcommand -> IPC request mapping |
| `aterm-cli/OutputFormatter.swift` | CLI | Table and JSON output formatting |
| `aterm-cli/CommandLogger.swift` | CLI | JSONL log file writer |

---

## 18. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| **ghostty_surface_config_s env_vars memory lifetime**: The C array of `ghostty_env_var_s` and its string pointers must stay alive until `ghostty_surface_new` returns. If the array is deallocated prematurely, the shell starts with corrupt or missing env vars. | High -- silent data corruption | Medium | Use `withUnsafeBufferPointer` and nested `withCString` closures to ensure all memory is stack-pinned during the `ghostty_surface_new` call, matching the existing `working_directory` pattern at `GhosttyTerminalSurface.swift` line 49. Write a unit test that spawns a surface and verifies env vars via the ghostty inherited config API. |
| **Socket path length**: Unix domain socket paths are limited to 104 bytes on macOS. `$TMPDIR` on macOS is typically ~50 characters (`/var/folders/xx/xxxxxxxxx/T/`), plus `aterm-501.sock` (~15 chars) = ~65 bytes. Safe, but edge cases with unusual `$TMPDIR` values could exceed the limit. | Medium -- app fails to start IPC | Low | Validate path length before binding. If too long, fall back to `/tmp/aterm-<uid>.sock`. Log a warning. |
| **CLI startup latency**: Swift command-line tools have non-trivial startup time (~20-40ms for dyld + Swift runtime init). This consumes a significant portion of the 100ms budget. | Medium -- latency target missed | Medium | Measure in Phase 1. If startup time exceeds 50ms, consider: (1) static linking to eliminate dyld overhead, (2) reducing ArgumentParser import overhead by using a minimal parsing approach for the hot path (status set). |
| **MainActor contention**: If the main thread is busy (e.g., heavy SwiftUI layout during animation), IPC requests queue behind it. A burst of CLI commands during a sidebar toggle animation could cause latency spikes. | Low -- transient latency | Low | The 5-second timeout prevents hangs. In practice, MainActor operations are sub-millisecond for model mutations. Monitor in production use. |
| **ArgumentParser binary size**: swift-argument-parser adds ~2-3 MB to the binary when statically linked. This is within the 5 MB target but is the largest contributor. | Low -- binary size | Low | Acceptable. If it becomes a concern, replace with manual argument parsing (the command set is small and static). |
| **Stale socket after app crash**: If the app crashes, the socket file remains. The next launch must detect and clean it up. If cleanup fails (e.g., permissions), the IPC server cannot start. | Medium -- IPC unavailable | Low | The `connect()` + `ECONNREFUSED` check (Section 5.1) handles this reliably. If `unlink()` fails, log an error and proceed without IPC (the app still functions, just without CLI support). |

---

## 19. Open Technical Questions

| # | Question | Context | Impact if Unresolved |
|---|----------|---------|---------------------|
| 1 | Should the `IPCServer` use `NWListener` (Network.framework) instead of raw POSIX sockets for the Unix domain socket? | `NWListener` provides structured concurrency-friendly APIs and automatic connection management, but adds a framework dependency the CLI side cannot use (the CLI needs raw POSIX sockets regardless since it must not link Network.framework to stay lightweight). Using POSIX sockets on both sides keeps the implementation symmetric. | Low. POSIX sockets are well-understood and sufficient. `NWListener` could simplify the server side but is not necessary. |
| 2 | How should the `PATH` modification interact with shells that reset `PATH` in their RC files (e.g., `path_helper` in `/etc/zprofile` on macOS)? | If the user's `.zshrc` or `/etc/zprofile` resets `PATH`, the prepended app bundle path may be lost. The `ATERM_CLI_PATH` env var (FR-01) provides a fallback, but the convenience of bare `aterm` invocation depends on `PATH`. | Medium. Users of Claude Code hooks will use `$ATERM_CLI_PATH` (reliable). Direct `aterm` usage may fail for some shell configurations. Document the `$ATERM_CLI_PATH` fallback. |
| 3 | Should the env var C array allocation for `ghostty_surface_config_s` use a single contiguous buffer or individual `withCString` closures per variable? | A single buffer is more efficient but more complex. Individual closures are simpler but nest deeply (one level per variable). With 7 variables, nesting is manageable. | Low. Correctness matters more than performance here (called once per surface creation). Choose the approach that is easiest to verify for memory safety. |
| 4 | Should `PaneStatusManager` be a singleton or dependency-injected? | Singleton (`static let shared`) is simpler and matches `AppMetrics.shared`. Dependency injection is more testable but requires threading the manager through the view hierarchy. | Low. Start with singleton. Refactor to DI if testing becomes difficult. |
