# Design Guideline: CLI Tool (`tian`)

**Author:** psycoder
**Date:** 2026-04-05
**Status:** Draft
**PRD Reference:** [cli-tool-prd.md](./cli-tool-prd.md)

---

## 1. Overview

The `tian` CLI tool enables programmatic control of the tian terminal emulator from within its own shell sessions. It communicates with the running tian app over a Unix domain socket to manage the workspace hierarchy (Workspace > Space > Tab > Pane), report process status to the sidebar, and trigger macOS system notifications.

This document provides implementation-ready design guidance covering IPC architecture, binary structure, app-side request handling, status display integration, notification delivery, environment variable injection, error handling, and testing strategy. All designs reference the actual codebase and existing patterns.

### Scope

Two use cases drive the design:

1. **Claude Code hooks** -- `tian status set --label "Thinking..."`, `tian status clear`, `tian notify "Build complete"`. Lightweight, high-frequency, latency-sensitive.
2. **Scripts and AI agents** -- Full CRUD on Workspace/Space/Tab/Pane. Lower frequency, correctness-critical.

---

## 2. User Journey Maps

### Journey 1: Claude Code Hook Integration (Status + Notifications)

**Persona:** Claude Code running inside an tian pane via hooks (PreToolUse, PostToolUse, Stop).

**Preconditions:**
- tian is running with an active shell session
- `TIAN_SOCKET`, `TIAN_PANE_ID`, `TIAN_SPACE_ID` are present in the environment
- `tian` is on PATH (injected by the app into the PTY environment)

```
Hook fires (PreToolUse)
  |
  v
tian status set --label "Reading file..."  ──> CLI validates env vars
  |                                               |
  |                                               v
  |                                         Connects to Unix socket
  |                                               |
  |                                               v
  |                                         Sends JSON request {action: "status.set",
  |                                           paneID: $TIAN_PANE_ID, label: "Reading file..."}
  |                                               |
  |                                               v
  |                                         App IPC handler receives on background thread
  |                                               |
  |                                               v
  |                                         Dispatches to @MainActor:
  |                                           StatusModel.setStatus(paneID:label:)
  |                                               |
  |                                               v
  |                                         SwiftUI sidebar re-renders
  |                                           (SidebarSpaceRowView shows status)
  |                                               |
  |                                               v
  |                                         Sends response {ok: true}
  |                                               |
  v                                               v
Hook receives exit 0                        CLI prints nothing, exits 0
  |
  v
Hook fires (Stop)
  |
  v
tian status clear  ────────────────────>   Same flow, StatusModel.clearStatus(paneID:)
  |
  v
tian notify "Task complete" --title "Claude Code"
  |
  v
CLI sends notify request  ─────────────>   App checks UNUserNotificationCenter auth
  |                                         (lazy request on first use)
  |                                               |
  |                                         Auth granted? ──> Schedule notification
  |                                         Auth denied?  ──> Return {error: "permission_denied"}
  |                                               |
  v                                               v
CLI exits 0 or 4                            Notification banner appears
```

**Error states and recovery:**

| Error | Behavior | Exit Code |
|-------|----------|-----------|
| `TIAN_SOCKET` missing | "Error: Not running inside tian." | 2 |
| Socket file missing/stale | "Error: Cannot connect to tian (socket not found)." | 2 |
| App crashed mid-request | CLI times out after 5s, "Error: Connection timed out." | 2 |
| Pane closed before status set | "Error: Pane not found: <id>" | 1 |
| Notification permission denied | "Warning: Notification permission denied." (stderr) | 4 |

**Edge cases:**
- **Rapid status updates:** Multiple `status set` calls in quick succession. Each replaces the previous -- no queueing. The IPC handler processes serially via `@MainActor`, so no data races.
- **Pane closed during hook execution:** The hook's `TIAN_PANE_ID` becomes stale. The IPC handler returns a "pane not found" error. The hook exits non-zero but this is non-fatal for Claude Code.
- **App restarted between hooks:** The socket disappears. The next CLI call fails with exit code 2. The new app instance creates a fresh socket but the old env vars are stale.

---

### Journey 2: Script/AI Agent Workspace Setup

**Persona:** A shell script or AI agent that creates a full project workspace with multiple spaces, tabs, and split panes.

**Preconditions:** Same as Journey 1.

```
# Script: set up a "my-project" workspace
# Step 1: Create workspace
WS_ID=$(tian workspace create "my-project" --directory ~/Code/my-project)
  |
  v
CLI sends: {action: "workspace.create", name: "my-project", directory: "~/Code/my-project"}
  |
  v
App: WorkspaceCollection.createWorkspace(name:workingDirectory:)
  |   Returns new Workspace.id
  v
CLI stdout: "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
Exit 0

# Step 2: Create spaces in the new workspace
SPACE_DEV=$(tian space create "development" --workspace $WS_ID)
SPACE_TEST=$(tian space create "testing" --workspace $WS_ID)
  |
  v
App: workspace.spaceCollection.createSpace(workingDirectory:)
  |   SpaceModel created with auto-tab, returns space.id
  v
CLI stdout: "<new-space-uuid>"

# Step 3: Create tabs and split panes
TAB_SERVER=$(tian tab create --space $SPACE_DEV --directory ~/Code/my-project)
tian pane split --direction horizontal
  |
  v
App: space.createTab(workingDirectory:)
App: tab.paneViewModel.splitPane(direction: .horizontal)
  |   New pane inherits working directory
  v
CLI stdout: "<new-tab-uuid>" / "<new-pane-uuid>"

# Step 4: Navigate to the dev space
tian space focus $SPACE_DEV
```

**Error states:**

| Error | Behavior | Exit Code |
|-------|----------|-----------|
| Workspace create with empty name | "Error: Workspace name cannot be empty." | 1 |
| Space create with invalid workspace ID | "Error: Workspace not found: <id>" | 1 |
| Tab create with invalid space ID | "Error: Space not found: <id>" | 1 |
| Directory does not exist | Workspace/tab created anyway (shell will start in ~). Not an error -- matches current `WorkingDirectoryResolver` behavior. | 0 |

**Edge cases:**
- **Concurrent script commands:** Two scripts create workspaces simultaneously. The `@MainActor` serialization ensures no data races on `WorkspaceCollection.workspaces`. Each command gets a unique UUID.
- **Script creates workspace in background, app is quit:** Socket disappears. All subsequent commands fail with exit code 2.
- **Stale env var after workspace focus:** After `tian workspace focus $WS_ID`, the calling pane's `TIAN_WORKSPACE_ID` env var still points to the *original* workspace. This is expected -- env vars are set at spawn time and do not update. The CLI sends all env vars; the IPC handler uses them for "defaults to current" resolution, not for validation (except stale-detection on hierarchy lookups).

---

### Journey 3: First-Time User Discovery

**Persona:** A developer who has tian installed and runs `tian` from a different terminal emulator (iTerm2, Terminal.app) or discovers the CLI by tab-completing.

```
$ tian workspace list                     # From iTerm2

Error: Not running inside tian.
The tian CLI can only be used from within an tian terminal session.

Exit code: 2
```

