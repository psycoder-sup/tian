#!/bin/bash
# tian Claude Code hook — keep a session's background-work badge in sync with
# Claude Code's authoritative `background_tasks` snapshot, so a session isn't
# shown idle while work is still running (nor busy after it's gone).
#
# Usage: tian-hook-activity.sh <sync|clear>
#
#   sync  : Stop / SubagentStop — read the payload's `background_tasks` array from
#           stdin and forward it as an authoritative whole-set replace (also GCs
#           activities that dropped out of the snapshot). These are the ONLY hook
#           events Claude Code populates `background_tasks` on.
#   clear : SessionEnd — the session is over, so unconditionally clear this pane's
#           background activities. That event carries no `background_tasks`, so
#           there is nothing to read; needs neither stdin nor jq.
#
# No-ops gracefully when jq or the expected field is missing. Always exits 0 so
# a tracking failure never blocks Claude Code.

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

case "$ACTION" in
  sync)
    INPUT=$(cat 2>/dev/null)
    [ -z "$INPUT" ] && exit 0
    command -v jq >/dev/null 2>&1 || exit 0
    # Compact snapshot of all running background tasks (bash + agents). Defaults
    # to [] so an empty/absent array still clears any stale activities.
    BT=$(printf '%s' "$INPUT" | jq -c '.background_tasks // []' 2>/dev/null)
    [ -z "$BT" ] && BT="[]"
    run_tian activity sync --json "$BT"
    ;;

  clear)
    # Session ended → its background tasks are gone. Replace with the empty set.
    run_tian activity sync --json "[]"
    ;;

  *)
    exit 0
    ;;
esac

exit 0
