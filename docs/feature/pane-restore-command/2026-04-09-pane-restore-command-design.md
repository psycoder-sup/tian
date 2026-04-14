# Pane Restore Command

Persist an optional restore command per pane so that processes like Claude Code sessions can be automatically resumed when tian restores a saved session.

## Problem

When tian closes and reopens, it restores pane layout and working directories but spawns fresh shells. Interactive sessions (e.g., Claude Code) running in those panes are lost. Users must manually re-launch `claude --resume <session-id>` to pick up where they left off.

## Solution

Allow processes to register a "restore command" on their pane via IPC. When tian restores the session, panes with a restore command use ghostty's `initial_input` to replay the command into the freshly spawned shell, automatically resuming the session.

## Design

### Data Model

**Persistence** (`SessionState.swift`):

Add an optional `restoreCommand` field to `PaneLeafState`:

```swift
struct PaneLeafState: Codable, Sendable, Equatable {
    let paneID: UUID
    let workingDirectory: String
    let restoreCommand: String?  // e.g. "claude --resume abc123"
}
```

The field is optional, so existing `state.json` files (without this field) decode correctly with `restoreCommand` as `nil`. No version bump or migration needed.

**Runtime** (`PaneViewModel`):

Add a `restoreCommands: [UUID: String]` dictionary to `PaneViewModel`. Populated from:
- IPC when a process registers its restore command
- Persisted state during session restore

### IPC Command

**Command:** `pane.set-restore-command`

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `command` | string | yes | Full command to replay on restore |

Pane ID is resolved from `TIAN_PANE_ID` in the IPC env, consistent with other pane commands.

No `pane.clear-restore-command` is needed. The restore command is only meaningful during session restore. If no hook re-registers it in a subsequent session, it simply won't be serialized.

**Handler** (`IPCCommandHandler.swift`):

Resolves the pane via env, stores the command string in `PaneViewModel.restoreCommands[paneID]`.

### Hook Integration (User Side)

Claude Code's SessionStart hook registers the restore command:

```json
{
  "hooks": {
    "SessionStart": [{
      "command": "tian pane set-restore-command --command=\"claude --resume $CLAUDE_SESSION_ID\""
    }]
  }
}
```

This fires every time a Claude session starts in any tian pane.

### Restore Flow

1. `SessionRestorer` reads `PaneLeafState.restoreCommand` during `buildWorkspaceCollection()`
2. `PaneViewModel.fromState()` populates `restoreCommands[paneID]` from the persisted state
3. `GhosttyTerminalSurface.createSurface()` receives a new `initialInput: String?` parameter
4. When `initialInput` is non-nil, sets `config.initial_input` to the command string (with trailing `\n`) via `withCString`, matching the existing `working_directory` pattern for C string lifetime safety
5. Ghostty spawns the default shell, then sends the initial input as if the user typed it

**Fallback:** If the restore command fails (session expired, `claude` not installed, etc.), the error prints in the shell and the user is left at a working prompt. No special error handling in tian.

### Serialization Flow

1. `SessionSerializer.snapshot()` walks the pane tree as today
2. For each leaf, checks `PaneViewModel.restoreCommands[paneID]`
3. If present, includes `restoreCommand` in the serialized `PaneLeafState`
4. If absent, `restoreCommand` is `nil` in the JSON output

### File Changes

| File | Change |
|------|--------|
| `Persistence/SessionState.swift` | Add `restoreCommand: String?` to `PaneLeafState` |
| `Pane/PaneViewModel.swift` | Add `restoreCommands: [UUID: String]`; populate from state on restore; expose for serialization |
| `Core/IPCCommandHandler.swift` | Add `pane.set-restore-command` handler |
| `Core/GhosttyTerminalSurface.swift` | Add `initialInput: String?` param to `createSurface()`; set `config.initial_input` |
| `Persistence/SessionSerializer.swift` | Include `restoreCommands[paneID]` when snapshotting leaf state |
| `Persistence/SessionRestorer.swift` | Pass `restoreCommand` through to `PaneViewModel.fromState()` |

No new files. No UI changes. No version bump.

### Out of Scope

- The Claude Code hook configuration lives in `~/.claude/settings.json`, not in tian's codebase
- Restore commands for other tools (tmux, ssh, etc.) — this design supports them generically but they are not targeted
- Visual indicator showing a pane is "resuming" vs. a fresh shell
