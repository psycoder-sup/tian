# Auto Claude Session Restore via Wrapper

**Date:** 2026-04-09
**Status:** Approved

## Problem

When a user runs Claude Code in an aterm pane, closes the window, and reopens it, the Claude session is not resumed. aterm already has the infrastructure for session restore (`restoreCommand` on `PaneLeafState`, `pane.set-restore-command` IPC), but nothing registers the restore command automatically. Requiring users to manually configure Claude Code hooks is friction that prevents adoption.

## Solution

Bundle a `claude` wrapper script and a settings JSON file in the aterm app bundle. The wrapper transparently injects `--settings` when running inside aterm, which installs a `SessionStart` hook that registers the restore command via IPC. Zero user configuration required.

## Components

### 1. `claude` wrapper script

**Location:** `aterm.app/Contents/MacOS/claude`
**Source:** `aterm/Resources/claude` (shell script)

```bash
#!/bin/bash
SELF_DIR="$(dirname "$0")"
REAL_CLAUDE=$(PATH="${PATH//$SELF_DIR:}" command -v claude)

if [ -z "$REAL_CLAUDE" ]; then
  echo "claude: command not found" >&2
  exit 127
fi

if [ -n "$ATERM_SOCKET" ]; then
  exec "$REAL_CLAUDE" --settings "$SELF_DIR/../Resources/aterm-claude-settings.json" "$@"
else
  exec "$REAL_CLAUDE" "$@"
fi
```

Behavior:
- Strips its own directory from `$PATH` to find the real `claude` binary (parameter expansion + builtin, no subprocesses)
- If `$ATERM_SOCKET` is set (running inside aterm): injects `--settings` pointing to the bundled settings JSON
- If not inside aterm: passes through transparently
- If `claude` is not installed: prints error, exits 127

### 2. Settings JSON

**Location:** `aterm.app/Contents/Resources/aterm-claude-settings.json`
**Source:** `aterm/Resources/aterm-claude-settings.json`

```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "aterm pane set-restore-command --command 'claude --resume $SESSION_ID'"
      }
    ]
  }
}
```

The hook fires when Claude Code starts a session and registers the restore command with aterm via the existing `pane.set-restore-command` IPC handler. The `$SESSION_ID` environment variable is provided by Claude Code's hook system.

### 3. Build integration

**File:** `project.yml`

Add post-compile scripts to copy both files into the app bundle:
- Copy `aterm/Resources/claude` to `Contents/MacOS/claude` (executable)
- Copy `aterm/Resources/aterm-claude-settings.json` to `Contents/Resources/aterm-claude-settings.json`

## Session Restore Flow

```
User types "claude" in aterm pane
  -> shell finds wrapper (MacOS/ is on PATH)
  -> wrapper finds real claude, execs with --settings
    -> Claude Code starts, fires SessionStart hook
      -> hook calls: aterm pane set-restore-command --command "claude --resume <session-id>"
        -> PaneViewModel stores restoreCommand for this pane
          -> SessionSerializer persists to state.json on app quit

User quits & reopens aterm
  -> SessionRestorer loads state.json
    -> PaneViewModel.fromState reads restoreCommand
      -> surfaceView.initialInput = "claude --resume <session-id>\n"
        -> ghostty types it into the shell
          -> Claude session resumes
```

## Files to Add/Modify

| File | Action | Purpose |
|------|--------|---------|
| `aterm/Resources/claude` | Add | Wrapper shell script |
| `aterm/Resources/aterm-claude-settings.json` | Add | Claude Code settings with SessionStart hook |
| `project.yml` | Modify | Add post-compile scripts to bundle both files |

## Non-Goals

- Handling `--settings` conflicts (if user passes their own `--settings`)
- Modifying user's `~/.claude/settings.json`
- Process-level Claude detection
- Supporting non-bash shells for the wrapper (bash is available on all macOS)

## Dependencies

Relies on existing aterm infrastructure:
- `pane.set-restore-command` IPC handler (`IPCCommandHandler.swift`)
- `restoreCommand` on `PaneLeafState` (`SessionState.swift`)
- `initialInput` on `TerminalSurfaceView` (`TerminalSurfaceView.swift`)
- `PaneViewModel.fromState` wiring (`PaneViewModel.swift`)
- `EnvironmentBuilder` PATH prepend (`EnvironmentBuilder.swift`)
- Claude Code `--settings` flag and `SessionStart` hook system
