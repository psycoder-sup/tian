# SPEC: M5 -- Persistence

**Based on:** docs/feature/aterm/aterm-prd.md v1.4
**Author:** CTO Agent
**Date:** 2026-03-24
**Version:** 1.0
**Status:** Draft

---

## 1. Overview

Milestone 5 adds session persistence to aterm: the ability to serialize the full workspace hierarchy to disk on quit and restore it on launch, so the user never has to rebuild their terminal layout manually. This spec covers the quit flow (including a confirmation dialog when foreground processes are running), the JSON schema for persisted state, the serialization and deserialization pipeline, restore-time error handling, and instrumentation to measure restore correctness. M5 depends on M1 (PTY/shell), M2 (pane splitting), M3 (tabs/spaces), and M4 (workspaces) being complete, as it serializes the data models those milestones introduce.

---

## 2. Persisted State Schema (JSON)

### Storage Location

All persistence files live in `~/Library/Application Support/aterm/`. This directory is created on first quit-save if it does not exist. The primary state file is `state.json`. A backup of the previous state is kept as `state.prev.json` (overwritten each save cycle).

### JSON Schema

The top-level JSON object contains a `version` field (integer, starting at 1) to enable future schema migrations, a `savedAt` ISO-8601 timestamp, and the workspace hierarchy.

#### Top-Level Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| version | integer | yes | Schema version. Starts at 1. Used for forward-compatible migration on load. |
| savedAt | string (ISO-8601) | yes | Timestamp of when the state was saved. For debugging and staleness detection. |
| activeWorkspaceId | string (UUID) | yes | The UUID of the workspace that was focused at quit time. |
| workspaces | array of Workspace | yes | Ordered array of all workspaces. Order matches the user's arrangement. |

#### Workspace Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string (UUID) | yes | Stable identifier for the workspace. |
| name | string | yes | User-visible workspace name. |
| activeSpaceId | string (UUID) | yes | UUID of the last-active space within this workspace. |
| defaultWorkingDirectory | string or null | no | Default working directory for this workspace, if set. Null means inherit from global ($HOME). |
| spaces | array of Space | yes | Ordered array of spaces within this workspace. |
| windowFrame | WindowFrame object or null | no | Window geometry at save time. Null means use system default placement. |
| isFullscreen | boolean | no | Whether the window was in full-screen mode when saved. Defaults to false if absent. |

#### WindowFrame Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| x | number | yes | Window origin X coordinate (screen points). |
| y | number | yes | Window origin Y coordinate (screen points). |
| width | number | yes | Window width (screen points). |
| height | number | yes | Window height (screen points). |

**Offscreen detection on restore:** When restoring a workspace's window geometry, validate that the saved frame overlaps at least one connected display. If the frame is entirely offscreen (e.g., the user disconnected an external monitor), fall back to system default window placement. Use `NSScreen.screens` to enumerate connected displays and check for intersection with the saved frame rect.

#### Space Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string (UUID) | yes | Stable identifier for the space. |
| name | string | yes | User-visible space name. |
| activeTabId | string (UUID) | yes | UUID of the last-active tab within this space. |
| defaultWorkingDirectory | string or null | no | Default working directory for this space, if set. Null means inherit from workspace. |
| tabs | array of Tab | yes | Ordered array of tabs within this space. |

#### Tab Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | string (UUID) | yes | Stable identifier for the tab. |
| name | string or null | no | User-visible tab name, if renamed. Null means auto-generated. |
| activePaneId | string (UUID) | yes | UUID of the last-focused pane within this tab. |
| root | PaneNode (split or leaf) | yes | The root of the pane split tree for this tab. A PaneNode is either a split node (with `"type": "split"`, `"first"`, `"second"`) or a leaf node (with `"type": "pane"`, `"paneID"`, `"workingDirectory"`). |