```
$ tian --help                             # From anywhere

tian - Control tian terminal emulator from within its shell sessions.

Usage: tian <resource> <verb> [arguments] [--flags]

Resources:
  workspace    Manage workspaces
  space        Manage spaces within a workspace
  tab          Manage tabs within a space
  pane         Manage panes within a tab
  status       Set or clear sidebar status for the current pane
  notify       Send a macOS system notification

Options:
  --help       Show help for a command
  --version    Show CLI version

Note: This CLI only works from within an tian terminal session.
Environment variables TIAN_SOCKET and TIAN_PANE_ID must be present.

Exit code: 0 (--help always succeeds even outside tian)
```

**Design decision:** `--help` and `--version` succeed without env vars. All other commands check `TIAN_SOCKET` first. This lets users discover the CLI without needing to be inside tian.

---

### Journey 4: Process Safety Workflow (Close with Running Processes)

**Persona:** A script attempting to close a workspace/space/tab that contains panes with running foreground processes.

```
$ tian workspace close $WS_ID

Error: Workspace "my-project" has 3 panes with running processes:
  - Space "development", Tab "Tab 1", Pane d4e5f6a7-...  (node)
  - Space "development", Tab "Tab 1", Pane e5f6a7b8-...  (python)
  - Space "testing", Tab "Tab 1", Pane f6a7b8c9-...      (cargo)
Use --force to close anyway.

Exit code: 3
```

```
$ tian workspace close $WS_ID --force

Workspace "my-project" closed (3 running processes terminated).

Exit code: 0
```

**Implementation path:**

1. IPC handler receives `workspace.close` request with `force: false`
2. Handler resolves workspace by UUID via `WorkspaceCollection.workspaces.first(where:)`
3. Handler calls `ProcessDetector.detectRunningProcesses` scoped to the target workspace
4. If processes detected and `force == false`: return error response with process list
5. If `force == true` or no processes: call `WorkspaceCollection.removeWorkspace(id:)` which triggers cascading cleanup via `Workspace.cleanup()` -> `TabModel.cleanup()` -> `PaneViewModel.cleanup()`

**The process check happens at the IPC handler level**, before dispatching to the model layer. This matches the existing `ProcessDetector` pattern used by `QuitFlowCoordinator` and `CloseConfirmationDialog`.

---

## 3. IPC Architecture Design

### Socket Location and Lifecycle

```
Socket path: $TMPDIR/tian-<uid>.sock
Example:     /var/folders/xx/xxxxx/T/tian-501.sock
```

**Why `$TMPDIR`:** Per-user, writable without sudo, automatically cleaned on reboot. The UID suffix handles multi-user systems. `$TMPDIR` is preferred over `~/Library/Application Support/tian/` because socket files should not survive app termination.

**Lifecycle:**

```
App Launch
  |
  v
Check for stale socket file at $TMPDIR/tian-<uid>.sock
  |-- exists? --> unlink() it (stale from crash)
  v
Create socket, bind, listen  (mode 0600, owner-only)
  |
  v
Accept connections in a loop (background thread)
  |
  v
App Termination (normal or crash)
  |-- normal: unlink() socket in applicationWillTerminate
  |-- crash: stale file left behind, cleaned on next launch
```

### Message Protocol

**Wire format:** Length-prefixed JSON over Unix domain socket. Each message is:

```
[4 bytes: payload length, big-endian uint32][payload: UTF-8 JSON]
```

Length-prefixed framing avoids the delimiter-parsing pitfalls of newline-delimited JSON (embedded newlines in strings, partial reads).

**Request schema:**

```json
{
  "v": 1,
  "action": "workspace.create",
  "params": {
    "name": "my-project",
    "directory": "/Users/sanguk/Code/my-project"
  },
  "env": {
    "paneID": "d4e5f6a7-...",
    "tabID": "c3d4e5f6-...",
    "spaceID": "b2c3d4e5-...",
    "workspaceID": "a1b2c3d4-..."
  }
}
```

- `v`: Protocol version. Allows version mismatch detection.
- `action`: Dot-separated resource.verb (e.g., `workspace.create`, `status.set`, `pane.split`).
- `params`: Action-specific parameters.
- `env`: All TIAN_* env var values from the calling shell. Sent with every request for stale detection and "defaults to current" resolution.

**Response schema (success):**

```json
{
  "v": 1,
  "ok": true,
  "data": {
    "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
  }
}
```

**Response schema (error):**

```json
{
  "v": 1,
  "ok": false,
  "error": {
    "code": "entity_not_found",
    "message": "Workspace not found: 00000000-0000-0000-0000-000000000000",
    "exitCode": 1
  }
}
```

The `exitCode` in the error response tells the CLI which exit code to use, keeping exit-code logic centralized in the app.

**Action catalog:**

| Action | Params | Response `data` |
|--------|--------|-----------------|
| `workspace.create` | `name`, `directory?` | `{id}` |
| `workspace.list` | -- | `{items: [{id, name, spaceCount, active}]}` |
| `workspace.close` | `id`, `force?` | `{}` |
| `workspace.focus` | `id` | `{}` |
| `space.create` | `name?`, `workspaceID?` | `{id}` |
| `space.list` | `workspaceID?` | `{items: [{id, name, tabCount, active}]}` |
| `space.close` | `id`, `workspaceID?`, `force?` | `{}` |
| `space.focus` | `id`, `workspaceID?` | `{}` |
| `tab.create` | `spaceID?`, `directory?` | `{id}` |
| `tab.list` | `spaceID?` | `{items: [{id, name, title, active}]}` |
| `tab.close` | `id?`, `force?` | `{}` |
| `tab.focus` | `target` (UUID or 1-based index) | `{}` |
| `pane.split` | `paneID?`, `direction?` | `{id}` |
| `pane.list` | `tabID?` | `{items: [{id, workingDirectory, state}]}` |
| `pane.close` | `paneID?` | `{}` |
| `pane.focus` | `target` (UUID or direction), `paneID?` | `{}` |
| `status.set` | `label` | `{}` |
| `status.clear` | -- | `{}` |
| `notify` | `message`, `title?`, `subtitle?` | `{}` |

### Connection Flow

```
CLI Process                          App (IPCServer)
    |                                     |
    |  connect(socket_path)               |
    |------------------------------------>|
    |                                     |  accept()
    |  send [len][json request]           |
    |------------------------------------>|
    |                                     |  read request
    |                                     |  parse JSON
    |                                     |  route to handler
    |                                     |  dispatch to @MainActor
    |                                     |  execute model operation
    |                                     |  serialize response
    |  recv [len][json response]          |
    |<------------------------------------|
    |                                     |  close connection
    |  parse response                     |
    |  print output / exit                |
```

Each CLI invocation opens a new connection, sends one request, receives one response, and closes. No connection pooling or keep-alive. This simplifies the protocol and avoids stale-connection bugs.

### Concurrency Model

```
                    +-----------------------+
                    |   IPCServer           |
                    |   (background thread) |
                    +---------+-------------+
                              |
                    accept() loop
                              |
              +---------------+---------------+
              |               |               |
         Connection 1    Connection 2    Connection 3
         (DispatchQueue) (DispatchQueue) (DispatchQueue)
              |               |               |
              v               v               v
         Read request    Read request    Read request
         Parse JSON      Parse JSON      Parse JSON
              |               |               |
              +-------+-------+-------+-------+
                      |               |
                      v               v
              DispatchQueue.main.async { }
              (@MainActor serialization)
                      |
                      v
              Model operation executes
              (single-threaded on MainActor)
                      |
                      v
              Response written back
              to the connection's socket fd
```

