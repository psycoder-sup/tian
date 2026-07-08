#!/bin/bash
# Standalone test for tian-hook-prompt.sh — no Xcode/Swift build required.
#
# Verifies that harness-injected synthetic turns (wrapped in a known tag like
# <task-notification>, <system-reminder>, <local-command-stdout>, etc.) are
# filtered out before ever reaching `tian prompt set`, while genuine
# user-typed prompts — including ones that merely contain a stray `<` — are
# still forwarded unchanged.
#
# This exploits the hook's existing injection seam: it invokes
#   "$TIAN_CLI_PATH" prompt set --text "<prompt>"
# so this test points TIAN_CLI_PATH at a stub script that records its args,
# feeds a JSON payload to the real hook on stdin, and asserts whether the
# stub fired.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../tian-hook-prompt.sh"

if [ ! -f "$HOOK" ]; then
  echo "FAIL: hook script not found at $HOOK"
  exit 1
fi

command -v jq >/dev/null 2>&1 || {
  echo "SKIP: jq not installed, cannot exercise tian-hook-prompt.sh"
  exit 0
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

CALLS_LOG="$WORKDIR/calls.log"
STUB="$WORKDIR/stub-tian"

cat >"$STUB" <<STUBEOF
#!/bin/bash
printf '%s\n' "CALL: \$*" >> "$CALLS_LOG"
STUBEOF
chmod +x "$STUB"

TOTAL=0
FAILS=0

# run_hook <prompt-text>
# Feeds {"prompt": "<prompt-text>"} to the hook via stdin with TIAN_CLI_PATH
# pointed at the stub, resetting the call log first.
run_hook() {
  : >"$CALLS_LOG"
  local payload
  payload=$(jq -n --arg p "$1" '{prompt: $p}')
  printf '%s' "$payload" | TIAN_CLI_PATH="$STUB" bash "$HOOK" >/dev/null 2>&1
}

assert_rejected() {
  local name="$1" prompt="$2"
  TOTAL=$((TOTAL + 1))
  run_hook "$prompt"
  if [ -s "$CALLS_LOG" ]; then
    echo "FAIL: $name — expected NOT forwarded, but stub was called"
    FAILS=$((FAILS + 1))
  else
    echo "PASS: $name — correctly rejected (not forwarded)"
  fi
}

assert_forwarded() {
  local name="$1" prompt="$2"
  TOTAL=$((TOTAL + 1))
  run_hook "$prompt"
  if [ ! -s "$CALLS_LOG" ]; then
    echo "FAIL: $name — expected forwarded, but stub was NOT called"
    FAILS=$((FAILS + 1))
  elif ! grep -qF -- "$prompt" "$CALLS_LOG"; then
    echo "FAIL: $name — stub was called, but forwarded text did not match"
    FAILS=$((FAILS + 1))
  else
    echo "PASS: $name — correctly forwarded"
  fi
}

echo "--- harness-injected synthetic turns: must NOT be forwarded ---"

assert_rejected "task-notification wrapper" \
  '<task-notification> <task-id>x</task-id> <tool-use-id>y</tool-use-id></task-notification>'

assert_rejected "system-reminder wrapper" \
  '<system-reminder>foo</system-reminder>'

assert_rejected "local-command-stdout wrapper" \
  '<local-command-stdout>bar</local-command-stdout>'

assert_rejected "command-name wrapper" \
  '<command-name>/clear</command-name>'

assert_rejected "leading-whitespace task-notification" \
"$(printf '\n  <task-notification> <task-id>a416d241d013c3078</task-id> <tool-use-id>abc</tool-use-id></task-notification>')"

echo ""
echo "--- genuine user prompts: must be forwarded unchanged ---"

assert_forwarded "real multi-word prompt" \
  "after finxing all run /orchestrate-cleanup and release this version using /release-mac-app"

assert_forwarded "slash command" \
  "/orchestrate-cleanup"

assert_forwarded "benign mid-text angle bracket (comparison)" \
  "is a < b ever true?"

assert_forwarded "benign mid-text angle bracket (JSX-ish)" \
  "use <Foo/> component"

assert_forwarded "tag name is a superset, not an exact denylist match" \
  "<command-namespace>foo</command-namespace>"

echo ""
echo "===================="
if [ "$FAILS" -eq 0 ]; then
  echo "PASS: all $TOTAL cases passed"
  exit 0
else
  echo "FAIL: $FAILS/$TOTAL cases failed"
  exit 1
fi