#### PaneNode -- Split Case (recursive tree node)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| type | string literal "split" | yes | Discriminator for the union type. Always "split". |
| direction | string enum: "horizontal", "vertical" | yes | Split axis. "horizontal" means children are arranged left-to-right; "vertical" means top-to-bottom. |
| ratio | number (0.0 - 1.0) | yes | The proportion of available space allocated to the first child. Second child gets 1 - ratio. |
| first | PaneNode (split or leaf) | yes | The first child of this split (left or top, depending on direction). |
| second | PaneNode (split or leaf) | yes | The second child of this split (right or bottom, depending on direction). |

Note: This binary tree format uses `"first"` and `"second"` fields (not a `"children"` array) to directly mirror the runtime `PaneNode` enum which has `.leaf` and `.split` cases. This enables zero-translation `Codable` conformance -- the JSON structure maps 1:1 to the Swift type, requiring no custom serialization logic.

#### PaneNode -- Leaf Case (terminal pane)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| type | string literal "pane" | yes | Discriminator for the union type. Always "pane". |
| paneID | string (UUID) | yes | Stable identifier for this pane. Matches the `paneID` field in the runtime PaneNode.leaf case. |
| workingDirectory | string | yes | Absolute path of the pane's working directory at save time. |
| profileId | string or null | no | ID of the profile assigned to this pane, if any. Null means inherited. |

### Schema Versioning Strategy

The `version` field is an integer that increments whenever the schema changes in a backwards-incompatible way. On load:

1. Read the `version` field first.
2. If `version` equals the current expected version, deserialize directly.
3. If `version` is less than the current expected version, run a chain of migration functions (v1-to-v2, v2-to-v3, etc.) to transform the JSON before deserializing.
4. If `version` is greater than the current expected version (downgrade scenario), treat the state as corrupted -- fall back to default state.

Migration functions operate on raw JSON (dictionaries), not typed models, so they can handle any structural change.

---

## 3. Quit Flow

### Process Detection (FR-22)

Before serialization, the app must determine whether any pane has a foreground process running that is not the shell itself. The detection works as follows:

1. For each active PTY session, read the foreground process group ID using `tcgetpgrp()` on the PTY master file descriptor.
2. Compare the foreground process group ID to the shell's process group ID (captured at shell spawn time).
3. If they differ, a foreground child process is running. Collect the process name by reading `/proc`-equivalent info via `sysctl` with `KERN_PROCARGS2` or by calling `proc_pidpath()` from libproc.
4. Build a list of (pane identifier, process name) tuples for all panes with active foreground processes.

### Confirmation Dialog

If the foreground-process list is non-empty, present a native SwiftUI alert (or sheet) with:

- **Title:** "Processes are still running"
- **Body:** A scrollable list of pane identifiers (workspace > space > tab > pane position) and process names. If more than 8 entries, show the first 8 with a count of remaining (e.g., "and 3 more").
- **Primary button:** "Quit Anyway" (destructive style). Proceeds with serialization and quit.
- **Secondary button:** "Cancel". Aborts the quit entirely. The `NSApplication` terminate call is cancelled.

If the foreground-process list is empty, skip the dialog and proceed directly to serialization.

### Serialization Pipeline

After confirmation (or when no dialog is needed):

1. **Snapshot the hierarchy.** Walk the in-memory workspace model (Workspace > Space > Tab > pane split tree) and produce the JSON-serializable representation described in Section 2. This snapshot captures: (a) working directories by querying each PTY session's current working directory via `proc_pidinfo` with `PROC_PIDVNODEPATHINFO` on the shell PID, (b) window geometry per workspace by reading each NSWindow's frame rect, (c) full-screen state per workspace by checking the window's `styleMask` for `.fullScreen`.
2. **Encode to JSON.** Use `JSONEncoder` with `outputFormatting` set to `[.prettyPrinted, .sortedKeys]` for human-readability and stable diffs.
3. **Atomic write.** Write the JSON to a temporary file in the same directory, then rename it to `state.json` using `FileManager.replaceItemAt(_:withItemAt:)`. This ensures the state file is never partially written. Before the rename, copy the existing `state.json` to `state.prev.json` (best-effort; failure here does not block quit).
4. **Send SIGHUP.** After successful serialization, send SIGHUP to all PTY sessions by calling `close()` on the master file descriptor of each PTY (which causes SIGHUP to be delivered to the process group). Alternatively, explicitly `kill(-pgid, SIGHUP)` for each shell process group.
5. **Exit.** Allow the `NSApplication` termination to proceed.