**Key insight:** Multiple CLI processes can connect concurrently, but all model mutations are serialized through `@MainActor`. This matches the existing pattern where `NotificationCenter` notifications are dispatched to `.main` queue (see `GhosttyApp.handleAction` at line 245-251 of `GhosttyApp.swift`).

---

## 4. CLI Binary Design

### Binary Target Structure

```
tian.app/
  Contents/
    MacOS/
      tian           <-- Main app executable
      tian-cli       <-- CLI binary (standalone, no GhosttyKit dependency)
```

The CLI binary is a separate Swift executable target in `project.yml`. It links only against Foundation and System (for Unix socket operations). It must NOT link against GhosttyKit, AppKit, or SwiftUI.

**project.yml addition:**

```yaml
  tian-cli:
    type: tool
    platform: macOS
    sources:
      - path: tian-cli
    settings:
      base:
        PRODUCT_NAME: tian-cli
        PRODUCT_BUNDLE_IDENTIFIER: com.tian.cli
        SWIFT_VERSION: "6.0"
        INSTALL_PATH: ""
        SKIP_INSTALL: false
        # Code-sign with same team identity as main app
        CODE_SIGN_IDENTITY: $(CODE_SIGN_IDENTITY)
    dependencies: []
```

After adding, run `xcodegen generate` to regenerate the project.

### Source Layout

```
tian-cli/
  main.swift              -- Entry point, argument parsing, dispatch
  IPCClient.swift         -- Socket connect, send request, receive response
  Commands/
    WorkspaceCommand.swift
    SpaceCommand.swift
    TabCommand.swift
    PaneCommand.swift
    StatusCommand.swift
    NotifyCommand.swift
  Models/
    Request.swift         -- Codable request types
    Response.swift        -- Codable response types
  Output/
    TableFormatter.swift  -- Human-readable table output
    JSONFormatter.swift   -- Machine-readable JSON output
  CLILogger.swift         -- Logging to ~/Library/Logs/tian/cli.log
  EnvironmentCheck.swift  -- TIAN_* env var validation
```

### Argument Parsing

Use Swift Argument Parser (`swift-argument-parser`) for argument parsing. It provides help generation, error messages, and subcommand routing with minimal code.

```swift
// main.swift
import ArgumentParser

@main
struct TianCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tian",
        abstract: "Control tian terminal emulator from within its shell sessions.",
        version: "1.0.0",
        subcommands: [
            WorkspaceCommand.self,
            SpaceCommand.self,
            TabCommand.self,
            PaneCommand.self,
            StatusCommand.self,
            NotifyCommand.self,
        ]
    )
}
```

```swift
// Commands/WorkspaceCommand.swift
struct WorkspaceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workspace",
        abstract: "Manage workspaces.",
        subcommands: [Create.self, List.self, Close.self, Focus.self]
    )

    struct Create: ParsableCommand {
        @Argument(help: "Workspace name.")
        var name: String

        @Option(help: "Default working directory.")
        var directory: String?

        func run() throws {
            let env = try EnvironmentCheck.validate()  // exits 2 if missing
            let request = IPCRequest(
                action: "workspace.create",
                params: ["name": name, "directory": directory],
                env: env
            )
            let response = try IPCClient.send(request, socketPath: env.socketPath)
            // Print UUID of created workspace
            print(response.data["id"] as! String)
        }
    }
}
```

### Output Formatting

**Table output** (default for `list` commands):

```
$ tian workspace list
  NAME          ID                                     SPACES  ACTIVE
* my-project    a1b2c3d4-e5f6-7890-abcd-ef1234567890   3       yes
  personal      f0e1d2c3-b4a5-6789-0123-456789abcdef   1       no
```

- Active row marked with `*`
- Columns: fixed-width, aligned, truncated with `...` if needed
- Header row always present

**JSON output** (`--format json`):

```json
[
  {"id": "a1b2c3d4-...", "name": "my-project", "spaces": 3, "active": true},
  {"id": "f0e1d2c3-...", "name": "personal", "spaces": 1, "active": false}
]
```

- Valid JSON array, one object per entity
- Stable key ordering for predictable grep/jq usage

**Write operation output** (create, close, split, focus, status, notify):

```
# Create: print only the UUID (easy to capture with $(...))
$ tian workspace create "my-project"
a1b2c3d4-e5f6-7890-abcd-ef1234567890

# Close: human-readable confirmation to stderr, nothing to stdout
$ tian workspace close a1b2c3d4-...
# (no stdout output -- exit code 0 signals success)

# Focus, status set/clear, notify: same pattern -- exit code only
```

**Design rationale for silent success on non-create writes:** Scripts check exit codes, not stdout. Printing confirmation messages to stdout pollutes pipeline output. The PRD says "print a confirmation message" -- we print to stderr for human visibility while keeping stdout clean for scripting.

### CLI Logging

Every invocation is logged to `~/Library/Logs/tian/cli.log`:

```
2026-04-05T14:32:01.123Z  tian workspace create "my-project" --directory ~/Code  exit=0  id=a1b2c3d4  dur=23ms
2026-04-05T14:32:01.456Z  tian status set --label "Thinking..."  exit=0  dur=8ms
2026-04-05T14:32:05.789Z  tian workspace close 00000000-...  exit=1  err="not found"  dur=12ms
```

**Log rotation:** Rotate when file exceeds 5MB. Keep one `.1` backup. Check size before appending.

---

## 5. App-Side IPC Handler Design

### New Files

```
tian/
  IPC/
    IPCServer.swift          -- Socket server lifecycle (bind, listen, accept)
    IPCRequestRouter.swift   -- Parse action, dispatch to handler
    IPCProtocol.swift        -- Request/Response Codable types, wire format
    Handlers/
      WorkspaceHandler.swift
      SpaceHandler.swift
      TabHandler.swift
      PaneHandler.swift
      StatusHandler.swift
      NotifyHandler.swift
```

### IPCServer Lifecycle

```swift
// tian/IPC/IPCServer.swift

@MainActor
final class IPCServer {
    private let socketPath: String
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init() {
        let uid = getuid()
        let tmpDir = NSTemporaryDirectory()
        self.socketPath = "\(tmpDir)tian-\(uid).sock"
    }

    func start() {
        cleanupStaleSocket()

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            Log.ipc.error("Failed to create socket: \(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                let pathBuf = UnsafeMutableRawPointer(pathPtr)
                    .assumingMemoryBound(to: CChar.self)
                strcpy(pathBuf, ptr)
            }
        }

        // Bind and set permissions
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        chmod(socketPath, 0o600)  // Owner-only

        listen(serverFD, /* backlog: */ 5)

        // Accept connections on a background queue
        let source = DispatchSource.makeReadSource(
            fileDescriptor: serverFD,
            queue: DispatchQueue(label: "com.tian.ipc", qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.resume()
        self.acceptSource = source

        Log.ipc.info("IPC server listening at \(socketPath)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }

    private func cleanupStaleSocket() {
        if FileManager.default.fileExists(atPath: socketPath) {
            Log.ipc.info("Removing stale socket at \(socketPath)")
            unlink(socketPath)
        }
    }

    // ...acceptConnection(), readRequest(), writeResponse()...
}
```

