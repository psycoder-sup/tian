#!/bin/bash
# tian Claude Code hook — keep a session's background-work badge in sync with
# Claude Code's lifecycle events (SubagentStart/Stop, TeammateIdle) and its
# authoritative `background_tasks` snapshot, so a session isn't shown idle
# while work is still running (nor busy after it's gone).
#
# Usage: tian-hook-activity.sh <begin|end|sync|reconcile|reset-lifecycle|clear>
#
#   begin           : SubagentStart / TeammateIdle-start-shaped payloads — read
#                      an id/kind/label off stdin and register one live
#                      lifecycle entry (upsert by id).
#   end             : SubagentStop / TeammateIdle — read an id (or, failing
#                      that, a label) off stdin and drop that one lifecycle
#                      entry. No-op if unknown.
#   sync            : SubagentStop — read the payload's `background_tasks`
#                      array from stdin and forward it as a partial reconcile:
#                      replaces snapshot-sourced entries, preserves live
#                      lifecycle entries (registered via `begin`).
#   reconcile       : Stop — like `sync`, but authoritative: the result is
#                      exactly the `background_tasks` snapshot, and every
#                      lifecycle entry is dropped (a turn genuinely ended).
#   reset-lifecycle : UserPromptSubmit / idle Notification — drop lifecycle
#                      entries (subagents/teammates) while keeping
#                      snapshot-sourced entries (a backgrounded bash genuinely
#                      survives across turns). Needs no stdin.
#   clear           : SessionEnd — the one guaranteed teardown event. Calls
#                      the dedicated `tian activity clear` op, which drops
#                      every background activity for the pane unconditionally
#                      (lifecycle *and* snapshot-sourced alike). This must NOT
#                      be a `sync`/`reconcile` with an empty array: `sync` is
#                      now a partial replace that deliberately preserves live
#                      lifecycle entries, and `reconcile` needs a
#                      `background_tasks` payload that SessionEnd doesn't
#                      carry — neither actually clears everything, which is
#                      exactly what a session teardown needs. Needs neither
#                      stdin nor jq.
#
# `begin`/`end` also append the raw (compacted, truncated) stdin payload to
# the same tian hook log that tian-hook-log.sh writes to, so the real
# SubagentStart/TeammateIdle payload shapes can be inspected later if the
# field extraction above turns out to guess wrong. That log file's path,
# size check, and rotation are owned solely by tian-hook-log.sh (this script
# delegates to it) to avoid two hook processes racing the same rotation.
#
# No-ops gracefully when jq or the expected field is missing. Always exits 0
# so a tracking failure never blocks Claude Code.

set +e

ACTION="${1:-}"

# Run the bundled tian CLI. Prefer the hook-provided TIAN_CLI_PATH (as the
# other tian-hook-*.sh helpers do); otherwise fall back to `tian` on PATH
# (matching the inline settings.json hooks). Output is suppressed and failures
# swallowed so activity tracking never blocks Claude Code.
run_tian() {
  if [ -n "$TIAN_CLI_PATH" ]; then
    "$TIAN_CLI_PATH" "$@" >/dev/null 2>&1 || true
  else
    tian "$@" >/dev/null 2>&1 || true
  fi
}

# Locate tian-hook-log.sh, the sole owner of claude-hooks.log's path, size
# check, and `mv -f` rotation. It ships next to this script; fall back to
# PATH so this still resolves if the two are invoked from different cwds.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd 2>/dev/null)"
LOG_SCRIPT="$SCRIPT_DIR/tian-hook-log.sh"
[ -f "$LOG_SCRIPT" ] || LOG_SCRIPT="tian-hook-log.sh"