### Serialization Failure Handling

If any step in the serialization pipeline fails (directory creation fails, encoding fails, write fails):

1. Log the error to the unified logging system (`os_log`) with fault level.
2. Do NOT block quit. Proceed to send SIGHUP and exit.
3. On next launch, the app will detect the missing or stale state file and start with default state.

### Integration with NSApplication Lifecycle

The quit flow hooks into `NSApplicationDelegate.applicationShouldTerminate(_:)`:

- Return `.terminateLater` to pause the termination sequence.
- Run process detection asynchronously (off main thread for the sysctl calls).
- If a dialog is needed, present it and wait for user response.
- On "Quit Anyway" or no dialog needed, run serialization, then call `NSApplication.shared.reply(toApplicationShouldTerminate: true)`.
- On "Cancel", call `NSApplication.shared.reply(toApplicationShouldTerminate: false)`.

---

## 4. Restore Flow

### Launch Sequence

On app launch, the restore flow runs before any UI is shown:

1. **Check for state file.** Look for `~/Library/Application Support/aterm/state.json`.
2. **If not found:** Launch with default state (one workspace named "default", one space named "default", one tab, one pane in `$HOME`). This is the first-launch experience.
3. **If found:** Read and decode the file. On any failure, fall back to default state (see error handling below).

### Deserialization Pipeline

1. **Read file.** Read the entire `state.json` into a `Data` object.
2. **Parse version.** Decode only the `version` field first (partial decode). If the version is higher than the app's current schema version, treat as corrupted.
3. **Migrate if needed.** If the version is lower than current, run the migration chain on the raw JSON dictionary.
4. **Full decode.** Decode the complete state into the typed model hierarchy using `JSONDecoder`.
5. **Validate the tree.** Walk the decoded hierarchy and validate structural invariants:
   - Every workspace has at least one space.
   - Every space has at least one tab.
   - Every tab has a non-null root node.
   - Every PaneNode leaf has a non-empty workingDirectory.
   - The activeWorkspaceId references an existing workspace.
   - Each activeSpaceId references an existing space within its workspace.
   - Each activeTabId references an existing tab within its space.
   - Each activePaneId references an existing pane within its tab's split tree.
   - All UUIDs are unique across the entire state.
6. **Resolve working directories.** For each PaneNode leaf, check whether the saved `workingDirectory` exists on disk using `FileManager.fileExists(atPath:isDirectory:)`. If the directory does not exist, replace it with `$HOME` and record a mismatch for instrumentation. Optionally, show a transient notification in the pane (e.g., "[saved directory /foo/bar no longer exists; opened in home]").

### Reconstruction

After successful deserialization and validation:

1. **Build the model.** Instantiate the in-memory workspace/space/tab/pane model objects from the decoded state. Reuse the persisted UUIDs so that any future save produces stable identifiers.
2. **Spawn shells.** For each PaneNode leaf, spawn a new PTY + shell session in the resolved working directory. Shell spawning should happen concurrently (not sequentially) using a `TaskGroup` to meet the under-1-second restore target. Limit concurrency to a reasonable cap (e.g., 8 concurrent spawns) to avoid overwhelming the system.
3. **Restore focus.** Set the active workspace, space, tab, and pane according to the persisted active IDs.
4. **Restore window geometry.** For each workspace, apply the saved `windowFrame` (x, y, width, height). Validate that the frame overlaps at least one connected display by checking intersection with `NSScreen.screens`. If the frame is entirely offscreen, fall back to system default placement. If `isFullscreen` is true, enter full-screen mode after positioning.
5. **Show the window.** Present the fully reconstructed UI. The window should appear with the correct layout immediately; shells will begin producing output as they start up.

### Error Handling