**Where to start/stop:** The `IPCServer` is owned by `TianAppDelegate`. Start in `applicationDidFinishLaunching`, stop in `applicationWillTerminate`.

```swift
// TianAppDelegate.swift (modified)
@MainActor
class TianAppDelegate: NSObject, NSApplicationDelegate {
    let workspaceManager = WorkspaceManager()
    let windowCoordinator = WindowCoordinator()
    private lazy var quitFlowCoordinator = QuitFlowCoordinator(windowCoordinator: windowCoordinator)
    private var ipcServer: IPCServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ... existing code ...

        // Start IPC server
        let server = IPCServer()
        server.requestHandler = IPCRequestRouter(
            windowCoordinator: windowCoordinator,
            workspaceManager: workspaceManager
        )
        server.start()
        self.ipcServer = server
    }

    func applicationWillTerminate(_ notification: Notification) {
        ipcServer?.stop()
    }
}
```

### Request Routing

```swift
// tian/IPC/IPCRequestRouter.swift

@MainActor
final class IPCRequestRouter {
    private let windowCoordinator: WindowCoordinator
    private let workspaceManager: WorkspaceManager
    private let statusModel: StatusModel
    private let notifyHandler: NotifyHandler

    func route(_ request: IPCRequest) async -> IPCResponse {
        // Version check
        guard request.v == 1 else {
            return .error(code: "version_mismatch",
                         message: "Protocol version \(request.v) not supported. Expected 1.",
                         exitCode: 1)
        }

        // Resolve the target WorkspaceCollection
        // v1: single window, so we use the first (and only) controller
        guard let collection = windowCoordinator.allWorkspaceCollections.first else {
            return .error(code: "no_window",
                         message: "No tian window is open.",
                         exitCode: 1)
        }

        switch request.action {
        case "workspace.create":
            return WorkspaceHandler.create(request, collection: collection)
        case "workspace.list":
            return WorkspaceHandler.list(request, collection: collection)
        case "workspace.close":
            return WorkspaceHandler.close(request, collection: collection)
        case "workspace.focus":
            return WorkspaceHandler.focus(request, collection: collection)
        case "space.create":
            return SpaceHandler.create(request, collection: collection)
        // ... all other actions ...
        case "status.set":
            return StatusHandler.set(request, statusModel: statusModel)
        case "status.clear":
            return StatusHandler.clear(request, statusModel: statusModel)
        case "notify":
            return await NotifyHandler.send(request)
        default:
            return .error(code: "unknown_action",
                         message: "Unknown action: \(request.action)",
                         exitCode: 1)
        }
    }
}
```

### Threading: Background to MainActor Bridge

The socket `accept()` and I/O happen on a background `DispatchQueue`. All model operations require `@MainActor`. The bridge:

```swift
private func handleConnection(fd: Int32) {
    // Background thread: read request
    let requestData = readLengthPrefixedData(fd: fd)
    guard let request = try? JSONDecoder().decode(IPCRequest.self, from: requestData) else {
        writeLengthPrefixedData(fd: fd, data: errorResponse("Invalid request JSON"))
        close(fd)
        return
    }

    // Bridge to MainActor for model operations
    Task { @MainActor in
        let response = await self.requestRouter.route(request)
        let responseData = try! JSONEncoder().encode(response)

        // Write response back (can happen off main thread)
        DispatchQueue(label: "com.tian.ipc.write").async {
            writeLengthPrefixedData(fd: fd, data: responseData)
            close(fd)
        }
    }
}
```

### Stale Environment Variable Detection

When the CLI sends env vars with the request, the IPC handler validates hierarchy consistency:

```swift
// In SpaceHandler.focus, for example:
func focus(_ request: IPCRequest, collection: WorkspaceCollection) -> IPCResponse {
    let spaceID = UUID(uuidString: request.params["id"]!)!
    let workspaceID = request.resolveWorkspaceID()  // from params or env

    // Verify the space actually belongs to the specified workspace
    guard let workspace = collection.workspaces.first(where: { $0.id == workspaceID }),
          workspace.spaceCollection.spaces.contains(where: { $0.id == spaceID }) else {
        return .error(
            code: "stale_env",
            message: "Stale environment detected. Space \(spaceID) is no longer in workspace \(workspaceID).",
            exitCode: 1
        )
    }

    workspace.spaceCollection.activateSpace(id: spaceID)
    collection.activateWorkspace(id: workspaceID)
    return .ok()
}
```

---

## 6. Status Display Design

### StatusModel

A new `@Observable` model that maps pane UUIDs to status labels:

```swift
// tian/Models/StatusModel.swift

@MainActor @Observable
final class StatusModel {
    /// Active status labels keyed by pane UUID.
    private(set) var statuses: [UUID: StatusEntry] = [:]

    struct StatusEntry {
        let label: String
        let updatedAt: Date
    }

    func setStatus(paneID: UUID, label: String) {
        statuses[paneID] = StatusEntry(label: label, updatedAt: Date())
    }

    func clearStatus(paneID: UUID) {
        statuses.removeValue(forKey: paneID)
    }

    /// Called when a pane is closed. Removes any associated status.
    func paneDidClose(paneID: UUID) {
        statuses.removeValue(forKey: paneID)
    }

    /// Returns the most recently updated status label for any pane
    /// within the given set of pane IDs (all panes in a space).
    func activeLabel(forPaneIDs paneIDs: Set<UUID>) -> String? {
        statuses
            .filter { paneIDs.contains($0.key) }
            .max(by: { $0.value.updatedAt < $1.value.updatedAt })?
            .value.label
    }
}
```

**Ownership:** The `StatusModel` is a singleton owned by `IPCRequestRouter` (or `TianAppDelegate`). It is passed down to the view layer via the environment or as a direct dependency.

**Cleanup on pane close:** Wire into the existing `PaneViewModel.closePane` flow. When a pane closes, its surface observer fires `surfaceCloseNotification`. We add a parallel listener in the IPC layer:

```swift
// In IPCServer or a dedicated StatusCleanupObserver
NotificationCenter.default.addObserver(
    forName: GhosttyApp.surfaceCloseNotification, object: nil, queue: .main
) { [weak statusModel] notification in
    guard let statusModel,
          let surfaceId = notification.userInfo?["surfaceId"] as? UUID else { return }
    // surfaceId is the GhosttyTerminalSurface.id, not the pane UUID.
    // Need a mapping -- see "Pane-to-Surface ID Mapping" below.
}
```

**Pane-to-Surface ID mapping for cleanup:** The `PaneViewModel.surfaces` dictionary maps `paneID -> GhosttyTerminalSurface`. The surface has its own `id`. When we receive a `surfaceClose` notification with a `surfaceId`, we need to find the corresponding `paneID`. This mapping already exists in `PaneViewModel.paneID(forSurfaceID:)` (line 307-309 of `PaneViewModel.swift`), but it is private. The cleanest approach is to have `PaneViewModel.closePane` post a separate notification or call a callback with the paneID, so the StatusModel can observe it directly:

```swift
// In PaneViewModel.closePane (after removing the pane):
statusModel?.paneDidClose(paneID: paneID)
```

Or use a notification:

```swift
static let paneDidCloseNotification = Notification.Name("PaneViewModel.paneDidClose")
// In closePane:
NotificationCenter.default.post(
    name: Self.paneDidCloseNotification,
    object: nil,
    userInfo: ["paneID": paneID]
)
```

### Sidebar Integration

The `SidebarSpaceRowView` needs to display the status label below the space name. The space row needs access to the `StatusModel` and the set of pane IDs within its space.

**Collecting pane IDs for a space:**

```swift
extension SpaceModel {
    /// All pane UUIDs across all tabs in this space.
    var allPaneIDs: Set<UUID> {
        var ids = Set<UUID>()
        for tab in tabs {
            ids.formUnion(tab.paneViewModel.splitTree.allLeaves())
        }
        return ids
    }
}
```

**Modified SidebarSpaceRowView:**

```swift
// SidebarSpaceRowView.swift (modified)

struct SidebarSpaceRowView: View {
    let space: SpaceModel
    let isActive: Bool
    let isKeyboardSelected: Bool
    let statusModel: StatusModel       // <-- NEW
    let onSelect: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var lastClickTime: Date?

    private var statusLabel: String? {
        statusModel.activeLabel(forPaneIDs: space.allPaneIDs)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color.green : Color(white: 0.5, opacity: 0.4))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                // Existing space name
                InlineRenameView(
                    text: space.name,
                    isRenaming: $isRenaming,
                    onCommit: { space.name = $0 }
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color(white: 0.9) : .secondary)

                // Status label (shown only when active)
                if let statusLabel {
                    Text(statusLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            Text(tabCountLabel)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.45))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                )
        }
        // ... rest unchanged ...
    }
}
```

**Visual layout:**

```
+--------------------------------------------------+
| (o)  Space Name                         2 tabs   |
|      Thinking...                                  |
+--------------------------------------------------+
  ^       ^                                  ^
  |       |                                  |
  dot   name + status (VStack)            badge

When no status:
+--------------------------------------------------+
| (o)  Space Name                         2 tabs   |
+--------------------------------------------------+
```

**The status area is hidden when no status is active** (no empty placeholder). The row height adjusts naturally via VStack. Since `StatusModel` is `@Observable`, changes trigger immediate SwiftUI re-renders -- no polling.

---

## 7. Notification Design

### UNUserNotificationCenter Integration

```swift
// tian/IPC/Handlers/NotifyHandler.swift

import UserNotifications

@MainActor
enum NotifyHandler {
    /// Lazy-initialized flag to track whether we've requested authorization.
    private static var hasRequestedAuth = false

    static func send(_ request: IPCRequest) async -> IPCResponse {
        let message = request.params["message"] ?? ""
        let title = request.params["title"] ?? "tian"
        let subtitle = request.params["subtitle"]
        let paneID = request.env["paneID"] ?? ""

        guard !message.isEmpty else {
            return .error(code: "invalid_args",
                         message: "Notification message cannot be empty.",
                         exitCode: 1)
        }

        // Lazy authorization request
        let center = UNUserNotificationCenter.current()
        let authStatus = await checkOrRequestAuth(center: center)

        switch authStatus {
        case .denied:
            return .error(code: "permission_denied",
                         message: "Notification permission denied. Enable in System Settings > Notifications > tian.",
                         exitCode: 4)
        case .notDetermined:
            // Should not happen after requesting, but handle gracefully
            return .error(code: "permission_denied",
                         message: "Notification permission not granted.",
                         exitCode: 4)
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }

        // Schedule notification
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = message
        content.sound = .default
        content.userInfo = ["paneID": paneID]  // For click-to-focus routing

        let notificationRequest = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        do {
            try await center.add(notificationRequest)
            return .ok()
        } catch {
            return .error(code: "notification_failed",
                         message: "Failed to schedule notification: \(error.localizedDescription)",
                         exitCode: 1)
        }
    }

    private static func checkOrRequestAuth(
        center: UNUserNotificationCenter
    ) async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()

        if settings.authorizationStatus == .notDetermined && !hasRequestedAuth {
            hasRequestedAuth = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            return await center.notificationSettings().authorizationStatus
        }

        return settings.authorizationStatus
    }
}
```

### Click-to-Focus Routing

When the user clicks a notification, tian must activate the source pane. This requires implementing `UNUserNotificationCenterDelegate`:

```swift
// In TianAppDelegate (extended)
extension TianAppDelegate: UNUserNotificationCenterDelegate {
    func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let paneIDString = userInfo["paneID"] as? String,
              let paneID = UUID(uuidString: paneIDString) else {
            completionHandler()
            return
        }

        // Find the pane in the hierarchy and focus it
        focusPaneByID(paneID)

        // Bring app to foreground
        NSApp.activate(ignoringOtherApps: true)

        completionHandler()
    }

    /// Also handle foreground notifications (show banner even when app is active)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func focusPaneByID(_ paneID: UUID) {
        for collection in windowCoordinator.allWorkspaceCollections {
            for workspace in collection.workspaces {
                for space in workspace.spaceCollection.spaces {
                    for tab in space.tabs {
                        if tab.paneViewModel.surfaces.keys.contains(paneID) {
                            // Navigate to this pane
                            collection.activateWorkspace(id: workspace.id)
                            workspace.spaceCollection.activateSpace(id: space.id)
                            space.activateTab(id: tab.id)
                            tab.paneViewModel.focusPane(paneID: paneID)
                            return
                        }
                    }
                }
            }
        }
    }
}
```

**Call `setupNotificationDelegate()` in `applicationDidFinishLaunching` before any notifications could arrive.**

---

## 8. Environment Variable Injection Design

### Injection Point

Environment variables must be set before the shell process starts. The injection point is `GhosttyTerminalSurface.createSurface(view:workingDirectory:)` in `GhosttyTerminalSurface.swift` (line 19). The `ghostty_surface_config_s` has an environment field, but examining the current code, the config is built and passed to `ghostty_surface_new` which spawns the PTY.

**Approach:** Use `setenv()` on the process-level environment before calling `ghostty_surface_new()`. Since surface creation happens on `@MainActor` (serialized), there are no races between concurrent surface creations. After `ghostty_surface_new()` returns, `unsetenv()` to clean up.

