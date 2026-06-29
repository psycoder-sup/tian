#!/usr/bin/env bash
#
# implement.sh — delegate an approved implementation task to a fresh
# worktree-backed Space's Claude session, then wait for it to finish.
#
# This is pure orchestration over the existing `tian` CLI primitives
# (worktree create / pane capture / pane send / pane list). It adds no new
# binary subcommands and makes no IPC changes — it only composes what the
# `tian` control plane already exposes.
#
# Flow: create worktree Space (background by default) -> wait for its
# auto-seeded Claude session to boot -> paste the plan (with a mandatory
# self-verify coda appended) into that session -> poll the pane's sessionState
# until the turn settles (idle / needs_attention) -> print machine-readable IDs
# + a capture tail (which carries the session's self-verify report) for the
# caller.
#
# The delegated session self-verifies its OWN work (build + test + plan-coverage
# check) and prints a structured report as the last thing in its turn. That
# self-check is the only mandatory verification layer right now; deeper
# INDEPENDENT verification by the caller (re-reading the diff) or a separate
# verifier session is a planned future layer. This script never removes the
# worktree.

set -euo pipefail

# ---- tunables ----------------------------------------------------------------
START_GRACE=15      # Phase A: seconds to wait for the session to start working
POLL_INTERVAL=4     # Phase B: seconds between sessionState polls
CAPTURE_TAIL=40     # lines of the final capture to echo

# ---- helpers -----------------------------------------------------------------
PROG="tian implement"

log()  { printf '%s: %s\n' "$PROG" "$1" >&2; }
err()  { printf '%s: error: %s\n' "$PROG" "$1" >&2; exit "${2:-1}"; }

usage() {
  cat >&2 <<'EOF'
Usage: implement.sh <branch> [options]

Delegate an approved implementation task to a fresh worktree Space's Claude
session and wait for it to finish.

The plan/task text comes from --prompt-file or STDIN.

Positional:
  <branch>                 Branch name for the worktree (required).

Options:
  --base <ref>             Create the branch from <ref> instead of HEAD.
  --existing               Check out an existing branch instead of creating one.
  --path <repo>            Repo path to create the worktree from.
  --workspace <id>         Workspace (window) to host the new Space.
  --foreground             Create the worktree in the foreground (steal focus).
                           Default is background (does not steal focus).
  --prompt-file <f>        Read the plan from file <f> (else read from STDIN).
  --timeout <sec>          Overall ceiling for the post-delegation wait
                           (default 5400).
  --boot-timeout <sec>     Ceiling for the Claude session to boot (default 60).
  -h, --help               Show this help.

Output (stdout): machine-readable IDs + final_state, then a capture tail.
final_state is one of: idle | needs_attention | failed | inactive | running.
A `running` result means the ceiling elapsed while the session was still
actively working — it is NOT a failure; re-attach with the printed
`tian pane capture` command to keep watching.
Exit: 0 if the session settled at idle/needs_attention OR is still running
(re-attachable); non-zero on a hard failure or a genuine stall.
EOF
}

# need_val <flag> <maybe-value...> — verify a value arg is present & non-empty.
need_val() {
  local flag="$1"
  if [[ $# -lt 2 || -z "${2:-}" ]]; then
    err "option $flag requires a value" 2
  fi
}

# ---- argument parsing --------------------------------------------------------
branch=""
base=""
existing=0
path=""
workspace=""
foreground=0
prompt_file=""
timeout=5400
boot_timeout=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)         need_val "$@"; base="$2"; shift 2 ;;
    --path)         need_val "$@"; path="$2"; shift 2 ;;
    --workspace)    need_val "$@"; workspace="$2"; shift 2 ;;
    --prompt-file)  need_val "$@"; prompt_file="$2"; shift 2 ;;
    --timeout)      need_val "$@"; timeout="$2"; shift 2 ;;
    --boot-timeout) need_val "$@"; boot_timeout="$2"; shift 2 ;;
    --existing)     existing=1; shift ;;
    --foreground)   foreground=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    --)             shift; break ;;
    -*)             usage; err "unknown option: $1" 2 ;;
    *)
      if [[ -z "$branch" ]]; then
        branch="$1"; shift
      else
        usage; err "unexpected extra argument: $1" 2
      fi
      ;;
  esac
