#!/bin/bash
# tian Claude Code hook logger.
#
# Usage: tian-hook-log.sh <EVENT_LABEL> [STATE]
#
# Reads the Claude Code hook JSON payload from stdin, appends a diagnostic
# line to ~/Library/Logs/tian/claude-hooks.log, and (if STATE is given and
# TIAN_CLI_PATH is set) forwards the state via `tian-cli status set`.
#
# Rotates the log file when it exceeds 5MB (matches tian's FileLogWriter).
# Always exits 0 so hook behavior is never blocked by logging failures.

set +e

LOG_DIR="${HOME}/Library/Logs/tian"
LOG_FILE="${LOG_DIR}/claude-hooks.log"
LOG_BACKUP="${LOG_DIR}/claude-hooks.1.log"
LOG_MAX_BYTES=$((5 * 1024 * 1024))

EVENT="${1:-unknown}"
STATE="${2:-}"

mkdir -p "$LOG_DIR" 2>/dev/null

# Rotate if too large.
if [ -f "$LOG_FILE" ]; then
  SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$SIZE" -gt "$LOG_MAX_BYTES" ]; then
    mv -f "$LOG_FILE" "$LOG_BACKUP" 2>/dev/null
  fi
fi

INPUT=$(cat 2>/dev/null)

jqr() {
  # jq with fallback to empty string if jq isn't installed or input is empty.
  if command -v jq >/dev/null 2>&1 && [ -n "$INPUT" ]; then
    printf '%s' "$INPUT" | jq -r "$1 // \"\"" 2>/dev/null
  fi
}

TOOL=$(jqr '.tool_name')
PMODE=$(jqr '.permission_mode')
NTYPE=$(jqr '.notification_type')
MSG=$(jqr '.message' | tr '\n\r' '  ' | cut -c1-120)

TS=$(date '+%Y-%m-%d %H:%M:%S')

{
  printf '%s [%s]' "$TS" "$EVENT"
  [ -n "$TOOL"  ] && printf ' tool=%s'  "$TOOL"
  [ -n "$PMODE" ] && printf ' pmode=%s' "$PMODE"
  [ -n "$NTYPE" ] && printf ' ntype=%s' "$NTYPE"
  [ -n "$MSG"   ] && printf ' msg="%s"' "$MSG"
  printf ' cli=%s'  "${TIAN_CLI_PATH:+SET}${TIAN_CLI_PATH:-UNSET}"
  printf ' sock=%s' "${TIAN_SOCKET:+SET}${TIAN_SOCKET:-UNSET}"
  printf ' pane=%s' "${TIAN_PANE_ID:-UNSET}"
  printf '\n'

  if [ -n "$STATE" ]; then
    if [ -n "$TIAN_CLI_PATH" ]; then
      OUT=$("$TIAN_CLI_PATH" status set --state "$STATE" 2>&1)
      RC=$?
      printf '  -> status set --state %s rc=%s' "$STATE" "$RC"
      [ -n "$OUT" ] && printf ' out=%q' "$OUT"
      printf ' done=%s\n' "$(date '+%H:%M:%S')"
    else
      printf '  -> status set skipped (TIAN_CLI_PATH unset)\n'
    fi
  fi
} >> "$LOG_FILE" 2>&1

exit 0
