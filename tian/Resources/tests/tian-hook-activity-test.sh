#!/bin/bash
# Standalone test for tian-hook-activity.sh — no Xcode/Swift build required.
#
# Verifies the `begin`, `end`, `reconcile`, and `reset-lifecycle` actions
# extract the right fields from a Claude Code hook payload and forward them
# to the bundled `tian` CLI, and that unrecognized input degrades gracefully
# (no CLI call, exit 0) rather than blocking Claude.
#
# This exploits the hook's existing injection seam: it invokes
#   "$TIAN_CLI_PATH" activity <subcommand> ...
# so this test points TIAN_CLI_PATH at a stub script that records its args,
# feeds a JSON payload to the real hook on stdin, and asserts what the stub
# was (or wasn't) called with.
#
# HOME is redirected to a scratch dir for every invocation so the `begin`/
# `end` raw-payload logging (which writes under
# $HOME/Library/Logs/tian/claude-hooks.log, same as tian-hook-log.sh) never
# touches the real user's log directory.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../tian-hook-activity.sh"

if [ ! -f "$HOOK" ]; then
  echo "FAIL: hook script not found at $HOOK"
  exit 1
fi

command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not installed, cannot exercise tian-hook-activity.sh"
  exit 0
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

CALLS_LOG="$WORKDIR/calls.log"
STUB="$WORKDIR/stub-tian"
FAKE_HOME="$WORKDIR/home"
mkdir -p "$FAKE_HOME"

cat >"$STUB" <<STUBEOF
#!/bin/bash
printf '%s\n' "CALL: \$*" >> "$CALLS_LOG"
STUBEOF
chmod +x "$STUB"

TOTAL=0
FAILS=0
HOOK_EXIT=0

# run_hook <action> [payload]
# Feeds <payload> (if any) to the hook via stdin, with TIAN_CLI_PATH pointed
# at the stub and HOME redirected to a scratch dir, resetting the call log
# first. Sets $HOOK_EXIT to the hook's exit code.
run_hook() {
  local action="$1" payload="${2:-}"
  : >"$CALLS_LOG"
  if [ -n "$payload" ]; then
    printf '%s' "$payload" | HOME="$FAKE_HOME" TIAN_CLI_PATH="$STUB" bash "$HOOK" "$action" >/dev/null 2>&1
  else
    HOME="$FAKE_HOME" TIAN_CLI_PATH="$STUB" bash "$HOOK" "$action" </dev/null >/dev/null 2>&1
  fi
  HOOK_EXIT=$?
}

assert_call() {
  local name="$1" action="$2" payload="$3" expected="$4"
  TOTAL=$((TOTAL + 1))
  run_hook "$action" "$payload"
  if [ "$HOOK_EXIT" -ne 0 ]; then
    echo "FAIL: $name — hook exited $HOOK_EXIT (expected 0)"
    FAILS=$((FAILS + 1))
  elif ! grep -qF -- "$expected" "$CALLS_LOG"; then
    echo "FAIL: $name — expected call containing: $expected"
    echo "  actual:"
    sed 's/^/    /' "$CALLS_LOG"
    FAILS=$((FAILS + 1))
  else
    echo "PASS: $name"
  fi
}

assert_no_call() {
  local name="$1" action="$2" payload="${3:-}"
  TOTAL=$((TOTAL + 1))
  run_hook "$action" "$payload"
  if [ "$HOOK_EXIT" -ne 0 ]; then
    echo "FAIL: $name — hook exited $HOOK_EXIT (expected 0)"
    FAILS=$((FAILS + 1))
  elif [ -s "$CALLS_LOG" ]; then
    echo "FAIL: $name — expected no CLI call, but stub was called:"
    sed 's/^/    /' "$CALLS_LOG"
    FAILS=$((FAILS + 1))
  else
    echo "PASS: $name — correctly no-op'd"
  fi
}

echo "--- begin ---"

assert_call "begin: SubagentStart-shaped payload" begin \
  '{"agent_id":"a1","agent_type":"Explore","session_id":"s"}' \
  "CALL: activity begin --id a1 --kind agent --label Explore"

assert_call "begin: teammate-shaped payload" begin \
  '{"teammate_id":"t1","teammate_name":"reviewer"}' \
  "CALL: activity begin --id t1 --kind teammate --label reviewer"

assert_no_call "begin: no id extractable" begin \
  '{"foo":"bar"}'

echo ""
echo "--- end ---"

assert_call "end: agent_id present" end \
  '{"agent_id":"a1"}' \
  "CALL: activity end --id a1"

assert_call "end: only teammate_name present" end \
  '{"teammate_name":"reviewer"}' \
  "CALL: activity end --label reviewer"

echo ""
echo "--- reconcile ---"

assert_call "reconcile: background_tasks present" reconcile \
  '{"background_tasks":[{"task_id":"b1"}]}' \
  'CALL: activity reconcile --json [{"task_id":"b1"}]'

assert_call "reconcile: no background_tasks key" reconcile \
  '{"foo":"bar"}' \
  "CALL: activity reconcile --json []"

echo ""
echo "--- reset-lifecycle ---"

assert_call "reset-lifecycle: no stdin needed" reset-lifecycle "" \
  "CALL: activity reset-lifecycle"

echo ""
echo "--- clear ---"

assert_call "clear: unconditional teardown uses its own op, not sync" clear "" \
  "CALL: activity clear"

echo ""
echo "--- raw payload logging ---"

TOTAL=$((TOTAL + 1))
: >"$CALLS_LOG"
LOG_FILE="$FAKE_HOME/Library/Logs/tian/claude-hooks.log"
rm -f "$LOG_FILE"
printf '%s' '{"agent_id":"a1","agent_type":"Explore","session_id":"s"}' \
  | HOME="$FAKE_HOME" TIAN_CLI_PATH="$STUB" bash "$HOOK" begin >/dev/null 2>&1
HOOK_EXIT=$?
if [ "$HOOK_EXIT" -ne 0 ]; then
  echo "FAIL: begin logs raw payload — hook exited $HOOK_EXIT (expected 0)"
  FAILS=$((FAILS + 1))
elif [ ! -f "$LOG_FILE" ]; then
  echo "FAIL: begin logs raw payload — $LOG_FILE was not created"
  FAILS=$((FAILS + 1))
elif ! grep -q "activity.begin" "$LOG_FILE"; then
  echo "FAIL: begin logs raw payload — no activity.begin line in $LOG_FILE"
  sed 's/^/    /' "$LOG_FILE"
  FAILS=$((FAILS + 1))
elif ! grep -q 'payload=.*agent_id' "$LOG_FILE"; then
  echo "FAIL: begin logs raw payload — no payload= field with raw payload in $LOG_FILE"
  sed 's/^/    /' "$LOG_FILE"
  FAILS=$((FAILS + 1))
else
  echo "PASS: begin logs raw payload — delegates to tian-hook-log.sh's claude-hooks.log"
fi

echo ""
echo "--- graceful degradation ---"

assert_no_call "unknown action + empty stdin: no call, exit 0" bogus-action ""

echo ""
echo "===================="
if [ "$FAILS" -eq 0 ]; then
  echo "PASS: all $TOTAL cases passed"
  exit 0
else
  echo "FAIL: $FAILS/$TOTAL cases failed"
  exit 1
fi
