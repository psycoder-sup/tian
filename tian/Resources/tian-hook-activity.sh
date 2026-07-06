#!/bin/bash
# tian Claude Code hook — track background work from Claude Code's authoritative
# `background_tasks` snapshot so a session isn't shown idle while work is still
# running in the background.
#
# Usage: tian-hook-activity.sh sync
#
# Reads the Claude Code hook JSON payload from stdin and forwards the whole
# `background_tasks` array to tian as an authoritative whole-set replace:
#   sync : Stop / SubagentStop → activity sync    (authoritative snapshot,
#                                 also garbage-collects stale activities)
#
# No-ops gracefully when jq or the expected field is missing. Always exits 0 so
# a tracking failure never blocks Claude Code.

set +e

ACTION="${1:-}"

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

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
    # Compact snapshot of all running background tasks (bash + agents). Defaults
    # to [] so an empty/absent array still clears any stale activities.
    BT=$(printf '%s' "$INPUT" | jq -c '.background_tasks // []' 2>/dev/null)
    [ -z "$BT" ] && BT="[]"
    run_tian activity sync --json "$BT"
    ;;

  *)
    exit 0
    ;;
esac

exit 0