| Failure Mode | Behavior |
|-------------|----------|
| `state.json` does not exist | Launch with default state. No error shown. |
| `state.json` cannot be read (permission error) | Log error. Launch with default state. Show a one-time alert: "Could not read saved session state." |
| JSON parse fails (corrupted file) | Log error. Attempt to read `state.prev.json` as fallback. If that also fails, launch with default state. |
| Schema version is from the future (downgrade) | Log warning. Launch with default state. |
| Validation fails (structural invariant violation) | Log the specific violation. Attempt to read `state.prev.json`. If that also fails, launch with default state. |
| A saved working directory does not exist | Replace with `$HOME` for that pane. Log the mismatch. Show transient notice in the affected pane. |
| Shell spawn fails for a pane | Show error in that specific pane (per FR-25 pattern). Other panes are unaffected. |
| `state.prev.json` fallback also fails | Launch with default state. Log that both files were unusable. |

---

## 5. Restore Correctness Instrumentation

### What to Measure

At launch, after the restore flow completes, compute:

- **Total panes saved:** Count of PaneNode leaf nodes in the loaded state file.
- **Total panes restored:** Count of panes that were successfully reconstructed with a live shell.
- **Layout matches:** For each pane, whether its position in the split tree (parent split direction, ratio, sibling) matches what was saved. Since the app reconstructs from the same tree, this should always match unless fallback occurred.
- **Working directory matches:** For each pane, whether the resolved working directory equals the saved working directory. A mismatch occurs when a directory was missing and fell back to `$HOME`.
- **Active-element matches:** Whether the active workspace, space, tab, and pane all resolved correctly.

### Correctness Percentage Calculation

```
correctness = (matching_panes / total_saved_panes) * 100
```

A pane "matches" if all of the following are true:
1. It exists in the restored hierarchy at the same position (same workspace, space, tab, same split tree path).
2. Its working directory matches the saved value (not replaced by fallback).
3. Its shell spawned successfully.

### Logging

On every launch with restored state, emit a structured log entry via `os_log` at info level:

- restore_correctness_pct: the percentage (0-100)
- total_panes_saved: integer
- total_panes_restored: integer
- working_directory_mismatches: integer (count)
- working_directory_mismatch_details: array of {paneId, savedPath, resolvedPath}
- active_element_mismatches: array of strings describing which active IDs did not resolve
- restore_duration_ms: time from start of deserialization to window-visible
- schema_version: the version found in the state file
- migration_applied: boolean (whether a migration was run)

This data is logged locally only (no external telemetry per PRD non-goal NG2). It can be viewed via Console.app by filtering on the aterm subsystem.

### Debug Overlay

Expose restore metrics in a debug overlay (toggled via a keyboard shortcut or menu item, likely added in M7). The overlay should display the last restore's correctness percentage, mismatch details, and restore duration.

---

## 6. Component Architecture

### Feature Directory Structure

Since no code exists yet, this spec proposes the following structure for persistence-related code, to be placed alongside whatever directory layout M1-M4 establish. The naming follows Swift/SwiftUI conventions.

```
aterm/
  Persistence/
    SessionState.swift          -- Codable model types (SessionState, WorkspaceState, SpaceState, TabState, PaneNode, WindowFrame)
    SessionStateMigrator.swift  -- Version detection and migration chain
    SessionSerializer.swift     -- Encode + atomic write logic
    SessionRestorer.swift       -- Read + decode + validate + reconstruct logic
    RestoreMetrics.swift        -- Correctness instrumentation and logging
    ProcessDetector.swift       -- Foreground process detection via tcgetpgrp/proc_pidinfo
  App/
    AppDelegate.swift           -- applicationShouldTerminate hook (quit flow orchestration)
  UI/
    QuitConfirmationDialog.swift -- SwiftUI view for the foreground-process confirmation dialog
```

### Key Types

#### SessionState (top-level Codable model)