done

if [[ -z "$branch" ]]; then
  usage
  exit 2
fi

[[ "$timeout" =~ ^[0-9]+$ ]] \
  || err "--timeout must be a non-negative integer (got: $timeout)" 2
[[ "$boot_timeout" =~ ^[0-9]+$ ]] \
  || err "--boot-timeout must be a non-negative integer (got: $boot_timeout)" 2

# ---- preconditions -----------------------------------------------------------
# Checked after arg parsing so `--help` and the no-args usage path work without
# a live tian socket. Done before reading STDIN so we never consume the plan
# when we're going to bail anyway.
TIAN="${TIAN_CLI_PATH:-tian}"
command -v "$TIAN" >/dev/null 2>&1 \
  || err "tian CLI not found (add tian to PATH or set TIAN_CLI_PATH)"
command -v jq >/dev/null 2>&1 \
  || err "jq is required but not found (brew install jq)"

if [[ "$("$TIAN" ping 2>/dev/null || true)" != "pong" ]]; then
  err "not inside a tian session (tian ping did not return pong)"
fi

# ---- run-log setup -----------------------------------------------------------
# One JSONL record per delegation is appended at every post-tracking exit, so the
# /tian workflow is auditable from a durable log instead of transcript parsing.
# Logging is best-effort and MUST NEVER break a delegation (all writes ||true).
#
# TIAN_WORKFLOW_VERSION stamps every record so a run can be tied to the exact
# harness that produced it. BUMP IT whenever implement.sh, the self-verify coda,
# or implement-logrec.sh changes behavior. Changelog:
#   1.0.0 — 90-min ceiling; `running` (busy-at-ceiling) is not a failure; child
#           commits its own work + emits status/notify; durable run log with
#           git-derived commits and a self-verify completion record.
#   1.0.1 — watcher parses the self-verify verdict/build/tests even when the pane
#           capture indents the block (leading whitespace).
TIAN_WORKFLOW_VERSION="1.0.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
LOGREC="$SCRIPT_DIR/implement-logrec.sh"
RUN_START_EPOCH="$(date +%s 2>/dev/null || echo 0)"
TIAN_IMPLEMENT_LOG="${TIAN_IMPLEMENT_LOG:-$HOME/.claude/tian/implement-runs.jsonl}"
repo_root="$(git -C "${path:-.}" rev-parse --show-toplevel 2>/dev/null || echo "${path:-$PWD}")"
worktree_path=""   # resolved after worktree create; used for git-derived commits

# ---- resolve the plan text ---------------------------------------------------
plan=""
if [[ -n "$prompt_file" ]]; then
  [[ -e "$prompt_file" ]] || err "prompt file not found: $prompt_file" 2
  if [[ -d "$prompt_file" ]]; then err "prompt file is a directory: $prompt_file" 2; fi
  [[ -r "$prompt_file" ]] || err "prompt file not readable: $prompt_file" 2
  plan="$(cat -- "$prompt_file")"
else
  if [[ -t 0 ]]; then
    err "no plan provided (pass --prompt-file <f> or pipe the plan via stdin)" 2
  fi
  plan="$(cat)"
fi

# Trim-check: reject an all-whitespace / empty plan.
if [[ -z "${plan//[[:space:]]/}" ]]; then
  err "no plan provided (plan text is empty)" 2
fi

# ---- append the mandatory self-verify coda ----------------------------------
# Every delegated plan gets this appended so the implementer verifies its OWN
# work before settling: build + test + plan-coverage self-check, then emit a
# delimited, greppable report as the LAST thing it prints (so it lands in the
# capture tail the caller reads). The diff already lives in the implementer's
# context, so self-verify is near-free there; only the compact report crosses
# back to the caller. This is a self-check, not an independent review — a red
# build/test must never be reported as `pass`.
#
# Read via `read -r -d ''` (not $(cat <<'EOF')): under macOS bash 3.2 a heredoc
# nested in $( ) whose body contains apostrophes (repo's, caller's) breaks the
# parser's quote matching. `read` has no command substitution, so it is safe.
IFS= read -r -d '' SELF_VERIFY_CODA <<'CODA' || true
---

When you have finished implementing the above, you MUST self-verify before you
stop — do not report done until you have:

