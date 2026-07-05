#!/bin/bash
# tian Claude Code hook — forward the submitted prompt to the Session Overview card.
#
# Reads the Claude Code UserPromptSubmit JSON payload from stdin, extracts
# `.prompt`, collapses whitespace and caps its length, then invokes
# `tian prompt set --text "<prompt>"` so the latest user prompt can be shown
# on the Session Overview card.
#
# Always exits 0 so a forwarding failure never blocks prompt submission.

set +e

INPUT=$(cat 2>/dev/null)
[ -z "$INPUT" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Collapse newlines/tabs to spaces and cap length so a huge multi-line prompt
# can't bloat the UI or a command line. Run the truncation under a UTF-8 locale
# so `cut -c` counts characters, not bytes, and never splits a multibyte glyph.
PROMPT=$(printf '%s' "$PROMPT" | tr '\n\r\t' '   ' | LC_ALL=en_US.UTF-8 cut -c1-200)

# Reject whitespace-only prompts: after collapsing, if nothing but spaces
# remains, there's no real content to show — exit without touching the card.
TRIMMED=$(printf '%s' "$PROMPT" | tr -d ' ')
[ -z "$TRIMMED" ] && exit 0

if [ -n "$TIAN_CLI_PATH" ]; then
  "$TIAN_CLI_PATH" prompt set --text "$PROMPT" >/dev/null 2>&1
fi

exit 0