Maps 1:1 to the JSON schema in Section 2. All fields are `Codable`. The pane tree uses the `PaneNode` enum with cases `.split(direction:, ratio:, first:, second:)` and `.leaf(paneID:, workingDirectory:)`, encoded with a `type` discriminator field. The binary tree structure (first/second fields, not children array) enables zero-translation Codable conformance.

#### SessionSerializer

Responsibilities:
- Accept the live workspace model and produce a `SessionState` snapshot.
- Encode to JSON with pretty printing and sorted keys.
- Perform atomic file write with backup rotation.
- Report errors without throwing (quit must not be blocked).

#### SessionRestorer

Responsibilities:
- Read and decode `state.json`, with fallback to `state.prev.json`.
- Run schema migrations if needed.
- Validate structural invariants.
- Resolve working directories (check existence, substitute `$HOME`).
- Return either a valid `SessionState` or nil (indicating default state should be used).
- Produce `RestoreMetrics` as a side effect.

#### ProcessDetector

Responsibilities:
- Accept a list of PTY master file descriptors and their associated shell PIDs.
- For each, determine if a foreground process other than the shell is running.
- Return a list of (pane identifier, process name) for panes with active foreground processes.
- Must be callable off the main thread.

#### RestoreMetrics

A struct capturing all the instrumentation data described in Section 5. Has a method to emit the data as a structured `os_log` entry.

---

## 7. Dependencies on M1-M4

| Milestone | What M5 Needs From It |
|-----------|----------------------|
| M1 (Terminal Fundamentals) | PTY session model with master FD and shell PID exposed. Shell spawn API that accepts a working directory parameter. The ability to display a message in a pane (for "directory not found" notices and shell exit messages). |
| M2 (Pane Splitting) | PaneNode data model (recursive enum with `.leaf` and `.split` cases) that can be walked to produce the persisted tree representation. The ability to reconstruct a PaneNode tree from a serialized representation. Zero-translation Codable conformance is expected since the JSON schema mirrors the runtime model directly. |
| M3 (Tabs and Spaces) | Tab and Space model objects with stable IDs, names, and ordered children. Active-tab and active-space tracking. |
| M4 (Workspaces) | Workspace model objects with stable IDs, names, ordered spaces, and default working directory. Active-workspace tracking. Workspace switcher and window management. |

M5 should define a protocol or interface that each milestone's model must conform to for serialization. Specifically:

- Each model (Workspace, Space, Tab, Pane) must expose a stable UUID that persists for the lifetime of the object.
- The pane split tree must be representable as a binary tree of splits with direction and ratio.
- Each pane must expose its current working directory (queried from the PTY at save time, not maintained as mutable state).

---

## 8. Navigation and UI Changes

### New UI Elements

| Element | Description |
|---------|-------------|
| Quit confirmation dialog | Modal alert presented when the user quits with running foreground processes. Implemented as a SwiftUI `.alert` modifier on the main window or as a standalone sheet. |
| Pane transient notice | An inline message displayed at the top of a pane when its saved working directory was not found. Auto-dismisses after 5 seconds or on any keypress. Uses the same visual style as the shell-exit-code message from FR-25. |

### No New Routes or Navigation

M5 does not introduce new screens or navigation paths. The quit dialog is a modal interruption, not a navigable screen.

---

## 9. Performance Considerations

### Fast Restore Target (Under 1 Second)

The PRD requires the app to be interactive within 1 second of cold launch with restored state. Budget allocation:

| Phase | Budget |
|-------|--------|
| Read and parse state.json | 50ms |
| Migration (if needed) | 50ms |
| Validation and directory checks | 100ms |
| Model reconstruction | 50ms |
| Shell spawning (concurrent) | 500ms |
| UI layout and first frame | 250ms |
| **Total** | **1000ms** |

Key optimizations:

- **Concurrent shell spawning.** Use Swift structured concurrency (`TaskGroup`) to spawn all shells in parallel rather than sequentially. With 8-way concurrency, even 20+ panes should spawn within 500ms.
- **Minimal JSON size.** The state file only stores hierarchy and working directories -- no scrollback, no command history. Even a large workspace (10 workspaces, 5 spaces each, 3 tabs each, 4 panes each = 600 panes) produces a JSON file well under 1MB.
- **No blocking on shell readiness.** The UI appears immediately with pane frames. Shell output streams in asynchronously as each PTY session starts.
- **Directory existence checks in parallel.** Use a concurrent map over pane working directories for `FileManager.fileExists` calls, which can be slow on network-mounted filesystems.

### State File Size Estimation

For a moderate setup (5 workspaces, 3 spaces each, 2 tabs each, 3 panes each = 90 panes): approximately 30-50KB of JSON. For the extreme case above (600 panes): approximately 200-300KB. Both are trivially fast to read and parse.

---

## 10. Permissions and Security

### File System Access

The app writes to `~/Library/Application Support/aterm/`, which is accessible by the app's sandbox (if sandboxed) or freely for non-sandboxed apps. Since this is a developer tool not targeting the App Store (NG6), sandboxing is not required, and no entitlements are needed for this directory.

### Information Stored

The state file contains:
- Workspace and space names (user-chosen strings).
- Working directory absolute paths (may reveal project names and directory structure).
- No credentials, no command history, no environment variables, no scrollback content.

This is acceptable for a personal tool. The file permissions should be set to `0600` (owner read/write only) to prevent other users on the machine from reading workspace paths.

### Process Detection

Reading foreground process group (`tcgetpgrp`) and process info (`proc_pidinfo`, `proc_pidpath`) operates on the app's own child processes, so no special entitlements are needed.

---

## 11. Migration and Deployment

### Schema Migration Framework

The `SessionStateMigrator` maintains an ordered list of migration functions:

| From Version | To Version | Migration Description |
|-------------|-----------|----------------------|
| (none yet)  | (none yet) | v1 is the initial schema. No migrations needed at launch. |

Each migration function takes a JSON dictionary (`[String: Any]`) and returns a transformed dictionary. Migrations are composed: migrating from v1 to v3 runs v1-to-v2 then v2-to-v3.

When adding a new schema version in the future:
1. Increment the version constant in code.
2. Add a migration function from the previous version.
3. The migration chain handles users who skip multiple versions.

### Rollback Plan

If M5 introduces a bug in the quit flow:
- The state file format is additive; older builds can ignore unknown fields.
- The `state.prev.json` backup provides a one-save-ago fallback.
- If both files are corrupted, the app degrades gracefully to default state rather than crashing.
- The persistence feature can be disabled entirely via a feature flag (see below).

### Feature Flag

Introduce a `persistenceEnabled` flag (default: true, overridable via a launch argument `--no-persistence` or an environment variable `ATERM_NO_PERSISTENCE=1`). When disabled:
- Quit skips serialization (but still shows the foreground-process dialog).
- Launch always starts with default state.

This allows isolating persistence bugs during development and testing.

---

## 12. Implementation Phases

### Phase 1: State Model and Serialization (Core)

- Define the `SessionState` Codable model hierarchy (all types from Section 2).
- Implement `SessionSerializer`: snapshot capture from live model, JSON encoding, atomic file write with backup.
- Implement `SessionStateMigrator` with the version-checking framework (no actual migrations yet).
- Write unit tests: encode a sample hierarchy, decode it, verify round-trip fidelity.
- Deliverable: The state file can be written to disk. Can be tested independently of the quit flow.

### Phase 2: Restore Pipeline

- Implement `SessionRestorer`: file reading, version check, decoding, validation, working directory resolution.
- Implement fallback to `state.prev.json`.
- Implement fallback to default state on any unrecoverable error.
- Integrate with app launch: if state file exists, restore the hierarchy, spawn shells, and apply window geometry (with offscreen detection fallback).
- Write unit tests: restore from valid file, restore from corrupted file, restore with missing directories, restore from older schema version, restore with offscreen window frame.
- Deliverable: App can round-trip (save on quit, restore on launch). Layout, working directories, window positions, and full-screen state are correct.

### Phase 3: Quit Flow and Process Detection