1. Built the project (discover the build command from this repo's conventions:
   CLAUDE.md / README / Makefile / package.json scripts / etc.).
2. Run the project's test suite the same way.
3. Re-read the plan above and confirmed each item is actually implemented.
4. Committed your own work in atomic, well-described commits. This worktree is
   yours — you own its commits. Do NOT push, open a PR, merge, or touch main;
   the orchestrator publishes when the user asks.

Then print exactly this block (fill it in; keep the marker lines verbatim so it
can be parsed):

===== TIAN SELF-VERIFY =====
build: pass | fail | skipped(<why>)
tests: pass | fail | skipped(<why>) — <one-line summary, e.g. counts/failures>
plan:
  - <plan item>: done | partial | skipped
commits: <short hashes + subjects you committed, or "none (why)">
deviations: <anything done differently from the plan, or "none">
open_questions: <anything needing the caller's decision, or "none">
verdict: pass | needs-attention | fail
===== END SELF-VERIFY =====

If you cannot build or test (command unknown, environment missing), do NOT
silently skip — set that line to skipped(<reason>) and lower the verdict
accordingly. Never report `pass` on an unverified or red build/test.
CODA

# The trailing signal section is built UNQUOTED so the real script path, branch,
# version, and timeout are interpolated now, while $PWD / $TIAN_* (the child's
# own env) and the <verdict>/<build>/<tests> placeholders stay literal for the
# delegated session to fill. Worded without apostrophes (macOS bash 3.2 heredoc
# safety). The self-verify record is what closes the `running` -> done gap: it is
# written by the implementer AFTER it finishes, so it carries the final verdict
# even when the watcher already exited reporting `running`.
IFS= read -r -d '' SIGNAL_SECTION <<EOF2 || true

Finally, as the LAST thing you do this turn, run these three commands so the
orchestrator and the user get a durable, recorded signal even if the watcher has
already detached. You are inside a tian pane: \$PWD is this worktree and the
TIAN_* env vars are set. Fill in <verdict>/<build>/<tests> from your SELF-VERIFY
block. If the verdict is needs-attention or fail, use --state needs_attention
(not idle) in the first two commands so the sidebar flags it.

  tian status set --label "self-verify: <verdict>" --state idle
  tian notify "self-verify: <verdict>" --title "tian implement"
  bash "$LOGREC" --source self-verify --workflow-version "$TIAN_WORKFLOW_VERSION" \\
    --final-state idle --branch "$branch" --worktree "\$PWD" --timeout $timeout \\
    --space "\$TIAN_SPACE_ID" --pane "\$TIAN_PANE_ID" --tab "\$TIAN_TAB_ID" \\
    --verdict "<verdict>" --build "<build>" --tests "<tests>"
EOF2
plan="${plan}"$'\n\n'"${SELF_VERIFY_CODA}${SIGNAL_SECTION}"

# ---- create the worktree Space ----------------------------------------------
wt_args=( "$branch" )
if [[ -n "$base" ]];      then wt_args+=( --base "$base" ); fi
if (( existing ));        then wt_args+=( --existing ); fi
if [[ -n "$path" ]];      then wt_args+=( --path "$path" ); fi
if [[ -n "$workspace" ]]; then wt_args+=( --workspace "$workspace" ); fi
if (( ! foreground ));    then wt_args+=( --background ); fi
wt_args+=( --format json )

log "creating worktree Space for '$branch'..."
if ! out="$("$TIAN" worktree create "${wt_args[@]}")"; then
  err "worktree create failed (see message above)"
fi

if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
  err "worktree create did not return valid JSON"
fi

space_id="$(printf '%s' "$out" | jq -r '.space_id // empty')" || space_id=""
claude_tab="$(printf '%s' "$out" | jq -r '.claude_tab_id // empty')" || claude_tab=""
claude_pane="$(printf '%s' "$out" | jq -r '.claude_pane_id // empty')" || claude_pane=""
terminal_pane="$(printf '%s' "$out" | jq -r '.pane_id // empty')" || terminal_pane=""

