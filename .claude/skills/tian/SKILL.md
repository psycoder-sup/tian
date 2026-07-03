---
name: tian
description: >-
  Drive the tian terminal emulator from the shell with the `tian` CLI: create/focus/close/list
  workspaces, sessions, and panes; spin up git-worktree-backed sessions for a branch; split the terminal
  panel and run commands in it; send input to and capture output from other terminal or agent sessions;
  set the sidebar status label/state; and post macOS notifications. Use whenever you are inside a tian
  session (the TIAN_SOCKET env var is set) and the task involves arranging terminals, running work in
  another pane/session, spawning a worktree for a task, or notifying on completion.
---

# Driving tian with the `tian` CLI

tian organizes terminals as **Workspace → Session**. A **Session** is one Claude pane plus an optional,
toggleable terminal panel. The `tian` CLI controls the running app over IPC. Use it instead of asking the
user to click around.

## Preconditions

- Only works **inside a tian terminal session** — it needs `TIAN_SOCKET` (set automatically by the app).
  If `tian ping` doesn't print `pong`, you're not inside tian; stop and tell the user.
- The binary is `tian` (on `PATH`). Hooks/scripts can also use `$TIAN_CLI_PATH`.
- `tian open` launches or focuses the app and is the **only** command that works outside a tian session.

## Mode: implement

When invoked as **`/tian implement <task>`**, delegate the task to a **fresh worktree Session's Claude
pane** using the bundled **`implement.sh`** orchestrator (it lives next to this file). Do not implement
the task yourself — see the anti-freelance rule in Core rules.

> **STOP — orchestrator hard limits.** From THIS session, for any delegated worktree you MUST NOT:
> `cd` into it; `Edit`/`Write` any file in it; `git commit` in it; run `git show`/`diff`/`log` on it
> to reconstruct what the child did; or loop on `tian pane capture` to poll its progress.
> Your ONLY inputs are the script's **IDs block** and the child's **`TIAN SELF-VERIFY`** report
> (read it from the run log or the capture tail). Everything else is the child's job — route every
> follow-up to the live child with `tian pane send`. This is repeated below on purpose: lead with it.

1. **Write the plan to a file.** Capture the approved plan/task as text (e.g. a temp file like
   `.dev/tmp/plan.md`) and choose a branch name for the work.