- Implement `ProcessDetector`: foreground process detection via `tcgetpgrp` and `proc_pidinfo`.
- Implement `QuitConfirmationDialog`: SwiftUI alert with process list.
- Integrate with `applicationShouldTerminate`: pause termination, detect processes, show dialog if needed, serialize, send SIGHUP, complete termination.
- Write integration tests: mock PTY sessions with and without foreground processes, verify dialog behavior.
- Deliverable: Full quit flow works end-to-end.

### Phase 4: Instrumentation

- Implement `RestoreMetrics`: capture correctness data during restore.
- Add `os_log` emission at the end of the restore flow.
- Add timing instrumentation (restore duration measurement).
- Verify metrics by intentionally introducing mismatches (delete a saved directory, corrupt the state file) and checking log output.
- Deliverable: Every launch with restored state produces a correctness log entry.

---

## 13. Technical Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Working directory detection via `proc_pidinfo` is inaccurate (e.g., shell changed directory after last update) | Panes restore in wrong directory; correctness drops below 100% | Low (macOS kernel tracks cwd per process accurately) | Query cwd at save time, not cached. Test with rapid `cd` before quit. |
| Foreground process detection fails for some process types (e.g., background jobs that take the foreground) | User quits without warning, loses work | Low | Use `tcgetpgrp` which is the POSIX standard mechanism. Test with common developer tools (vim, ssh, docker). |
| State file corruption due to crash during write | State lost, user starts with default on next launch | Low (atomic write via rename prevents partial writes) | Backup file (`state.prev.json`) provides one-generation fallback. |
| Shell spawn concurrency causes resource exhaustion with many panes | Restore hangs or fails | Low | Cap concurrent spawns (e.g., 8). Test with 50+ panes. |
| Restore takes over 1 second for large workspaces | Fails performance target | Medium | Profile with realistic workspace sizes. If shell spawning dominates, show UI immediately and let shells connect asynchronously. |
| Schema migration breaks for users who skip multiple versions | State lost on upgrade | Low (single developer, sequential updates) | Migration chain composes; test skipping versions in unit tests. |
| File permissions on `~/Library/Application Support/aterm/` prevent writes | Serialization fails silently; state not saved | Very low | Check and create directory with correct permissions at app start. Log errors clearly. |

---

## 14. Open Technical Questions

| # | Question | Context | Impact if Unresolved |
|---|----------|---------|---------------------|
| 1 | Should the pane split tree support N-way splits or strictly binary splits? | **Resolved:** The PaneNode enum uses strictly binary splits (each split has exactly `first` and `second` children). N-way layouts are composed from nested binary splits. The JSON schema uses `"first"` and `"second"` fields (not a `"children"` array) to mirror this. | Resolved. |
| 2 | How does M4's "multiple windows" (FR-36, one workspace per window) affect persistence? | **Resolved:** The Workspace object now includes `windowFrame` (x, y, width, height) and `isFullscreen` fields. On restore, offscreen frames (e.g., external monitor removed) fall back to system default placement. | Resolved. |
| 3 | Should `state.prev.json` be a single backup or a rotating set (e.g., last 3)? | Single backup is simpler but provides only one generation of fallback. | Minimal impact -- single backup covers the common case (latest write corrupted). Multiple backups are over-engineering for v1. **Recommendation:** Single backup. |
| 4 | Should the app auto-save state periodically (e.g., every 5 minutes) in addition to on quit? | A crash would lose all state if we only save on quit. | State loss on crash. **Recommendation:** Add periodic auto-save as a fast-follow after the quit-save flow is proven stable. Not in initial M5 scope per the PRD, but strongly recommended. |
| 5 | What is the exact protocol or interface M1-M4 models should conform to for serialization? | M5 needs to walk the workspace hierarchy and extract state. The interface depends on M1-M4's model design. | Tight coupling between M5 and M1-M4 models. **Recommendation:** Define a `Persistable` protocol with a `toPersistedState()` method that each model type implements, keeping serialization logic in M5's domain. |