# Worktree filesystem path — prefer the create payload, else resolve from git by
# branch. Used by the run log to derive the actual commits (authoritative).
worktree_path="$(printf '%s' "$out" | jq -r '.worktree // .path // empty')" || worktree_path=""
if [[ -z "$worktree_path" ]]; then
  worktree_path="$(git -C "$repo_root" worktree list --porcelain 2>/dev/null \
    | awk -v b="refs/heads/$branch" '/^worktree /{p=$2} $0=="branch "b{print p; exit}')" \
    || worktree_path=""
fi

if [[ -z "$claude_pane" ]]; then
  err "worktree create returned no claude_pane_id (cannot delegate)"
fi
if [[ -z "$claude_tab" ]]; then
  err "worktree create returned no claude_tab_id (cannot track session state)"
fi

# ---- wait for the Claude session to boot ------------------------------------
log "waiting for the Claude session to boot (<=${boot_timeout}s)..."
booted=0
SECONDS=0
while (( SECONDS < boot_timeout )); do
  if "$TIAN" pane capture --pane "$claude_pane" 2>/dev/null | grep -q 'Claude Code'; then
    booted=1
    break
  fi
  sleep 1
done
if (( ! booted )); then
  err "Claude session did not boot within ${boot_timeout}s (space_id=$space_id)" 3
fi

# get_state: print the Claude pane's sessionState (empty on unknown/transient
# error). Defined before delegation so the submit step can confirm the session
# actually started working.
get_state() {
  "$TIAN" pane list --tab "$claude_tab" --format json 2>/dev/null \
    | jq -r --arg id "$claude_pane" '.[] | select(.id == $id) | .sessionState // empty'
}

# ---- delegate the plan -------------------------------------------------------
# Paste the plan, then submit with a SEPARATE Return, retried until the session
# actually starts. A single Return fired immediately after a large multi-line
# bracketed paste races with the terminal's paste ingestion and gets swallowed —
# the plan stays staged in the input box, unsent, and the session never starts
# (observed live: a full-timeout wait with the plan still showing as
# "[Pasted text]"). Splitting the paste (--no-enter) from follow-up bare Returns
# defeats the race; a trailing newline can be absorbed as a stray line, so trim.
log "delegating the plan to the Claude session..."
plan="${plan%$'\n'}"
if ! printf '%s' "$plan" | "$TIAN" pane send - --no-enter --pane "$claude_pane"; then
  err "failed to paste the plan to the Claude session"
fi
submitted=0
for _ in 1 2 3 4 5; do
  sleep 2
  # Empty payload => pane send issues a Return only (submit) with no typed text.
  printf '' | "$TIAN" pane send - --pane "$claude_pane" 2>/dev/null || true
  case "$(get_state)" in
    busy|active|needs_attention|failed) submitted=1; break ;;
  esac
done
if (( ! submitted )); then
  log "warning: plan submitted but session not observed working; tracking anyway"
fi

# ---- track the session to a settled state -----------------------------------

started=0
last_state=""
final_state=""

SECONDS=0

# Phase A — wait for the session to start working (busy/active). Bounded by a
# short start-grace: this is only a head start on detecting `started` — Phase B
# keeps watching for busy/active too, so a session that boots slowly is still
# caught. If the grace expires without seeing work, we proceed to Phase B
# anyway. An early needs_attention/failed means it already settled, so stop
# waiting.
log "tracking session (phase A: start, grace ${START_GRACE}s)..."
while (( SECONDS < START_GRACE && SECONDS < timeout )); do
  state="$(get_state)" || state=""
  if [[ -n "$state" ]]; then last_state="$state"; fi
  case "$state" in
    busy|active)             started=1; break ;;
    needs_attention|failed)  started=1; break ;;
  esac
  sleep 1
done

# Phase B — wait for the turn to settle. needs_attention/failed are unambiguous
# settled states. `idle` and `inactive`, however, are also the booting/initial
# states a freshly-seeded session reports *before* it picks up the delegated
# prompt — so they only count as terminal once we've confirmed the session
# actually started working (`started`, set in either phase). Without that guard
# a stale boot-time `idle` would end the wait immediately and we'd report
# success before any work happened. The total wait (A+B) is bounded by --timeout.
log "tracking session (phase B: finish, total ceiling ${timeout}s)..."
while (( SECONDS < timeout )); do
  state="$(get_state)" || state=""
  if [[ -n "$state" ]]; then last_state="$state"; fi
  case "$state" in
    busy|active)             started=1 ;;
    needs_attention|failed)  final_state="$state"; break ;;
    idle|inactive)           if (( started )); then final_state="$state"; break; fi ;;
  esac
  sleep "$POLL_INTERVAL"