# Append a compacted, truncated copy of the raw hook payload to tian's
# claude-hooks.log by delegating to tian-hook-log.sh (via
# TIAN_HOOK_LOG_RAW_PAYLOAD=1), so unexpected SubagentStart/TeammateIdle
# payload shapes are still visible even when the field guesses in
# `begin`/`end` miss. No STATE arg is passed, so this can never trigger
# tian-hook-log.sh's `tian status set` side effect.
log_raw_payload() {
  local event="$1" raw="$2"
  local compact
  if command -v jq >/dev/null 2>&1; then
    compact=$(printf '%s' "$raw" | jq -c '.' 2>/dev/null)
  fi
  [ -z "$compact" ] && compact="$raw"
  compact=$(printf '%s' "$compact" | tr '\n\r' '  ' | cut -c1-500)

  printf '%s' "$compact" | TIAN_HOOK_LOG_RAW_PAYLOAD=1 "$LOG_SCRIPT" "$event" >/dev/null 2>&1
}

case "$ACTION" in
  begin)
    INPUT=$(cat 2>/dev/null)
    [ -z "$INPUT" ] && exit 0
    log_raw_payload "activity.begin" "$INPUT"
    command -v jq >/dev/null 2>&1 || exit 0

    ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // .teammate_id // .task_id // empty' 2>/dev/null)
    [ -z "$ID" ] && exit 0

    KIND="agent"
    IS_TEAMMATE=$(printf '%s' "$INPUT" | jq -r 'if (.teammate_id // .teammate_name) then "1" else "" end' 2>/dev/null)
    [ -n "$IS_TEAMMATE" ] && KIND="teammate"

    LABEL=$(printf '%s' "$INPUT" | jq -r --arg id "$ID" '.agent_type // .teammate_name // .description // $id' 2>/dev/null)
    [ -z "$LABEL" ] && LABEL="$ID"

    run_tian activity begin --id "$ID" --kind "$KIND" --label "$LABEL"
    ;;

  end)
    INPUT=$(cat 2>/dev/null)
    [ -z "$INPUT" ] && exit 0
    log_raw_payload "activity.end" "$INPUT"
    command -v jq >/dev/null 2>&1 || exit 0

    ID=$(printf '%s' "$INPUT" | jq -r '.agent_id // .teammate_id // .task_id // empty' 2>/dev/null)
    if [ -n "$ID" ]; then
      run_tian activity end --id "$ID"
      exit 0
    fi

    NAME=$(printf '%s' "$INPUT" | jq -r '.teammate_name // empty' 2>/dev/null)
    if [ -n "$NAME" ]; then
      run_tian activity end --label "$NAME"
      exit 0
    fi

    exit 0
    ;;

  sync)
    INPUT=$(cat 2>/dev/null)
    [ -z "$INPUT" ] && exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    # Compact snapshot of all running background tasks (bash + agents). Defaults
    # to [] so an empty/absent array still clears any stale snapshot activities.
    BT=$(printf '%s' "$INPUT" | jq -c '.background_tasks // []' 2>/dev/null)
    [ -z "$BT" ] && BT="[]"
    run_tian activity sync --json "$BT"
    ;;

  reconcile)
    INPUT=$(cat 2>/dev/null)
    [ -z "$INPUT" ] && exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    # Authoritative turn-end snapshot: result is exactly `background_tasks`;
    # every lifecycle entry (begin'd but never end'd) is dropped too.
    BT=$(printf '%s' "$INPUT" | jq -c '.background_tasks // []' 2>/dev/null)
    [ -z "$BT" ] && BT="[]"
    run_tian activity reconcile --json "$BT"
    ;;

  reset-lifecycle)
    # No stdin needed — just drop lifecycle (subagent/teammate) entries while
    # keeping snapshot-sourced ones (a backgrounded bash survives a new turn).
    run_tian activity reset-lifecycle
    ;;

  clear)
    # Session ended → unconditionally drop every background activity for
    # this pane (lifecycle and snapshot-sourced alike). This must be its own
    # op, not `sync`/`reconcile` with an empty array: since `sync` became a
    # partial replace, `sync --json "[]"` no longer clears lifecycle
    # entries, and `reconcile` needs a `background_tasks` payload SessionEnd
    # doesn't provide. `clear` is the guaranteed teardown op.
    run_tian activity clear
    ;;

  *)
    exit 0
    ;;
esac

exit 0