2. **Run the bundled script.** It creates the worktree (background by default), waits for the Session's
   auto-seeded Claude pane to boot, pastes the plan — plus a **mandatory self-verify coda** the script
   appends automatically — into it, and blocks until that session settles:
   ```bash
   bash "<skill-dir>/implement.sh" <branch> --prompt-file <plan-file>
   # …or pipe the plan on stdin instead of --prompt-file:
   printf '%s' "$plan" | bash "<skill-dir>/implement.sh" <branch>
   ```
   `<skill-dir>` is the directory that contains this `SKILL.md`. The script prints `session_id`,
   `claude_pane_id`, `terminal_pane_id`, and `final_state`, then a capture tail.
   It exits 0 once the session reaches `idle` or `needs_attention`, non-zero on a hard failure/stall.
   A `final_state=running` (exit 0) means the ceiling elapsed while the session was **still working** —
   that is **not** a failure: re-attach with the printed `tian pane capture --pane <claude_pane_id>` and
   keep watching, don't take the task over. Likewise, await the background run's completion notification
   (and the child's own `tian status`/`tian notify` signal on self-verify) rather than hand-polling the
   pane in a loop.
3. **Read the session's self-verify report before reporting.** The appended coda makes the delegated
   session build, test, and self-check against the plan, then print a `===== TIAN SELF-VERIFY =====` block
   as the last thing it outputs — so it lands in the capture tail. Read that block: **never report success
   on a `fail`/`needs-attention` verdict or a red build/test.** Verify **from the report** (it also lists
   the commits the session made) — don't `cd` into the worktree and re-read the diff yourself; that just
   duplicates context the child already holds. (Self-verify is the only *required* verification right now.
   Deeper *independent* verification — a separate verifier session — is a planned later layer; writing or
   editing the implementation from this session stays forbidden either way.)
4. **The delegated session owns its commits; you own publishing.** The coda has it commit its own work
   in the worktree. **Never push, open a PR, or merge unless the user explicitly asks** — and never
   commit the child's work *for* it. Report what was done and verified; leave publishing to the user.
5. **Iterate through the live child — keep it alive.** Verification almost always surfaces follow-ups
   (test failures, GUI feedback, review fixes). Route every one of them to the **live** child via
   `tian pane send … --pane <claude_pane_id>` — it still has the full context loaded. **Do not** fix them
   yourself by editing/committing in the worktree (that re-absorbs the implementer role and races the
   child). Keep the child's Session/pane alive until verification **and** iteration are done; only then
   close it / `worktree remove`. If the child has already exited, re-delegate rather than freelancing.

If `final_state` is `needs_attention`, the session paused for input: read the capture, then either
answer it (`tian pane send … --pane <claude_pane_id>`) or surface the question to the user. The script
never removes the worktree, so the result stays available for your verification.

**Run log.** Every delegation appends one JSONL record (branch, `final_state`, elapsed, parsed
self-verify `verdict`/`build`/`tests`/`commits`, plus `child_session_id`/`parent_session_id`/`no_wait`)
to `~/.claude/tian/implement-runs.jsonl` (override with `$TIAN_IMPLEMENT_LOG`). Review the harness over
time — outcome mix, verdict rate, how often runs hit the ceiling as `running`, async fan-out share, and
whether the implementer committed its own work — with `python3 "<skill-dir>/implement-log.py"`
(flags: `--recent N`, `--branch SUBSTR`, `--since YYYY-MM-DD`).

### Parallel fan-out (independent slices)

A bare `implement.sh <branch>` **blocks** until its one child settles — correct for a single slice, but
it serializes work. When a milestone splits into **N genuinely independent slices** (disjoint files, no
ordering between them), fan them out instead:

1. Pick N branch names and write each slice's plan to its own file.
2. Fire each delegation with **`--no-wait`** — it creates the worktree, pastes + submits the plan, then
   returns immediately with `final_state=delegated` (no tracking loop):
   ```bash
   bash "<skill-dir>/implement.sh" feat/a --no-wait --prompt-file plan-a.md
   bash "<skill-dir>/implement.sh" feat/b --no-wait --prompt-file plan-b.md
   bash "<skill-dir>/implement.sh" feat/c --no-wait --prompt-file plan-c.md
   ```
3. **Await every child's durable done-signal** with `implement-wait.sh`, which blocks until each branch
   has a `source=self-verify` record in the run log, then prints a compact per-branch summary. It polls
   the **run log only** — never `tian pane capture`:
   ```bash
   bash "<skill-dir>/implement-wait.sh" --branch feat/a --branch feat/b --branch feat/c
   # add --since "$(date +%s)" before fan-out so a prior run's record can't satisfy the wait
   ```
4. Then read each child's **`TIAN SELF-VERIFY`** report (from the run log or each pane's capture tail) and
   verify from the report — same rules as the blocking path.

**Rule: one writer per branch; the orchestrator never edits or commits any worktree.** Each slice has
exactly one child that owns its files and its commits. Fan-out parallelizes *children*, not the
orchestrator's role — you still only read reports and route follow-ups via `tian pane send`.

### Long-session hygiene

Run **one orchestrator session per milestone**, and **compact/clear context between milestones**. The
orchestrator should hold only the plan and the children's self-verify reports — never worktree file
contents or diffs. Re-reading a child's files or running `git show`/`diff`/`log` on its worktree balloons
resident context (orchestrators have been observed at 200K+ tokens/turn for hundreds of turns doing
exactly this) and duplicates context the child already holds. If you need worktree state, ask the live
child via `tian pane send`; if a turn's context has drifted into the worktree, clear it and resume from
the plan + the run log.

## The model & "current" context

Every pane's shell has these env vars identifying where it lives:
`TIAN_WORKSPACE_ID`, `TIAN_SESSION_ID`, `TIAN_PANE_ID` (plus `TIAN_SOCKET` and `TIAN_CLI_PATH` for the CLI
itself).

Most commands **default to the current** workspace/session/pane via those vars, so you usually omit the
targeting flags. Pass an explicit `--workspace/--session/--pane <UUID>` only to act on something else.

- **Workspace** = one OS window. **Session** = one Claude pane + an optional terminal panel. **Pane** =
  one terminal surface (1:1 with a ghostty surface), arranged in a split tree.

### A Session = one Claude pane + a toggleable terminal panel

A Session pairs exactly two areas:
- **Claude pane** — exactly one, auto-seeded when the session is created. It is the session's primary AI
  pane and **cannot be split** (`pane split` on it fails with "Claude pane cannot be split.").
