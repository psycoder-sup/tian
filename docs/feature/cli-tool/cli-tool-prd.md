# PRD: CLI Tool (`tian`)

**Author:** psycoder
**Date:** 2026-04-05
**Version:** 1.2
**Status:** Approved

---

## 1. Overview

A command-line tool (`tian`) that enables programmatic control of the tian terminal emulator from within its own shell sessions. The CLI communicates with the running tian app over IPC (Unix domain socket) to manage the full workspace hierarchy (Workspace > Space > Tab > Pane), report process status to the sidebar, and trigger macOS system notifications.

The CLI serves two distinct use cases:

1. **Status and notifications (Claude Code hooks):** Hooks report progress status to the sidebar and send macOS notifications on task completion. Hooks do not create or manage workspaces, spaces, tabs, or panes.
2. **Workspace management (scripts and AI agents):** Scripts and AI agents like Claude Code use CRUD operations to programmatically create, navigate, and manage workspaces, spaces, tabs, and panes.

The CLI is machine-facing: all entity targeting uses UUIDs, not names. It is scoped exclusively to tian and refuses to execute when run outside an tian shell session.

**Why now:** The main PRD (open question #9) identified a CLI tool as a TBD feature. Two concrete integration points make this actionable: Claude Code hooks need to report progress and send notifications from the shell, and AI agents need to programmatically manage workspace hierarchy. No IPC mechanism currently exists in tian (no URL scheme, no XPC service, no socket, no CLI).

---

## 2. Problem Statement

**User Pain Point:** Developer tools running inside tian's terminal sessions have no way to interact with the tian app itself. Claude Code hooks, shell scripts, and automation tools cannot create workspaces, switch contexts, report status, or send notifications programmatically. The developer must manually perform all workspace/space/tab management through keyboard shortcuts or sidebar clicks, even when the tool driving the terminal knows exactly what context it needs.

**Current Workaround:** All workspace hierarchy management is manual. There is no status reporting mechanism -- the developer must watch terminal output directly to understand what a long-running tool is doing. There is no notification mechanism -- the developer must keep the terminal window visible or remember to check back. The `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` callback exists in GhosttyApp but returns `true` without any handling.

**Business Opportunity:** A CLI tool transforms tian from a passive terminal into a programmable workspace manager. Claude Code hooks can report thinking/progress status in the sidebar and notify on task completion. Scripts and AI agents can programmatically create and manage workspaces, spaces, tabs, and panes to set up project contexts. This reduces manual overhead and makes the 4-level hierarchy useful for automation, not just manual organization.

---

## 3. Goals & Non-Goals

### Goals

- **G1:** Provide full CRUD and navigation operations for all four hierarchy levels (Workspace, Space, Tab, Pane) via a CLI tool, with all entity targeting by UUID.
- **G2:** Enable process status reporting from shell sessions to tian's sidebar (label), callable from Claude Code hooks.
- **G3:** Enable macOS system notifications from shell sessions via the CLI, callable from Claude Code hooks.
- **G4:** Establish an IPC channel (Unix domain socket) between the CLI and the running tian app, with environment variables injected into shell sessions for targeting.
- **G5:** Hard-block CLI execution outside of tian -- the CLI must refuse to run and exit with an error when tian environment variables are absent.

### Non-Goals

- **NG1:** Running arbitrary shell commands via the CLI (this is not a remote execution tool).
- **NG2:** Controlling tian from outside tian (e.g., from a different terminal emulator or a separate machine). The CLI is tian-only by design.
- **NG3:** Bidirectional streaming or event subscription (e.g., "watch for space changes"). The CLI is request-response only in v1.
- **NG4:** GUI for status/notification configuration. Status display is integrated into the existing sidebar; notifications use macOS system notifications.
- **NG5:** Plugin or extension API. The CLI is a standalone binary, not a framework.
- **NG6:** Scriptable configuration changes (e.g., `tian config set font-size 14`). Configuration remains file-based.
- **NG7:** Tab renaming via CLI. Tabs are auto-named from the terminal title (OSC 0/2) and do not support user-assigned names in the current model (`TabModel.name` is set at creation but display uses `TabModel.title` from the focused pane's terminal).
- **NG8:** Name-based entity targeting. The CLI is machine-facing; all lookups use UUIDs. Human-facing operations like renaming are not exposed.
- **NG9:** Multi-window support. v1 is scoped to a single window (tian is single-window in practice today).

---

## 4. User Stories

| # | As a... | I want to... | So that... |
|---|---------|--------------|------------|
| 1 | developer | run `tian workspace create "my-project" --directory ~/Code/my-project` from a script or AI agent | a new workspace is created with the specified working directory, and the returned UUID can be used for subsequent commands |
| 2 | developer | run `tian workspace list --format json` to get all workspaces with their UUIDs | my scripts can discover and target existing workspaces by UUID |
| 3 | developer | run `tian space focus <id>` to switch to a specific space | my automation can navigate to a specific space without keyboard shortcuts |
| 4 | developer | run `tian pane split --direction horizontal` from a script or AI agent | a split layout is set up for a task (e.g., editor + server) |
| 5 | developer | run `tian status set --label "Thinking..."` from a Claude Code hook | I can see what Claude Code is doing in tian's sidebar without watching terminal output |
| 6 | developer | run `tian status clear` when a task finishes | the sidebar status indicator is cleaned up automatically |
| 7 | developer | run `tian notify "Build complete"` from a hook | I get a macOS notification when a long-running task finishes, even if tian is not in the foreground |
| 8 | developer | have `tian` refuse to run when I accidentally invoke it from iTerm2 | I don't get confusing errors from trying to control an app I'm not running inside |
| 9 | developer | run `tian workspace focus <id>` | my script can bring a specific workspace to the foreground |
| 10 | developer | run `tian pane list` to enumerate panes in the current tab | my automation can identify pane UUIDs for targeted operations |

---

## 5. Functional Requirements

### Environment and IPC

**FR-01:** tian must inject the following environment variables into every shell session it spawns:
- `TIAN_SOCKET` -- absolute path to the Unix domain socket for IPC
- `TIAN_PANE_ID` -- UUID of the pane hosting this shell session
- `TIAN_TAB_ID` -- UUID of the tab containing this pane
- `TIAN_SPACE_ID` -- UUID of the space containing this tab
- `TIAN_WORKSPACE_ID` -- UUID of the workspace containing this space
- `TIAN_CLI_PATH` -- absolute path to the CLI binary inside the app bundle (e.g., `tian.app/Contents/MacOS/tian-cli`). Hooks can use `$TIAN_CLI_PATH` directly without manual installation.

These must be set before the shell process starts (via the PTY environment, not shell RC files).

**Caveat:** `TIAN_WORKSPACE_ID`, `TIAN_SPACE_ID`, and `TIAN_TAB_ID` may become stale if tabs or spaces are dragged between workspaces or spaces after the shell has started. The CLI sends all env vars with each request; if the IPC handler detects that the pane's actual parent hierarchy no longer matches the env vars, it returns an error. New panes (from splits) receive fresh, correct env vars at spawn time.

**FR-02:** The tian app must create and listen on a Unix domain socket at a well-known, per-user path (e.g., `$TMPDIR/tian-$UID.sock` or `~/Library/Application Support/tian/tian.sock`). The socket must be created when the app launches and removed when the app terminates (including crash cleanup on next launch if a stale socket file exists). A single socket serves the single window.

**FR-03:** The CLI must check for the presence of `TIAN_SOCKET` before executing any command. If the variable is absent or the socket file does not exist, the CLI must print a clear error message (e.g., "Error: Not running inside tian. The tian CLI can only be used from within an tian terminal session.") and exit with a non-zero exit code.

**FR-04:** The IPC protocol must be request-response: the CLI sends a request, the app processes it, and the app sends a response. The CLI blocks until the response is received (with a configurable timeout, default 5 seconds).

### Workspace CRUD + Navigation

**FR-05:** `tian workspace create <name> [--directory <path>]` -- Create a new workspace with the given display name and optional default working directory. Returns the new workspace's UUID on success. Prints an error if the name is empty.

**FR-06:** `tian workspace list [--format json|table]` -- List all workspaces in the window. Default format is a human-readable table (name, UUID, space count, active indicator). `--format json` outputs machine-readable JSON. Callers use the returned UUIDs for subsequent operations.

**FR-07:** `tian workspace close <id> [--force]` -- Close a workspace by UUID. Cascading close rules apply (all spaces, tabs, panes within are closed). Process safety checks are performed in the IPC handler: if any pane within the workspace has a running foreground process, the CLI must print a warning and require `--force` to proceed. Without `--force`, the command exits with a non-zero code.

**FR-08:** `tian workspace focus <id>` -- Switch to the specified workspace by UUID. Prints an error if the workspace is not found.

### Space CRUD + Navigation

**FR-09:** `tian space create [<name>] [--workspace <id>]` -- Create a new space in the specified workspace (defaults to the current workspace, identified via `TIAN_WORKSPACE_ID`). Name is optional (for sidebar display; auto-generated if omitted). Returns the new space's UUID.

**FR-10:** `tian space list [--workspace <id>] [--format json|table]` -- List spaces in the specified workspace (defaults to current).

**FR-11:** `tian space close <id> [--workspace <id>] [--force]` -- Close a space by UUID. Same process-check behavior as workspace close (checked in IPC handler).

**FR-12:** `tian space focus <id> [--workspace <id>]` -- Switch to the specified space by UUID within the given workspace.

### Tab CRUD + Navigation

**FR-13:** `tian tab create [--space <id>] [--directory <path>]` -- Create a new tab in the specified space (defaults to the current space). Returns the new tab's UUID.

**FR-14:** `tian tab list [--space <id>] [--format json|table]` -- List tabs in the specified space.

**FR-15:** `tian tab close [<id>] [--force]` -- Close a tab by UUID (defaults to the current tab). Same process-check behavior (checked in IPC handler).

**FR-16:** `tian tab focus <id-or-index>` -- Switch to a tab by UUID or 1-based index within the current space. Index 9 always focuses the last tab (matching `SpaceModel.goToTab` behavior).

### Pane CRUD + Navigation

**FR-17:** `tian pane split [--pane <id>] [--direction horizontal|vertical]` -- Split the specified pane (defaults to the current pane via `TIAN_PANE_ID`) in the given direction (defaults to vertical, matching the most common split). Returns the new pane's UUID. The new pane inherits the working directory of the source pane.

**FR-18:** `tian pane list [--tab <id>] [--format json|table]` -- List panes in the specified tab (defaults to the current tab). Output includes pane UUID, working directory, and state (running, exited, spawn-failed).

**FR-19:** `tian pane close [--pane <id>]` -- Close a pane by UUID (defaults to the current pane via `TIAN_PANE_ID`). Cascading close rules apply.

**FR-20:** `tian pane focus <id-or-direction> [--pane <id>]` -- Focus a pane by UUID or by direction (`up`, `down`, `left`, `right`) relative to the specified pane (defaults to the current pane via `TIAN_PANE_ID`). Directional focus uses the existing `SplitNavigation.neighbor` logic.

### Status Reporting

**FR-21:** `tian status set --label <text>` -- Set a status indicator for the current pane (identified by `TIAN_PANE_ID`). The label is a short text string (recommended max 50 characters, truncated with ellipsis in display). The status is displayed inline with the pane's parent space row in the sidebar.

**FR-22:** `tian status clear` -- Clear the status indicator for the current pane. The sidebar returns to its normal display.

**FR-23:** Status must be scoped to a pane (identified by `TIAN_PANE_ID`). Multiple panes can have independent status indicators simultaneously.

**FR-24:** Status must be ephemeral -- not persisted across app restarts. When a pane closes, its status is automatically cleared.

**FR-25:** If a `status set` command is sent while a status is already displayed for that pane, the new status replaces the old one (no queueing).

### Notifications

**FR-26:** `tian notify <message> [--title <title>] [--subtitle <subtitle>]` -- Send a macOS system notification via `UNUserNotificationCenter`. The `title` defaults to "tian" if omitted. The notification must be delivered regardless of whether tian is in the foreground.

**FR-27:** The tian app must request notification authorization (`.alert`, `.sound`) on first use (lazy, not on app launch). If the user has denied notification permissions, the `notify` command must print a warning to stderr and exit with code 4 (permission denied).

**FR-28:** Clicking a notification must bring the tian window containing the source pane to the foreground and focus that pane.

### CLI Output and Errors

**FR-29:** All successful write operations (create, close, split, focus, status set, notify) must exit with code 0 and print a confirmation message to stdout. Create operations must include the UUID of the created entity.

**FR-30:** All errors must be printed to stderr with a human-readable message and exit with a non-zero code. Error categories:
- Exit code 1: General error (invalid arguments, entity not found, empty name, stale env var mismatch)
- Exit code 2: Connection error (socket not found, connection refused, timeout)
- Exit code 3: Process safety error (running processes detected, `--force` not specified)
- Exit code 4: Permission denied (notification permissions denied by user)

**FR-31:** Every CLI invocation must be logged to `~/Library/Logs/tian/cli.log`. Each log entry includes: timestamp, full command with arguments, exit code, result (UUID for creates, error message for failures), and duration. The log file must be rotated or capped to prevent unbounded growth.

**FR-32:** `tian --version` must print the CLI version. `tian --help` and `tian <subcommand> --help` must print usage information.

### CLI Installation

**FR-33:** The CLI binary must be bundled inside the tian app bundle (e.g., `tian.app/Contents/MacOS/tian-cli`). tian must prepend the CLI binary's directory to `PATH` in the PTY environment so that `tian` is available as a command in every shell session without any manual installation. Combined with `TIAN_CLI_PATH` (FR-01), both direct usage (`tian status set ...`) and explicit path usage (`$TIAN_CLI_PATH status set ...`) work out of the box.

---

## 6. Non-Functional Requirements

**NFR-01: Latency.** CLI commands must complete (response received from app) within 100ms for CRUD operations under normal conditions (single-digit workspaces/spaces). The 5-second timeout is a safety net, not an expected latency.

**NFR-02: Reliability.** The IPC socket must handle concurrent CLI invocations gracefully. Multiple CLI processes sending commands simultaneously must not corrupt app state or produce interleaved responses. The app must process IPC requests serially or with proper synchronization.

**NFR-03: Binary size.** The CLI binary should be lightweight (target: under 5MB). It is a thin client that serializes commands and deserializes responses; all logic lives in the app.

**NFR-04: Crash safety.** If the tian app crashes or is force-quit while a CLI command is in flight, the CLI must time out and print a connection error -- not hang indefinitely.

**NFR-05: Socket permissions.** The Unix domain socket must be created with permissions restricted to the current user (mode 0600) to prevent other users on the system from sending commands to the terminal.

**NFR-06: Stale socket cleanup.** On launch, the tian app must check for a stale socket file from a previous crash and remove it before binding.

---

## 7. UX / Design Notes

### CLI UX

The CLI follows standard Unix conventions:

```
tian <resource> <verb> [arguments] [--flags]
```

Resources: `workspace`, `space`, `tab`, `pane`, `status`, `notify`.

All entity targeting uses UUIDs. The `list` commands return UUIDs that callers use for subsequent operations. The `create` commands return the new entity's UUID.

Resource-verb pattern for CRUD:
```
tian workspace create "my-project" --directory ~/Code/my-project
tian workspace list
tian workspace close a1b2c3d4-e5f6-7890-abcd-ef1234567890
tian workspace focus a1b2c3d4-e5f6-7890-abcd-ef1234567890

tian space create "feature-branch"
tian space list
tian space focus b2c3d4e5-f6a7-8901-bcde-f12345678901

tian tab create --directory ~/Code/my-project
tian tab list
tian tab focus 2
tian tab focus c3d4e5f6-a7b8-9012-cdef-123456789012

tian pane split --direction horizontal
tian pane list
tian pane focus left
tian pane close

tian status set --label "Thinking..."
tian status clear

tian notify "Task complete" --title "Claude Code"
```

Table output (default for `list` commands):
```
$ tian workspace list
  NAME          ID                                     SPACES  ACTIVE
* my-project    a1b2c3d4-e5f6-7890-abcd-ef1234567890   3       yes
  personal      f0e1d2c3-b4a5-6789-0123-456789abcdef   1       no
```

JSON output (for scripting):
```
$ tian workspace list --format json
[
  {"id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890", "name": "my-project", "spaces": 3, "active": true},
  {"id": "f0e1d2c3-b4a5-6789-0123-456789abcdef", "name": "personal", "spaces": 1, "active": false}
]
```

Error output:
```
$ tian workspace close a1b2c3d4-e5f6-7890-abcd-ef1234567890
Error: Workspace "my-project" (a1b2c3d4-...) has 2 panes with running processes.
Use --force to close anyway.

$ tian workspace focus 00000000-0000-0000-0000-000000000000
Error: Workspace not found: 00000000-0000-0000-0000-000000000000

$ tian space focus b2c3d4e5-f6a7-8901-bcde-f12345678901
Error: Stale environment detected. Space b2c3d4e5-... is no longer in workspace a1b2c3d4-....
```

Outside tian:
```
$ tian workspace list
Error: Not running inside tian.
The tian CLI can only be used from within an tian terminal session.
```

### Sidebar Status Display

Status appears inline with the space row in the sidebar. A compact status label is shown below the space name. When multiple panes in a space have status, the most recently updated pane's status is shown.

Display details:

- The status label is rendered in secondary text color, 10pt system font
- When no status is active, the area is hidden (no empty state placeholder)
- Status updates must be reflected in the sidebar within 100ms of receipt (no polling; IPC triggers immediate UI update)

### Notification Behavior

- Notifications use macOS `UNUserNotificationCenter` with the default presentation (banner)
- Notification title defaults to "tian" if not specified
- Notification body is the message text
- Notification sound uses the default system notification sound
- Clicking the notification activates the tian window and focuses the source pane
- Notifications are not grouped or stacked in v1 (each is independent)
- If notification permission is denied, the CLI exits with code 4 and prints a warning to stderr

---

## 8. Technical Boundaries

These are constraints the implementation must respect, without prescribing specific approaches:

**TB-01:** The CLI must be a standalone executable that can run without the app bundle present (it only needs the socket). It must not link against GhosttyKit or any app-internal frameworks.

**TB-02:** Environment variables (`TIAN_SOCKET`, `TIAN_PANE_ID`, `TIAN_CLI_PATH`, etc.) must be injected into the PTY environment before the shell starts. This means they must be set during surface creation, in the ghostty surface config or via the PTY setup path. The current `GhosttyTerminalSurface.createSurface` and its `ghostty_surface_config_s` are the relevant surface area.

**TB-03:** The IPC mechanism must not require the app to be sandboxed or require additional entitlements. Unix domain sockets work without sandbox restrictions (tian is not sandboxed, per `project.yml`).

**TB-04:** The CLI and app must agree on a versioned message format. The format must include a version field so the CLI can detect version mismatches (e.g., old CLI talking to new app) and print a helpful error.

**TB-05:** All workspace hierarchy mutations triggered by CLI commands must go through the existing model layer (`WorkspaceCollection`, `SpaceCollection`, `SpaceModel`, `PaneViewModel`). The IPC handler must dispatch to `@MainActor` to access these models safely. Process safety checks for cascading close operations (FR-07, FR-11, FR-15) are performed at the IPC handler level before dispatching to the model layer.

**TB-06:** The status model must be observable (to trigger sidebar re-renders) and must be associated with pane UUIDs. When a pane is closed, its status entry must be removed.

**TB-07:** Notification authorization must be requested lazily (on first `notify` command, not on app launch) to avoid prompting the user before they need notifications.

**TB-08:** The CLI binary must be code-signed with the same team identity as the app bundle for macOS Gatekeeper compatibility.

---

## 9. Success Metrics

Since tian is a personal tool with a single user, success is qualitative:

| Metric | Target |
|--------|--------|
| Hook integration | Claude Code hooks can report status and send notifications without manual intervention |
| CLI reliability | 100% of CLI commands succeed when the app is running and the arguments are valid (no spurious IPC failures) |
| Round-trip latency | CRUD commands complete in under 100ms (measured from CLI invocation to response received) |
| Status visibility | Status updates appear in the sidebar within 100ms of the CLI command |
| Notification delivery | Notifications appear within 1 second of the CLI command, even when tian is backgrounded |
| Environment correctness | All `TIAN_*` environment variables are present and correct in every spawned shell session, including panes created by splits |
| Blocking outside tian | CLI always exits with a clear error when run outside tian (no silent failures, no partial execution) |

---

## 10. Open Questions

| # | Question | Context | Owner | Due Date |
|---|----------|---------|-------|----------|
| 6 | Should `tian notify` support custom sounds or actions? | v1 uses the default notification sound and a single click-to-focus action. Custom sounds and action buttons could be post-v1. | psycoder | Post-v1 |

---

## 11. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-04-05 | Initial draft |
| 1.1 | 2026-04-05 | UUID-only targeting (drop name-based lookups and rename commands); single-window v1 scope; trust env vars with stale caveat and IPC mismatch error; sidebar status: Option A (inline with space row, most recently updated pane shown); exit code 4 for notification permission denial; add TIAN_CLI_PATH env var; clarify process safety checks at IPC handler level; remove "Daily workflow" metric; resolve OQ-1, OQ-2, OQ-3, OQ-5, OQ-7 |
| 1.2 | 2026-04-05 | Clarify two distinct use cases: hooks (status + notify) vs scripts/AI agents (CRUD); remove --progress from status set; add --pane flag to pane split/close/focus; status commands always use current pane (no --pane flag); add CLI command logging (FR-31); auto-enable CLI via PATH injection (no manual install); resolve OQ-4 |
