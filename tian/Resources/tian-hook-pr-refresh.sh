#!/bin/bash
# tian Claude Code hook — refresh sidebar PR badge after PR-affecting `gh` calls.
#
# Reads the Claude Code Bash PostToolUse JSON payload from stdin, looks at
# `tool_input.command`, and if it matches `gh pr (create|merge|close|reopen|edit)`
# invokes `tian-cli git refresh` so the PR badge updates without waiting for
# the 60s PRStatusCache TTL. `gh pr create` against an already-pushed branch
# makes no local file change, so the FSEvents-based eviction in tian doesn't
# fire on its own.
#
# Always exits 0 so a refresh failure never blocks tool execution.

set +e

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -z "$CMD" ] && exit 0

# Match `gh pr <subcmd>` for PR-affecting subcommands. Word boundaries keep
# `gh prefix` and similar tokens from triggering. Also catches piped/chained
# invocations like `... && gh pr create ...`.
if printf '%s' "$CMD" | grep -qE '(^|[^a-zA-Z0-9_])gh +pr +(create|merge|close|reopen|edit|ready)([^a-zA-Z0-9_-]|$)'; then
  if [ -n "$TIAN_CLI_PATH" ]; then
    "$TIAN_CLI_PATH" git refresh >/dev/null 2>&1
  fi
fi

exit 0