- **Terminal panel** — an optional shell area toggled with **Ctrl+`** (dock right or bottom, draggable
  divider). Hidden until first shown, and its panes **can** be split.

A Claude pane exit (its process quitting, or **⌘W** on it) **closes the whole session** — there's no
empty-session placeholder. A session's **name auto-derives** from the Claude pane title (falling back to
the working directory) unless it's renamed, so `session create`'s name argument is optional (omit it for
an auto-named session) and `session list` shows that display name in the `NAME` column.

This matters constantly: `pane list` tags each row with its `KIND` (claude or terminal), and **the pane
you drive a Claude session through is the `claude`-kind pane.** Address it directly with
`tian pane list --session <id> --kind claude` (or use the `claude_pane_id` a worktree create returns).

## Core rules

1. **Targeting is by UUID.** Discover IDs with a `list` command, or capture them from a `create`/`split`
   command — each prints the new entity's UUID to **stdout** (capture it: `id=$(tian pane split ...)`).
2. **Prefer `--background` when acting on the user's behalf.** `session create`, `pane split`, and
   `worktree create` all accept `--background` to create *without* stealing the user's keyboard focus.
   Default to it unless the user clearly wants to be switched over.
3. **Use `--format json`** for any `list` you intend to parse; the default is a human table.
4. **Don't close/force things blindly.** `close` cascades; `--force` overrides running-process safety
   checks. Only `--force` when the user asked or you created it yourself.
5. **Delegate coding to the new Session's Claude pane — don't freelance, ever.** Creating a worktree
   Session (via `worktree create` or `/tian implement`) means you delegate the work to **its** auto-seeded
   Claude pane. **Never `cd` into the worktree directory and edit or commit from the current session**
   — not for the initial task, and **not for follow-ups during the verify→iterate loop** (fixes, GUI
   feedback, review findings). Editing the worktree yourself leaves the child idle, duplicates its
   context, and races its commits. The terminal panel is for **shell commands only** (build, test, git
   *status/log*); for anything that changes code, `pane send` the work to the live child's
   `claude_pane_id` (or `/tian implement` for a fresh task). Keep the child alive until iteration is done;
   if it has exited, re-delegate rather than reaching in.

## Command reference

IDs below are UUIDs. `[...]` = optional. Defaults to the current context unless noted.

### Discovery
- `tian ping` → `pong` (connectivity check).
- `tian workspace list [--format json|table]` → ID, NAME, SESSIONS, ACTIVE.
- `tian session list [--workspace <id>] [--format ...]` → ID, NAME, STATE, PANES, ACTIVE. NAME is the
  session's display name (auto-derived from the Claude pane title unless renamed). STATE is the Claude
  session state of the session's Claude pane.
- `tian pane list [--session <id>] [--kind claude|terminal] [--format ...]` → ID, KIND, DIRECTORY, STATE,
  SESSION, LABEL, FOCUSED. Lists **both** the Claude pane and the terminal panel by default; `--kind`
  filters to one. (`STATE` is the process state; `SESSION` is the Claude session state.)

### Workspace (one per OS window)
- `tian workspace create <name> [--directory <path>]` → prints UUID.
- `tian workspace focus <id>`
- `tian workspace close <id> [--force]`

### Session (one Claude pane + optional terminal panel)
- `tian session create [<name>] [--workspace <id>] [--background]` → prints UUID. `<name>` is optional —
  omit it for an auto-named session.
- `tian session focus <id> [--workspace <id>]`
- `tian session close <id> [--workspace <id>] [--force]`

### Pane
- `tian pane split [--pane <id>] [--direction horizontal|vertical] [--background]` → prints new pane UUID.
  **Only terminal-panel panes can split** — splitting the Claude pane fails ("Claude pane cannot be
  split.").
- `tian pane focus <target> [--pane <id>]` — `<target>` is a pane UUID **or** a direction
  `up|down|left|right` (spatial neighbor of the source pane).
- `tian pane close [--pane <id>]`
- `tian pane send <text> [--pane <id>] [--no-enter]` — type/paste into a pane's terminal. Delivered via
  the **bracketed-paste path**, so multi-line text and interactive programs (a Claude session, a shell
  line editor) receive it as one paste, not line-by-line. Submits with Enter by default; `--no-enter`
  stages it without submitting. Pass `-` as the text to read from **stdin**.
- `tian pane capture [--pane <id>] [--scrollback] [--no-strip]` — print a pane's screen to stdout. Default
  is the visible viewport with ANSI stripped; `--scrollback` includes full history (may truncate to
  ~900 KB), `--no-strip` keeps escape sequences.
- `tian pane set-restore-command --command <cmd>` — command to replay when this pane is restored.

### Worktree-backed sessions (git)
- `tian worktree create <branch-name> [--existing] [--base <ref>] [--background] [--path <repo>] [--workspace <id>] [--format id|ids|json]`
  Creates a **git worktree** + a Session wired to it. `--existing` checks out an existing branch instead of
  creating one. `--base <ref>` creates the new branch from `<ref>` (branch/tag/commit) instead of current
  HEAD (invalid with `--existing`). This is git-mutating and can be slow (long timeout). Output by format:
  - `id` → the session UUID. `ids` → `<session-id> <claude-pane-id> <terminal-pane-id>`.
  - `json` → `session_id`, `claude_pane_id`, `terminal_pane_id`, and `existed`. Use `claude_pane_id` to
    drive the session's auto-seeded **Claude pane**.
- `tian worktree remove <session-id> [--force] [--delete-branch]` — removes the session and its git
  worktree; `--force` if dirty. `--delete-branch` also deletes the backing branch (`git branch -d`, or
  `-D` with `--force`); an unmerged branch is kept (the worktree is still removed) and the CLI reports it.

### Delegation orchestrator (bundled script — backs `/tian implement`)
- `bash "<skill-dir>/implement.sh" <branch> [options]` — end-to-end "delegate a task to a fresh worktree
  Session's Claude pane and wait for it to finish". It is pure orchestration over the existing CLI
  primitives — `worktree create` → `pane capture` (boot wait) → `pane send` (delegate) → `pane list`
  (track `sessionState`) — and adds **no** new binary subcommands or IPC. `<skill-dir>` is the directory
  holding this `SKILL.md`. Reads the plan from `--prompt-file <f>` or **stdin**. Options:
  - `--base <ref>` / `--existing` / `--path <repo>` / `--workspace <id>` — passed straight through to
    `worktree create`.
  - `--foreground` — create in the foreground (default is **background**, no focus steal).
  - `--no-wait` — **async fan-out**: paste + submit the plan, then return immediately with
    `final_state=delegated` (skip the tracking loop). Await the child's done-signal with
    `implement-wait.sh` instead. Use for N independent slices (see **Parallel fan-out** in Mode: implement).
  - `--prompt-file <f>` — plan source (else read from stdin; a TTY with no file is an error).
  - `--timeout <sec>` (default `5400`) — overall ceiling for the post-delegation wait.
  - `--boot-timeout <sec>` (default `60`) — ceiling for the Claude pane to boot.

  Prints `session_id` / `claude_pane_id` / `terminal_pane_id` / `final_state`, then a capture tail. The
  script appends a **mandatory self-verify coda** to the delegated plan, so the session builds/tests/
  plan-checks its own work and prints a `TIAN SELF-VERIFY` block into that capture tail. Exit `0` at
  `idle`, `needs_attention` (the latter also prints a `NOTE:` line), or `delegated` (`--no-wait`);
  non-zero on any hard failure or timeout. It does **not** remove the worktree — read the self-verify
  block before reporting (see **Mode: implement**).
- `bash "<skill-dir>/implement-wait.sh" --branch <b> [--branch <b2> ...] [--since <epoch>] [--timeout <sec>] [--log <path>] [--poll <sec>]`
  — the await primitive for `--no-wait` fan-out. Blocks until each named branch has a `source=self-verify`
  record in the run log (the child's durable done-signal), then prints `branch  verdict  build  tests
  (N commits)` per branch. Polls the **run log only** — never `tian pane capture`. `--since <epoch>`
  ignores records older than a cutoff (pass `$(date +%s)` captured *before* fan-out so a prior run can't
  satisfy the wait). Exit `0` when all branches are satisfied; `4` on timeout (still prints what arrived).

### Status, notifications, misc
- `tian status set [--label <text>] [--state active|busy|idle|needs_attention|failed|inactive]` — sidebar
  status for the current pane (at least one of `--label`/`--state`). `tian status clear` removes the label.
- `tian notify <message> [--title <t>] [--subtitle <s>]` — macOS notification (fires even when tian is
  backgrounded). Good for "long task done".
- `tian git refresh` — evict the PR cache and refresh the current session's git/PR sidebar badge after a
  change that doesn't touch local refs (e.g. `gh pr create` on an already-pushed branch).
- `tian config auto-set [--force] [--model <m>]` — generate `.tian/config.toml` for the current repo via
  `claude -p`. `tian open` — launch/focus the app.

## Recipes

**Inspect the current layout before acting**
```bash
tian session list; tian pane list --format json
```

**Delegate a task to a fresh worktree Session's Claude pane and wait for it (the easy way)**
```bash
# /tian implement runs exactly this. Plan from a file (or pipe it on stdin).
bash "<skill-dir>/implement.sh" feat/login --prompt-file plan.md
# Blocks until the delegated session settles, then prints session_id / claude_pane_id /
# terminal_pane_id / final_state + a capture tail. Read the child's self-verify report before
# reporting; the worktree is left in place for that.
```

**…the same thing by hand (under the hood — this is what `implement.sh` automates)**
```bash
# json gives you the Claude pane (claude_pane_id), not just the terminal shell.
out=$(tian worktree create feat/login --background --format json)
claude_pane=$(printf '%s' "$out" | jq -r .claude_pane_id)
# The Claude pane takes a few seconds to boot — poll it until ready.
until tian pane capture --pane "$claude_pane" | grep -q 'Claude Code'; do sleep 1; done
tian pane send 'run the test suite and summarize any failures' --pane "$claude_pane"
# ...later:
tian notify 'feat/login: done' --title tian
```
Use `--existing` to attach to a branch that already exists. To run shell commands in the same Session
instead, target its terminal pane: `read session_id claude_pane terminal_pane < <(tian worktree create …
--format ids)` then `tian pane send 'npm install && npm test' --pane "$terminal_pane"`. (Run *commands*
there — don't implement the task yourself in that shell; that's the delegated Claude pane's job. See Core
rule 5.)

**Split the terminal panel and run a dev server beside your work**
```bash
server=$(tian pane split --direction vertical --background)
tian pane send 'npm run dev' --pane "$server"
```

**Drive another agent/terminal session and read its result**
```bash
tian pane send 'summarize the failing test and propose a fix' --pane "$other"
sleep 3
tian pane capture --pane "$other" --scrollback   # read what it produced
```

**Report progress to the sidebar while a long task runs**
```bash
tian status set --label 'building…' --state busy
make release
tian status clear
tian notify 'Release build complete' --title tian
```

## Gotchas

- **Not inside tian → nothing works** except `tian open`. Confirm with `tian ping`.
- **Capture create output.** New UUIDs go to stdout; if you don't capture them you'll have to `list` to
  find the thing you just made.
- **`--background` is usually the polite choice** when you create on the user's behalf — otherwise you
  yank their focus to a new session/pane.
- **Stale env IDs.** `TIAN_{WORKSPACE,SESSION}_ID` can go stale if the user moves a session to a different
  workspace after the shell started; the IPC handler returns an error on mismatch. Panes created by
  `pane split` get fresh, correct IDs.
- **`pane send` ≠ exec.** It pastes keystrokes into whatever is running in that pane; there's no remote
  shell. Use `--no-enter` to stage input you don't want submitted yet.
- **A worktree hands you both a Claude pane and a terminal pane — so don't freelance.** `--format ids`
  prints `<session-id> <claude-pane-id> <terminal-pane-id>`, and `--format json` gives the same as
  `claude_pane_id` / `terminal_pane_id`. The Claude pane is the session's auto-seeded AI pane — delegate
  the work there. The terminal pane is for running *commands* (build/test/git), **not** for you to
  implement the task in. After `worktree create` / `/tian implement`, **never `cd` into the worktree and
  code from this session**; delegate to the new Session's Claude pane (prefer `/tian implement`). See
  **Core rule 5**.
- **The Claude pane boots slowly.** After `worktree create`, its `claude_pane_id` pane needs a few
  seconds before it accepts input — poll `tian pane capture --pane <claude_pane>` until `grep -q 'Claude
  Code'`, then `pane send`. Don't launch your own `claude`; the session already has one. Use the `KIND`
  column from `pane list` (or a pane's `SESSION` state) to tell the Claude pane from a terminal shell.
- For exact, current flags on any command: `tian help <subcommand>` (e.g. `tian help pane send`).