```swift
// GhosttyTerminalSurface.swift (modified createSurface)

func createSurface(
    view: TerminalSurfaceView,
    workingDirectory: String? = nil,
    environmentContext: PaneEnvironmentContext? = nil  // <-- NEW
) {
    // ... existing config setup ...

    // Inject TIAN_* environment variables before shell spawn
    if let ctx = environmentContext {
        setenv("TIAN_SOCKET", ctx.socketPath, 1)
        setenv("TIAN_PANE_ID", ctx.paneID.uuidString, 1)
        setenv("TIAN_TAB_ID", ctx.tabID.uuidString, 1)
        setenv("TIAN_SPACE_ID", ctx.spaceID.uuidString, 1)
        setenv("TIAN_WORKSPACE_ID", ctx.workspaceID.uuidString, 1)
        setenv("TIAN_CLI_PATH", ctx.cliPath, 1)
    }

    // PATH injection for CLI discovery
    if let ctx = environmentContext {
        let cliDir = (ctx.cliPath as NSString).deletingLastPathComponent
        if let currentPath = getenv("PATH") {
            let path = String(cString: currentPath)
            setenv("PATH", "\(cliDir):\(path)", 1)
        }
    }

    let created: ghostty_surface_t? = workingDirectory.withCString { cWd in
        config.working_directory = cWd
        return ghostty_surface_new(ghosttyApp, &config)
    }

    // Clean up process-level env vars (they've been inherited by the child PTY)
    if environmentContext != nil {
        unsetenv("TIAN_SOCKET")
        unsetenv("TIAN_PANE_ID")
        unsetenv("TIAN_TAB_ID")
        unsetenv("TIAN_SPACE_ID")
        unsetenv("TIAN_WORKSPACE_ID")
        unsetenv("TIAN_CLI_PATH")
        // Restore original PATH
    }

    // ... rest of existing post-creation setup ...
}
```

### PaneEnvironmentContext

A simple value type carrying the env var values:

```swift
// tian/IPC/PaneEnvironmentContext.swift

struct PaneEnvironmentContext: Sendable {
    let socketPath: String
    let paneID: UUID
    let tabID: UUID
    let spaceID: UUID
    let workspaceID: UUID
    let cliPath: String

    static func make(
        socketPath: String,
        paneID: UUID,
        tab: TabModel,
        space: SpaceModel,
        workspace: Workspace
    ) -> PaneEnvironmentContext {
        let cliPath = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("tian-cli")
            .path ?? ""
        return PaneEnvironmentContext(
            socketPath: socketPath,
            paneID: paneID,
            tabID: tab.id,
            spaceID: space.id,
            workspaceID: workspace.id,
            cliPath: cliPath
        )
    }
}
```

### Propagation Through the Hierarchy

The `PaneEnvironmentContext` must be constructed at surface creation time, which means the call sites in `PaneViewModel`, `SpaceModel`, and `SpaceCollection` need access to the hierarchy context. The cleanest approach:

1. Add an `environmentContextFactory` closure to `PaneViewModel`:

```swift
// PaneViewModel (new property)
var environmentContextFactory: ((UUID) -> PaneEnvironmentContext?)?
```

2. Wire it from `SpaceModel`, similar to the existing `directoryFallback` pattern (see `SpaceModel.wireDirectoryFallback` at line 159-169 of `SpaceModel.swift`):

```swift
// SpaceModel (new wiring method)
private func wireEnvironmentContext(_ tab: TabModel) {
    tab.paneViewModel.environmentContextFactory = { [weak self, weak tab] paneID in
        guard let self, let tab,
              let workspace = self.owningWorkspace,
              let socketPath = IPCServer.shared?.socketPath else { return nil }
        return PaneEnvironmentContext.make(
            socketPath: socketPath,
            paneID: paneID,
            tab: tab,
            space: self,
            workspace: workspace
        )
    }
}
```

3. The `PaneViewModel.splitPane` and initial surface creation paths pass the context through to `GhosttyTerminalSurface.createSurface`.

### Stale Env Var Handling

Env vars are frozen at shell spawn time. They become stale when:

| Scenario | Stale Var | Detection |
|----------|-----------|-----------|
| Tab moved between spaces | `TIAN_SPACE_ID` | IPC handler checks pane's actual parent hierarchy |
| Space moved between workspaces | `TIAN_WORKSPACE_ID` | Same hierarchy check |
| Workspace renamed | None (UUIDs don't change) | N/A |
| Pane split creates new pane | None (new pane gets fresh env) | N/A |
| App restarted | All (new UUIDs) | Socket path different |

**Resolution:** The IPC handler validates env vars only when they are used for "default to current" resolution (e.g., `space create` without `--workspace` uses `TIAN_WORKSPACE_ID`). If the pane's actual parent chain does not match the env vars, return exit code 1 with a descriptive error.

---

## 9. Error Handling Matrix

### Exit Codes

| Code | Category | Meaning |
|------|----------|---------|
| 0 | Success | Command completed successfully |
| 1 | General error | Invalid arguments, entity not found, stale env, empty name |
| 2 | Connection error | Not in tian, socket not found, timeout, connection refused |
| 3 | Process safety | Running processes detected, --force not specified |
| 4 | Permission denied | Notification permissions denied |

### Error Scenarios

| Scenario | Where Detected | Exit Code | Error Message | Recovery |
|----------|---------------|-----------|---------------|----------|
| `TIAN_SOCKET` not set | CLI (EnvironmentCheck) | 2 | "Error: Not running inside tian. The tian CLI can only be used from within an tian terminal session." | Run from within tian |
| Socket file does not exist | CLI (IPCClient.connect) | 2 | "Error: Cannot connect to tian (socket not found at <path>). Is tian running?" | Launch tian, open a terminal |
| Connection refused | CLI (IPCClient.connect) | 2 | "Error: Cannot connect to tian (connection refused)." | Restart tian |
| Response timeout (5s) | CLI (IPCClient.recv) | 2 | "Error: Connection timed out. The tian app may be unresponsive." | Restart tian |
| Protocol version mismatch | App (IPCRequestRouter) | 1 | "Error: Protocol version mismatch. CLI version X, app expects Y. Update the CLI." | Update tian |
| Invalid JSON in request | App (IPCServer) | 1 | "Error: Invalid request format." | Bug in CLI |
| Unknown action | App (IPCRequestRouter) | 1 | "Error: Unknown action: <action>." | Check CLI version |
| Workspace not found | App (WorkspaceHandler) | 1 | "Error: Workspace not found: <uuid>." | Use `tian workspace list` |
| Space not found | App (SpaceHandler) | 1 | "Error: Space not found: <uuid>." | Use `tian space list` |
| Tab not found | App (TabHandler) | 1 | "Error: Tab not found: <uuid>." | Use `tian tab list` |
| Pane not found | App (PaneHandler) | 1 | "Error: Pane not found: <uuid>." | Use `tian pane list` |
| Empty workspace name | App (WorkspaceHandler) | 1 | "Error: Workspace name cannot be empty." | Provide a name |
| Stale env: space not in workspace | App (hierarchy check) | 1 | "Error: Stale environment detected. Space <id> is no longer in workspace <id>." | Open new terminal in correct context |
| Close with running processes | App (ProcessDetector) | 3 | "Error: <entity> has N panes with running processes. Use --force to close anyway." | Add --force flag |
| Notification permission denied | App (NotifyHandler) | 4 | "Warning: Notification permission denied. Enable in System Settings > Notifications > tian." (stderr) | Grant permission in System Settings |
| Invalid tab focus index | App (TabHandler) | 1 | "Error: Tab index out of range. Space has N tabs." | Use valid index |
| Pane focus direction: no neighbor | App (PaneHandler) | 1 | "Error: No pane found in direction <dir>." | Pane is at edge |
| Invalid UUID format | CLI (argument parsing) | 1 | "Error: Invalid UUID: <value>." | Provide valid UUID |

### Error Output Format

All errors are written to stderr:

```
Error: <message>
```

For process safety errors, include details:

```
Error: Workspace "my-project" has 3 panes with running processes:
  - Space "development", Tab "Tab 1", Pane d4e5f6a7-...  (node)
  - Space "development", Tab "Tab 1", Pane e5f6a7b8-...  (python)
  - Space "testing", Tab "Tab 1", Pane f6a7b8c9-...      (cargo)
Use --force to close anyway.
```

The process names in parentheses come from `ghostty_surface_needs_confirm_quit` -- the existing process detection already surfaces the child process info.

---

## 10. Testing Strategy

### Unit Tests (tian-cli target)

| Component | Test | Approach |
|-----------|------|----------|
| Argument parsing | All subcommands parse correctly | `swift-argument-parser` built-in test helpers |
| TableFormatter | Column alignment, truncation, active marker | Pure function, string comparison |
| JSONFormatter | Valid JSON output, correct keys | Decode output, assert structure |
| EnvironmentCheck | Missing vars, partial vars, all present | Set/unset env vars in test |
| Request serialization | All action types produce valid JSON | Encode and decode round-trip |
| Response parsing | Success and error responses | Decode from fixture JSON |
| CLILogger | Log format, rotation trigger | Write to temp file, check format |

### Unit Tests (tian target, app-side)

| Component | Test | Approach |
|-----------|------|----------|
| IPCProtocol | Length-prefix encode/decode | Byte-level round-trip |
| IPCRequestRouter | All actions route correctly | Mock handler, verify dispatch |
| WorkspaceHandler | Create, list, close, focus | Create `WorkspaceCollection`, call handler, assert state |
| SpaceHandler | Create, list, close, focus | Same pattern with `SpaceCollection` |
| TabHandler | Create, list, close, focus (UUID and index) | Same pattern with `SpaceModel` |
| PaneHandler | Split, list, close, focus (UUID and direction) | Same pattern with `PaneViewModel` (mock surfaces) |
| StatusModel | Set, clear, pane close cleanup, multi-pane | Direct model operations |
| StatusModel.activeLabel | Most-recent-wins across pane IDs | Set multiple, verify correct one returned |
| Stale env detection | Mismatched hierarchy returns error | Construct hierarchy, send mismatched env |
| Process safety | Detect running processes, force flag | Mock `ghostty_surface_needs_confirm_quit` |

### Integration Tests

| Test | Approach |
|------|----------|
| Socket lifecycle | Start server, connect client, send request, verify response, stop server |
| End-to-end create | CLI binary creates workspace, verify in model |
| End-to-end list | Create entities, run list CLI, verify output |
| Concurrent connections | Multiple CLI processes send simultaneously, all get correct responses |
| Timeout behavior | Start server, don't respond, verify CLI times out |
| Stale socket cleanup | Leave socket file, start server, verify it recovers |

### UI Tests (tianUITests target)

| Test | Approach |
|------|----------|
| Status display | Simulate status set via IPC, verify sidebar shows label |
| Status clear | Set then clear, verify label disappears |
| Notification delivery | Send notify, verify UNUserNotificationCenter received request |

### Manual Testing Checklist

- [ ] Run `tian workspace list` inside tian -- table output correct
- [ ] Run `tian workspace list --format json` -- valid JSON
- [ ] Run `tian workspace list` outside tian -- clear error, exit code 2
- [ ] Run `tian --help` outside tian -- help text shown, exit code 0
- [ ] Run `tian status set --label "test"` -- sidebar updates within 100ms
- [ ] Run `tian status clear` -- sidebar label disappears
- [ ] Close pane with status -- status automatically cleared
- [ ] Run `tian notify "hello"` -- notification appears
- [ ] Click notification -- tian window activates, source pane focused
- [ ] Run `tian workspace close <id>` with running processes -- safety error
- [ ] Run `tian workspace close <id> --force` -- closes despite processes
- [ ] Kill tian while CLI is in flight -- CLI times out in 5s
- [ ] Restart tian after crash -- stale socket cleaned up, new socket works

---

## 11. Implementation Phases

### Phase 1: IPC Foundation (estimated: 3-4 days)

**Goal:** Establish the communication channel. No commands yet, just the socket and protocol.

**Deliverables:**
1. `IPCServer` -- socket bind, listen, accept, length-prefixed read/write
2. `IPCProtocol` -- `IPCRequest` and `IPCResponse` Codable types
3. `IPCClient` -- connect, send, receive (in `tian-cli` target)
4. `EnvironmentCheck` -- validate TIAN_* env vars
5. `tian-cli` target in `project.yml` with `main.swift` entry point
6. Wire `IPCServer.start()/stop()` in `TianAppDelegate`
7. Implement a single echo/ping action for end-to-end validation

**Tests:** Socket lifecycle, length-prefix encoding, round-trip echo.

**Files created/modified:**
- NEW: `tian/IPC/IPCServer.swift`
- NEW: `tian/IPC/IPCProtocol.swift`
- NEW: `tian-cli/main.swift`
- NEW: `tian-cli/IPCClient.swift`
- NEW: `tian-cli/EnvironmentCheck.swift`
- MOD: `tian/WindowManagement/TianAppDelegate.swift` (start/stop server)
- MOD: `project.yml` (add tian-cli target)

### Phase 2: Environment Variable Injection (estimated: 2 days)

**Goal:** Every shell session inside tian has `TIAN_*` vars and `tian` on PATH.

**Deliverables:**
1. `PaneEnvironmentContext` value type
2. Modified `GhosttyTerminalSurface.createSurface` to accept and inject env vars
3. `environmentContextFactory` closure on `PaneViewModel`
4. Wiring through `SpaceModel` -> `TabModel` -> `PaneViewModel`
5. PATH prepend for CLI binary directory

**Tests:** Verify env vars present in spawned shell (manual: `env | grep TIAN`).

**Files created/modified:**
- NEW: `tian/IPC/PaneEnvironmentContext.swift`
- MOD: `tian/Core/GhosttyTerminalSurface.swift` (env injection in createSurface)
- MOD: `tian/Pane/PaneViewModel.swift` (environmentContextFactory, pass to createSurface)
- MOD: `tian/Tab/SpaceModel.swift` (wire environmentContextFactory)

### Phase 3: Status Reporting (estimated: 2-3 days)

**Goal:** `tian status set/clear` works end-to-end with sidebar display.

**Deliverables:**
1. `StatusModel` (set, clear, pane close cleanup, activeLabel)
2. `StatusHandler` (IPC handler for status.set and status.clear)
3. `StatusCommand` (CLI argument parsing)
4. Modified `SidebarSpaceRowView` with status label display
5. Pane-close cleanup wiring

**Tests:** StatusModel unit tests, visual verification of sidebar display.

**Files created/modified:**
- NEW: `tian/Models/StatusModel.swift`
- NEW: `tian/IPC/Handlers/StatusHandler.swift`
- NEW: `tian-cli/Commands/StatusCommand.swift`
- MOD: `tian/View/Sidebar/SidebarSpaceRowView.swift` (status label)
- MOD: `tian/View/Sidebar/SidebarExpandedContentView.swift` (pass statusModel)
- MOD: `tian/Pane/PaneViewModel.swift` (pane close notification)

### Phase 4: Notifications (estimated: 1-2 days)

**Goal:** `tian notify` sends macOS notifications with click-to-focus.

**Deliverables:**
1. `NotifyHandler` (lazy auth, UNUserNotificationCenter integration)
2. `NotifyCommand` (CLI argument parsing)
3. `UNUserNotificationCenterDelegate` on `TianAppDelegate` (click routing)
4. `focusPaneByID` hierarchy traversal

**Tests:** Notification delivery, permission denied handling, click-to-focus.

**Files created/modified:**
- NEW: `tian/IPC/Handlers/NotifyHandler.swift`
- NEW: `tian-cli/Commands/NotifyCommand.swift`
- MOD: `tian/WindowManagement/TianAppDelegate.swift` (notification delegate)

### Phase 5: Workspace CRUD + Navigation (estimated: 3-4 days)

**Goal:** All workspace commands work: create, list, close (with process safety), focus.

**Deliverables:**
1. `WorkspaceHandler` (CRUD + navigation, process safety checks)
2. `WorkspaceCommand` (CLI subcommands)
3. `TableFormatter` and `JSONFormatter` for list output
4. `IPCRequestRouter` action dispatch for workspace.*
5. Stale env var detection for workspace-scoped operations

**Tests:** All workspace operations against real `WorkspaceCollection`.

**Files created/modified:**
- NEW: `tian/IPC/Handlers/WorkspaceHandler.swift`
- NEW: `tian/IPC/IPCRequestRouter.swift`
- NEW: `tian-cli/Commands/WorkspaceCommand.swift`
- NEW: `tian-cli/Output/TableFormatter.swift`
- NEW: `tian-cli/Output/JSONFormatter.swift`

### Phase 6: Space, Tab, Pane CRUD + Navigation (estimated: 4-5 days)

**Goal:** All remaining entity commands work.

**Deliverables:**
1. `SpaceHandler`, `TabHandler`, `PaneHandler`
2. `SpaceCommand`, `TabCommand`, `PaneCommand`
3. Tab focus by index (reuse `SpaceModel.goToTab`)
4. Pane focus by direction (reuse `PaneViewModel.focusDirection`)
5. Pane split (reuse `PaneViewModel.splitPane`)

**Tests:** Full CRUD for all entity types.

**Files created/modified:**
- NEW: `tian/IPC/Handlers/SpaceHandler.swift`
- NEW: `tian/IPC/Handlers/TabHandler.swift`
- NEW: `tian/IPC/Handlers/PaneHandler.swift`
- NEW: `tian-cli/Commands/SpaceCommand.swift`
- NEW: `tian-cli/Commands/TabCommand.swift`
- NEW: `tian-cli/Commands/PaneCommand.swift`

### Phase 7: CLI Logging + Polish (estimated: 1-2 days)

**Goal:** Production readiness.

**Deliverables:**
1. `CLILogger` (file logging with rotation)
2. `--version` and `--help` for all subcommands
3. Log category for IPC: `Log.ipc` added to `Logger.swift`
4. Edge case handling (empty strings, max label length, large list outputs)

**Files created/modified:**
- NEW: `tian-cli/CLILogger.swift`
- MOD: `tian/Utilities/Logger.swift` (add `ipc` category)

### Dependency Graph

```
Phase 1 (IPC Foundation)
    |
    +---> Phase 2 (Env Var Injection)
    |
    +---> Phase 3 (Status) -------> Phase 7 (Polish)
    |
    +---> Phase 4 (Notifications)
    |
    +---> Phase 5 (Workspace CRUD) --> Phase 6 (Space/Tab/Pane CRUD)
```

Phases 2, 3, 4, and 5 can proceed in parallel after Phase 1 is complete. Phase 6 depends on Phase 5 (shares the handler pattern and formatters). Phase 7 is final polish.

**Total estimated effort: 16-22 days**

---

## Appendix A: Full Request/Response Type Definitions

```swift
// tian/IPC/IPCProtocol.swift

struct IPCRequest: Codable, Sendable {
    let v: Int                              // Protocol version
    let action: String                      // "resource.verb"
    let params: [String: String?]           // Action-specific parameters
    let env: IPCEnvironment                 // Caller's TIAN_* env vars
}

struct IPCEnvironment: Codable, Sendable {
    let paneID: String
    let tabID: String
    let spaceID: String
    let workspaceID: String
}

struct IPCResponse: Codable, Sendable {
    let v: Int
    let ok: Bool
    let data: [String: AnyCodable]?         // Present on success
    let error: IPCError?                    // Present on failure

    static func ok(data: [String: AnyCodable] = [:]) -> IPCResponse {
        IPCResponse(v: 1, ok: true, data: data, error: nil)
    }

    static func error(code: String, message: String, exitCode: Int) -> IPCResponse {
        IPCResponse(v: 1, ok: false, data: nil,
                   error: IPCError(code: code, message: message, exitCode: exitCode))
    }
}

struct IPCError: Codable, Sendable {
    let code: String                        // Machine-readable error code
    let message: String                     // Human-readable message
    let exitCode: Int                       // CLI exit code to use
}
```

## Appendix B: Environment Variable Reference

| Variable | Source | Example | When Stale |
|----------|--------|---------|------------|
| `TIAN_SOCKET` | `IPCServer.socketPath` | `/var/folders/.../T/tian-501.sock` | App restarted |
| `TIAN_PANE_ID` | `PaneViewModel` pane UUID | `d4e5f6a7-b8c9-0123-defg-456789012345` | Never (pane ID is stable) |
| `TIAN_TAB_ID` | `TabModel.id` | `c3d4e5f6-a7b8-9012-cdef-123456789012` | Tab moved between spaces (not supported in v1) |
| `TIAN_SPACE_ID` | `SpaceModel.id` | `b2c3d4e5-f6a7-8901-bcde-f12345678901` | Space moved between workspaces (drag-drop) |
| `TIAN_WORKSPACE_ID` | `Workspace.id` | `a1b2c3d4-e5f6-7890-abcd-ef1234567890` | Workspace deleted while shell running |
| `TIAN_CLI_PATH` | `Bundle.main` path | `.../tian.app/Contents/MacOS/tian-cli` | App bundle moved |

## Appendix C: Sidebar Layout Mockup

```
SIDEBAR (expanded)
+--------------------------------------------------+
| (.) DEFAULT                              [+]     |  <-- SidebarWorkspaceHeaderView
+--------------------------------------------------+
|   (o)  default                      2 tabs       |  <-- SidebarSpaceRowView (active)
|        Thinking...                                |  <-- Status label (10pt, secondary)
+--------------------------------------------------+
|   ( )  feature-branch               1 tab        |  <-- SidebarSpaceRowView (inactive)
+--------------------------------------------------+
|                                                   |
| (.) MY-PROJECT                       [+]         |  <-- Another workspace
+--------------------------------------------------+
|   ( )  development                   3 tabs      |
|   ( )  testing                       1 tab       |
+--------------------------------------------------+

Legend:
  (o) = green dot (active space in active workspace)
  ( ) = gray dot (inactive space)
  (.) = accent-color dot (workspace header)
  [+] = add space button
  "Thinking..." = status from `tian status set --label "Thinking..."`
```