done

# ---- report ------------------------------------------------------------------
capture="$("$TIAN" pane capture --pane "$claude_pane" 2>/dev/null | tail -n "$CAPTURE_TAIL" || true)"

emit_block() {
  local fs="$1"
  printf 'space_id=%s\n' "$space_id"
  printf 'claude_tab_id=%s\n' "$claude_tab"
  printf 'claude_pane_id=%s\n' "$claude_pane"
  printf 'terminal_pane_id=%s\n' "$terminal_pane"
  printf 'final_state=%s\n' "$fs"
}

# log_run <final_state> <exit_code> — append the watcher's record for this
# delegation via the shared writer. Best-effort: never affects the outcome.
# build/tests/verdict are parsed from the capture tail when present (a `running`
# outcome has none yet — the implementer's own self-verify record fills those in
# later); commits/dirty are derived from git by the writer (authoritative).
log_run() {
  local fs="$1" ec="$2" elapsed sv_verdict sv_build sv_tests
  elapsed=$(( $(date +%s 2>/dev/null || echo "$RUN_START_EPOCH") - RUN_START_EPOCH ))
  sv_verdict="$(printf '%s\n' "$capture" | sed -n 's/^[[:space:]]*verdict:[[:space:]]*//p' | tail -1)"
  sv_build="$(printf '%s\n'   "$capture" | sed -n 's/^[[:space:]]*build:[[:space:]]*//p'   | tail -1)"
  sv_tests="$(printf '%s\n'   "$capture" | sed -n 's/^[[:space:]]*tests:[[:space:]]*//p'   | tail -1)"
  bash "$LOGREC" \
    --source watcher --workflow-version "$TIAN_WORKFLOW_VERSION" \
    --final-state "$fs" --exit-code "$ec" --elapsed "$elapsed" --timeout "$timeout" \
    --branch "$branch" --repo "$repo_root" --worktree "$worktree_path" \
    --space "$space_id" --pane "$claude_pane" --tab "$claude_tab" \
    --verdict "${sv_verdict:-unknown}" --build "${sv_build:-}" --tests "${sv_tests:-}" \
    --log "$TIAN_IMPLEMENT_LOG" 2>/dev/null || true
}

if [[ -z "$final_state" ]]; then
  # Ceiling elapsed before the session settled. Distinguish a healthy
  # still-working session from a genuine stall: a child still in busy/active is
  # NOT a failure (a real milestone routinely outlasts the ceiling) — report it
  # as `running` and exit 0 so the caller re-attaches instead of taking over.
  # Only a non-progressing session (idle/inactive/unknown that never settled,
  # i.e. truly stuck) keeps the hard `timeout` / exit 4 path.
  case "$last_state" in
    busy|active)
      emit_block "running"
      printf 'NOTE: still working after %ss (state: %s) — NOT a failure.\n' \
        "$timeout" "$last_state"
      printf 'Re-attach to keep watching: tian pane capture --pane %s\n' "$claude_pane"
      printf -- '--- capture ---\n'
      printf '%s\n' "$capture"
      log_run "running" 0
      exit 0
      ;;
    *)
      emit_block "timeout"
      printf 'NOTE: timed out after %ss (last observed state: %s)\n' \
        "$timeout" "${last_state:-unknown}"
      printf -- '--- capture ---\n'
      printf '%s\n' "$capture"
      log_run "timeout" 4
      exit 4
      ;;
  esac
fi

emit_block "$final_state"
case "$final_state" in
  idle)
    : # clean finish
    ;;
  needs_attention)
    printf 'NOTE: session paused for input (needs_attention)\n'
    ;;
  failed)
    printf 'NOTE: session reported a failed turn (failed)\n'
    ;;
  inactive)
    printf 'NOTE: session ended unexpectedly (inactive)\n'
    ;;
esac
printf -- '--- capture ---\n'
printf '%s\n' "$capture"

case "$final_state" in
  idle|needs_attention) log_run "$final_state" 0; exit 0 ;;
  *)                    log_run "$final_state" 5; exit 5 ;;
esac
