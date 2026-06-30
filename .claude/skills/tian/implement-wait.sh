#!/usr/bin/env bash
#
# implement-wait.sh — the orchestrator's await primitive for async fan-out.
#
# After firing N `implement.sh --no-wait` delegations (one writer per branch),
# the orchestrator calls this to block until each named branch has its durable
# done-signal in the run log: the `source=self-verify` record the child writes
# AFTER it finishes self-verifying. It polls the LOG FILE only — it NEVER runs
# `tian pane capture` (no pane polling, no context bloat). For each branch it
# then prints a compact summary line:
#
#   branch  verdict  build  tests  (N commits)
#
# Usage:
#   implement-wait.sh --branch <b> [--branch <b2> ...] [--since <epoch>]
#                     [--timeout <sec>] [--log <path>] [--poll <sec>]
#
#   --branch <b>     Branch to await (repeatable; at least one required).
#   --since <epoch>  Only count self-verify records at/after this unix time, so a
#                    prior run's record for the same branch can't satisfy the
#                    wait. Default 0 (any record qualifies).
#   --timeout <sec>  Overall ceiling (default 5400). On timeout, print which
#                    branches are still pending and exit 4 (but still print
#                    whatever DID arrive).
#   --log <path>     Run log to poll (default
#                    ${TIAN_IMPLEMENT_LOG:-$HOME/.claude/tian/implement-runs.jsonl}).
#   --poll <sec>     File poll interval (default 5).
#
# Exit: 0 once every branch is satisfied; 4 on timeout. Best-effort: if jq is
# missing it degrades to a clean skip (exit 0), like the other scripts.

set -uo pipefail

PROG="implement-wait"
err() { printf '%s: error: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }

LOG_DEFAULT="$HOME/.claude/tian/implement-runs.jsonl"

# ---- argument parsing --------------------------------------------------------
branches=()
since=0
timeout=5400
poll=5
logf="${TIAN_IMPLEMENT_LOG:-$LOG_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)  [[ $# -ge 2 && -n "${2:-}" ]] || err "--branch requires a value" 2
               branches+=( "$2" ); shift 2 ;;
    --since)   [[ $# -ge 2 ]] || err "--since requires a value" 2;   since="$2";   shift 2 ;;
    --timeout) [[ $# -ge 2 ]] || err "--timeout requires a value" 2; timeout="$2"; shift 2 ;;
    --log)     [[ $# -ge 2 ]] || err "--log requires a value" 2;     logf="$2";    shift 2 ;;
    --poll)    [[ $# -ge 2 ]] || err "--poll requires a value" 2;    poll="$2";    shift 2 ;;
    -h|--help) sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         err "unknown argument: $1" 2 ;;
  esac
done

if (( ${#branches[@]} == 0 )); then
  err "no branches given (pass at least one --branch <b>)" 2
fi

[[ "$since"   =~ ^[0-9]+$ ]] || err "--since must be a unix epoch integer (got: $since)" 2
[[ "$timeout" =~ ^[0-9]+$ ]] || err "--timeout must be a non-negative integer (got: $timeout)" 2
[[ "$poll"    =~ ^[0-9]+$ ]] || err "--poll must be a non-negative integer (got: $poll)" 2
(( poll > 0 )) || poll=1

# jq missing → degrade gracefully (clean skip), like the sibling scripts.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s: jq not found; skipping wait (returning success)\n' "$PROG" >&2
  exit 0
fi

# ---- helpers -----------------------------------------------------------------
# ts_epoch <iso8601> — convert a `YYYY-MM-DDThh:mm:ssZ` timestamp to unix epoch.
# BSD date (macOS) first, then GNU date; empty on failure.
ts_epoch() {
  local ts="$1" e=""
  e="$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null)" \
    || e="$(date -u -d "$ts" +%s 2>/dev/null)" || e=""
  printf '%s' "$e"
}

# latest_rec <branch> — print the LATEST qualifying self-verify record (compact
# JSON) for <branch>: source=self-verify, branch matches, and ts >= --since.
# Empty if none yet. The log is append-ordered, so the last qualifying line wins.
latest_rec() {
  local b="$1" line ts epoch best=""
  [[ -f "$logf" ]] || { printf ''; return 0; }
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    ts="$(printf '%s' "$line" | jq -r '.ts // empty' 2>/dev/null)"
    [[ -n "$ts" ]] || continue
    epoch="$(ts_epoch "$ts")"; [[ -n "$epoch" ]] || epoch=0
    if (( epoch >= since )); then best="$line"; fi
  done < <(jq -c --arg b "$b" \
              'select(.source == "self-verify" and .branch == $b)' "$logf" 2>/dev/null)
  printf '%s' "$best"
}

# ---- poll until satisfied or timed out ---------------------------------------
start="$(date +%s 2>/dev/null || echo 0)"
deadline=$(( start + timeout ))

printf '%s: awaiting %d branch(es) via run log: %s\n' "$PROG" "${#branches[@]}" "$logf" >&2
while :; do
  remaining=0
  for b in "${branches[@]}"; do
    [[ -z "$(latest_rec "$b")" ]] && remaining=$(( remaining + 1 ))
  done
  (( remaining == 0 )) && break
  now="$(date +%s 2>/dev/null || echo "$deadline")"
  (( now >= deadline )) && break
  sleep "$poll"
done

# ---- summary -----------------------------------------------------------------
printf '\n%-40s %-15s %-9s %s\n' "branch" "verdict" "build" "tests / commits"
printf '%-40s %-15s %-9s %s\n' "------" "-------" "-----" "---------------"
exit_code=0
for b in "${branches[@]}"; do
  rec="$(latest_rec "$b")"
  if [[ -z "$rec" ]]; then
    printf '%-40s %s\n' "$b" "PENDING — no self-verify record yet"
    exit_code=4
    continue
  fi
  verdict="$(printf '%s' "$rec" | jq -r '.verdict // "?"' 2>/dev/null)"
  build="$(printf '%s'   "$rec" | jq -r '.build // ""' 2>/dev/null)"
  tests="$(printf '%s'   "$rec" | jq -r '.tests // ""' 2>/dev/null)"
  ncommits="$(printf '%s' "$rec" | jq -r '(.commits | if type=="array" then length else 0 end)' 2>/dev/null)"
  [[ "$ncommits" =~ ^[0-9]+$ ]] || ncommits=0
  printf '%-40s %-15s %-9s %s (%s commits)\n' \
    "$b" "${verdict:-?}" "${build:-?}" "${tests:-—}" "$ncommits"
done

if (( exit_code != 0 )); then
  printf '\n%s: timed out after %ss — some branches still pending (exit %d).\n' \
    "$PROG" "$timeout" "$exit_code" >&2
fi
exit "$exit_code"
