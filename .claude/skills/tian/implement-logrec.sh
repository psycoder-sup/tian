#!/usr/bin/env bash
#
# implement-logrec.sh — append ONE /tian implement run record to the run log.
#
# Single owner of the log record format, called from two places:
#   - implement.sh (the watcher) at each post-tracking exit  → --source watcher
#   - the delegated session itself, after self-verify         → --source self-verify
#
# The watcher writes the outcome it observed (may be `running` with no verdict
# yet); the self-verify record — written by the implementer once it actually
# finishes — carries the final verdict and supersedes the watcher's for stats.
#
# `commits` and `dirty` are derived from git in the worktree (authoritative),
# NOT self-reported. Best-effort: never fail the caller — git problems just
# yield an empty commit list.

set -uo pipefail

LOG_DEFAULT="$HOME/.claude/tian/implement-runs.jsonl"

# ---- defaults / parse --------------------------------------------------------
final_state=""; source="watcher"; branch=""; repo=""; worktree=""
space=""; pane=""; tab=""; verdict=""; build=""; tests=""; version="unknown"
exit_code="null"; elapsed="null"; timeout="null"; logf="${TIAN_IMPLEMENT_LOG:-$LOG_DEFAULT}"
child_session=""; parent_session=""; no_wait="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --final-state)      final_state="$2"; shift 2 ;;
    --source)           source="$2"; shift 2 ;;
    --workflow-version) version="$2"; shift 2 ;;
    --branch)      branch="$2"; shift 2 ;;
    --repo)        repo="$2"; shift 2 ;;
    --worktree)    worktree="$2"; shift 2 ;;
    --space)       space="$2"; shift 2 ;;
    --pane)        pane="$2"; shift 2 ;;
    --tab)         tab="$2"; shift 2 ;;
    --exit-code)   exit_code="$2"; shift 2 ;;
    --elapsed)     elapsed="$2"; shift 2 ;;
    --timeout)     timeout="$2"; shift 2 ;;
    --verdict)     verdict="$2"; shift 2 ;;
    --build)       build="$2"; shift 2 ;;
    --tests)       tests="$2"; shift 2 ;;
    --child-session)  child_session="$2"; shift 2 ;;
    --parent-session) parent_session="$2"; shift 2 ;;
    --no-wait)        no_wait="$2"; shift 2 ;;
    --log)         logf="$2"; shift 2 ;;
    *) shift ;;  # ignore unknowns — logging must never be brittle
  esac
done

command -v jq >/dev/null 2>&1 || exit 0   # no jq → silently skip (never break caller)

# ---- resolve the child Claude session id (best-effort) -----------------------
# An explicit --child-session wins. Otherwise, when a worktree is known, resolve
# the NEWEST Claude transcript under that worktree's project dir. Claude Code
# names that dir by mangling the absolute worktree path — every "/" and "." is
# replaced with "-" — under ~/.claude/projects/. This is how the self-verify
# record (which only passes --worktree "$PWD") gets its child_session_id without
# the child having to compute its own id inline. Always best-effort: an empty
# result just yields an empty field.
if [[ -z "$child_session" && -n "$worktree" ]]; then
  proj_dir="$HOME/.claude/projects/$(printf '%s' "$worktree" | sed 's#[/.]#-#g')"
  if [[ -d "$proj_dir" ]]; then
    newest_tx="$(ls -1t "$proj_dir"/*.jsonl 2>/dev/null | head -n1)" || newest_tx=""
    [[ -n "$newest_tx" ]] && child_session="$(basename "$newest_tx" .jsonl)"
  fi
fi

# no_wait is recorded as a JSON boolean (default false); accept a few truthy forms.
case "$no_wait" in true|1|yes) no_wait_json=true ;; *) no_wait_json=false ;; esac

# ---- derive commits + dirty from the worktree (authoritative) ----------------
commits_json="[]"
dirty="null"
if [[ -n "$worktree" ]] && git -C "$worktree" rev-parse --git-dir >/dev/null 2>&1; then
  base=""
  for ref in main origin/main master origin/master; do
    if git -C "$worktree" rev-parse --verify -q "$ref" >/dev/null 2>&1; then base="$ref"; break; fi
  done
  if [[ -n "$base" ]]; then
    commits_json="$(git -C "$worktree" log --oneline --no-color "$base"..HEAD 2>/dev/null \
      | jq -R . | jq -s . 2>/dev/null)" || commits_json="[]"
    [[ -n "$commits_json" ]] || commits_json="[]"
  fi
  if [[ -n "$(git -C "$worktree" status --porcelain 2>/dev/null)" ]]; then dirty=true; else dirty=false; fi
fi

# numeric args must be valid JSON for --argjson; coerce non-numbers to null
isnum() { [[ "$1" =~ ^-?[0-9]+$ ]]; }
isnum "$exit_code" || exit_code="null"
isnum "$elapsed"   || elapsed="null"
isnum "$timeout"   || timeout="null"

# ---- append --------------------------------------------------------------------
mkdir -p "$(dirname "$logf")" 2>/dev/null || true
jq -cn \
  --arg ts       "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
  --arg version  "$version" \
  --arg source   "$source" \
  --arg repo     "$repo" \
  --arg branch   "$branch" \
  --arg space    "$space" \
  --arg pane     "$pane" \
  --arg tab      "$tab" \
  --arg fs       "$final_state" \
  --argjson ec   "$exit_code" \
  --argjson el   "$elapsed" \
  --argjson to   "$timeout" \
  --arg verdict  "${verdict:-unknown}" \
  --arg build    "$build" \
  --arg tests    "$tests" \
  --arg csid     "$child_session" \
  --arg psid     "$parent_session" \
  --argjson nowait  "$no_wait_json" \
  --argjson commits "$commits_json" \
  --argjson dirty   "$dirty" \
  '{ts:$ts, workflow_version:$version, source:$source, repo:$repo, branch:$branch,
    space_id:$space, claude_pane_id:$pane, claude_tab_id:$tab, final_state:$fs,
    exit_code:$ec, elapsed_s:$el, timeout_s:$to, verdict:$verdict, build:$build,
    tests:$tests, child_session_id:$csid, parent_session_id:$psid, no_wait:$nowait,
    commits:$commits, dirty:$dirty}' \
  >> "$logf" 2>/dev/null || true
