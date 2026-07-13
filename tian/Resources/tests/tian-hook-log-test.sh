#!/bin/bash
# Standalone test for tian-hook-log.sh — no Xcode/Swift build required.
#
# Verifies that the hook forwards the payload's `.agent_id` as `--agent-id`
# on its `tian status set` call, only when non-empty (never an empty flag
# value), and that it still degrades gracefully (no STATE -> no call, no jq
# -> no --agent-id, raw-payload logging never triggers a status change).
#
# This exploits the hook's existing injection seam: it invokes
#   "$TIAN_CLI_PATH" status set --state <state> [--agent-id <id>]
# so this test points TIAN_CLI_PATH at a stub script that records its args,
# feeds a JSON payload to the real hook on stdin, and asserts what the stub
# was (or wasn't) called with.
#
# HOME is redirected to a scratch dir for every invocation so
# claude-hooks.log never touches the real user's log directory.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../tian-hook-log.sh"

if [ ! -f "$HOOK" ]; then
  echo "FAIL: hook script not found at $HOOK"
  exit 1
fi

command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not installed, cannot exercise tian-hook-log.sh"
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

# A minimal PATH containing only the external commands tian-hook-log.sh
# needs, with jq deliberately excluded, to exercise the "jq unavailable"
# degradation path without depending on the ambient system PATH.
NOJQ_DIR="$WORKDIR/nojq-bin"
mkdir -p "$NOJQ_DIR"
for cmd in bash mkdir stat date cat mv tr cut; do
  bin=$(command -v "$cmd" 2>/dev/null)
  [ -n "$bin" ] && ln -sf "$bin" "$NOJQ_DIR/$cmd"
done

TOTAL=0
FAILS=0
HOOK_EXIT=0

# run_hook <event> <state> <payload> [extra_env...]
# Feeds <payload> to the hook via stdin with args "<event> <state>" (state
# omitted if empty), TIAN_CLI_PATH pointed at the stub, and HOME redirected
# to a scratch dir, resetting the call log first. Sets $HOOK_EXIT.
run_hook() {
  local event="$1" state="$2" payload="$3"
  shift 3
  : >"$CALLS_LOG"
  if [ -n "$state" ]; then
    printf '%s' "$payload" \
      | env "$@" HOME="$FAKE_HOME" TIAN_CLI_PATH="$STUB" bash "$HOOK" "$event" "$state" >/dev/null 2>&1
  else
    printf '%s' "$payload" \
      | env "$@" HOME="$FAKE_HOME" TIAN_CLI_PATH="$STUB" bash "$HOOK" "$event" >/dev/null 2>&1
  fi
  HOOK_EXIT=$?
}

# assert_call_exact <name> <event> <state> <payload> <expected-call-args> [extra_env...]
# Asserts the stub was called with EXACTLY the given args (not just a
# substring match) — important here since "--state busy" is a substring of
# "--state busy --agent-id x" and we need to distinguish the two.
assert_call_exact() {
  local name="$1" event="$2" state="$3" payload="$4" expected="$5"
  shift 5
  TOTAL=$((TOTAL + 1))
  run_hook "$event" "$state" "$payload" "$@"
  if [ "$HOOK_EXIT" -ne 0 ]; then
    echo "FAIL: $name — hook exited $HOOK_EXIT (expected 0)"
    FAILS=$((FAILS + 1))
  elif ! grep -qFx -- "CALL: $expected" "$CALLS_LOG"; then
    echo "FAIL: $name — expected exact call: $expected"
    echo "  actual:"
    sed 's/^/    /' "$CALLS_LOG"
    FAILS=$((FAILS + 1))
  else
    echo "PASS: $name"
  fi
}

assert_no_call() {
  local name="$1" event="$2" state="$3" payload="${4:-}"
  TOTAL=$((TOTAL + 1))
  run_hook "$event" "$state" "$payload"
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

echo "--- agent_id forwarding ---"

assert_call_exact "non-empty agent_id forwards --agent-id" PostToolUse busy \
  '{"tool_name":"Read","agent_id":"a911931f1e21d0c73","agent_type":"Explore"}' \
  "status set --state busy --agent-id a911931f1e21d0c73"

assert_call_exact "empty agent_id omits --agent-id entirely" PostToolUse busy \
  '{"tool_name":"Read","agent_id":"","agent_type":""}' \
  "status set --state busy"

assert_call_exact "absent agent_id key omits --agent-id entirely" PostToolUse busy \
  '{"tool_name":"Read"}' \
  "status set --state busy"

echo ""
echo "--- no STATE arg -> no call ---"

assert_no_call "no STATE, agent_id present" PreToolUse "" \
  '{"tool_name":"Read","agent_id":"a1"}'

echo ""
echo "--- raw payload path never triggers status set ---"

TOTAL=$((TOTAL + 1))
: >"$CALLS_LOG"
LOG_FILE="$FAKE_HOME/Library/Logs/tian/claude-hooks.log"
rm -f "$LOG_FILE"
printf '%s' '{"agent_id":"a1","agent_type":"Explore"}' \
  | HOME="$FAKE_HOME" TIAN_CLI_PATH="$STUB" TIAN_HOOK_LOG_RAW_PAYLOAD=1 bash "$HOOK" activity.begin >/dev/null 2>&1
HOOK_EXIT=$?
if [ "$HOOK_EXIT" -ne 0 ]; then
  echo "FAIL: raw payload path — hook exited $HOOK_EXIT (expected 0)"
  FAILS=$((FAILS + 1))
elif [ -s "$CALLS_LOG" ]; then
  echo "FAIL: raw payload path — expected no CLI call, but stub was called:"
  sed 's/^/    /' "$CALLS_LOG"
  FAILS=$((FAILS + 1))
elif [ ! -f "$LOG_FILE" ] || ! grep -q 'payload=.*agent_id' "$LOG_FILE"; then
  echo "FAIL: raw payload path — expected payload= field in $LOG_FILE"
  FAILS=$((FAILS + 1))
elif ! grep -q 'agent=a1' "$LOG_FILE"; then
  echo "FAIL: raw payload path — expected agent=a1 field in $LOG_FILE"
  sed 's/^/    /' "$LOG_FILE"
  FAILS=$((FAILS + 1))
else
  echo "PASS: raw payload path — no status set call, agent origin still logged"
fi

echo ""
echo "--- jq unavailable degrades gracefully ---"

TOTAL=$((TOTAL + 1))
: >"$CALLS_LOG"
printf '%s' '{"tool_name":"Read","agent_id":"a1"}' \
  | PATH="$NOJQ_DIR" HOME="$FAKE_HOME" TIAN_CLI_PATH="$STUB" bash "$HOOK" PostToolUse busy >/dev/null 2>&1
HOOK_EXIT=$?
if [ "$HOOK_EXIT" -ne 0 ]; then
  echo "FAIL: jq unavailable — hook exited $HOOK_EXIT (expected 0)"
  FAILS=$((FAILS + 1))
elif ! grep -qFx "CALL: status set --state busy" "$CALLS_LOG"; then
  echo "FAIL: jq unavailable — expected 'status set --state busy' with no --agent-id"
  echo "  actual:"
  sed 's/^/    /' "$CALLS_LOG"
  FAILS=$((FAILS + 1))
else
  echo "PASS: jq unavailable — agent id treated as empty, no --agent-id flag, exit 0"
fi

echo ""
echo "--- log line records origin ---"

TOTAL=$((TOTAL + 1))
: >"$CALLS_LOG"
LOG_FILE="$FAKE_HOME/Library/Logs/tian/claude-hooks.log"
rm -f "$LOG_FILE"
printf '%s' '{"tool_name":"Read","agent_id":"a911931f1e21d0c73"}' \
  | HOME="$FAKE_HOME" TIAN_CLI_PATH="$STUB" bash "$HOOK" PostToolUse busy >/dev/null 2>&1
if ! grep -q 'agent=a911931f1e21d0c73' "$LOG_FILE"; then
  echo "FAIL: log line — expected agent=a911931f1e21d0c73 in $LOG_FILE"
  sed 's/^/    /' "$LOG_FILE"
  FAILS=$((FAILS + 1))
else
  echo "PASS: log line — records subagent origin"
fi

TOTAL=$((TOTAL + 1))
: >"$CALLS_LOG"
rm -f "$LOG_FILE"
printf '%s' '{"tool_name":"Read"}' \
  | HOME="$FAKE_HOME" TIAN_CLI_PATH="$STUB" bash "$HOOK" PostToolUse busy >/dev/null 2>&1
if ! grep -q 'agent=main' "$LOG_FILE"; then
  echo "FAIL: log line — expected agent=main in $LOG_FILE"
  sed 's/^/    /' "$LOG_FILE"
  FAILS=$((FAILS + 1))
else
  echo "PASS: log line — records main-thread origin"
fi

echo ""
echo "===================="
if [ "$FAILS" -eq 0 ]; then
  echo "PASS: all $TOTAL cases passed"
  exit 0
else
  echo "FAIL: $FAILS/$TOTAL cases failed"
  exit 1
fi
