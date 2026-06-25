---
name: tian-cli
description: >-
  Drive the tian terminal emulator from the shell with the `tian` CLI: create/focus/close/list
  workspaces, spaces, tabs, and panes; spin up git-worktree-backed spaces for a branch; split panes
  and run commands in them; send input to and capture output from other terminal or agent sessions;
  set the sidebar status label/state; and post macOS notifications. Use whenever you are inside a tian
  session (the TIAN_SOCKET env var is set) and the task involves arranging terminals, running work in
  another pane/tab/space, spawning a worktree for a task, or notifying on completion.
---

# Driving tian with the `tian` CLI

tian organizes terminals as **Workspace → Space → Tab → Pane**. The `tian` CLI controls the running app
over IPC. Use it instead of asking the user to click around.

## Preconditions

- Only works **inside a tian terminal session** — it needs `TIAN_SOCKET` (set automatically by the app).
  If `tian ping` doesn't print `pong`, you're not inside tian; stop and tell the user.
- The binary is `tian` (on `PATH`). Hooks/scripts can also use `$TIAN_CLI_PATH`.
- `tian open` launches or focuses the app and is the **only** command that works outside a tian session.

## The model & "current" context

Every pane's shell has these env vars identifying where it lives:
`TIAN_WORKSPACE_ID`, `TIAN_SPACE_ID`, `TIAN_TAB_ID`, `TIAN_PANE_ID`.

Most commands **default to the current** workspace/space/tab/pane via those vars, so you usually omit the
targeting flags. Pass an explicit `--workspace/--space/--tab/--pane <UUID>` only to act on something else.

- **Workspace** = one OS window. **Space** = a group of tabs. **Tab** = one tab (title from focused pane).
  **Pane** = one terminal session (1:1 with a ghostty surface), arranged in a split tree.

### Sections: every Space has a Claude tab AND a Terminal tab

A Space is split into two **sections**, each with its own tabs:
- **Claude section** — auto-seeded with one Claude session tab when the Space is created (this is the
  Space's primary AI session).
- **Terminal section** — your regular shell tabs.

This matters constantly: `tian tab list` / `pane list` tag each row with its `SECTION`, and **the pane a
fresh worktree hands you via `--format ids` is the Terminal-section *shell*, not the Claude session.** To
drive the auto-Claude session, target its pane specifically (see the worktree recipe).

## Core rules

1. **Targeting is by UUID.** Discover IDs with a `list` command, or capture them from a `create`/`split`
   command — each prints the new entity's UUID to **stdout** (capture it: `id=$(tian pane split ...)`).
2. **Prefer `--background` when acting on the user's behalf.** `space create`, `tab create`,
   `pane split`, and `worktree create` all accept `--background` to create *without* stealing the user's
   keyboard focus. Default to it unless the user clearly wants to be switched over.
3. **Use `--format json`** for any `list` you intend to parse; the default is a human table.
4. **Don't close/force things blindly.** `close` cascades; `--force` overrides running-process safety
   checks. Only `--force` when the user asked or you created it yourself.

## Command reference

IDs below are UUIDs. `[...]` = optional. Defaults to the current context unless noted.

### Discovery
- `tian ping` → `pong` (connectivity check).
- `tian workspace list [--format json|table]` → ID, NAME, SPACES, ACTIVE.
- `tian space list [--workspace <id>] [--format ...]` → ID, NAME, TABS, ACTIVE.
- `tian tab list [--space <id>] [--section claude|terminal] [--format ...]` → ID, SECTION, TITLE, PANES,
  ACTIVE. Lists **both** sections by default; `--section` filters. (`active` is per-section.)
- `tian pane list [--tab <id>] [--format ...]` → ID, SECTION, DIRECTORY, STATE, SESSION, LABEL, FOCUSED.

### Workspace (one per OS window)
- `tian workspace create <name> [--directory <path>]` → prints UUID.
- `tian workspace focus <id>`
- `tian workspace close <id> [--force]`

### Space (group of tabs)
- `tian space create [<name>] [--workspace <id>] [--background]` → prints UUID.
- `tian space focus <id> [--workspace <id>]`
- `tian space close <id> [--workspace <id>] [--force]`

### Tab
- `tian tab create [--space <id>] [--directory <path>] [--background]` → prints UUID.
- `tian tab focus <target>` — `<target>` is a tab UUID **or** a 1-based index `1`–`9`.
- `tian tab close [<id>] [--force]` (defaults to current tab).

### Pane
- `tian pane split [--pane <id>] [--direction horizontal|vertical] [--background]` → prints new pane UUID.
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

### Worktree-backed spaces (git)
- `tian worktree create <branch-name> [--existing] [--background] [--path <repo>] [--workspace <id>] [--format id|ids|json]`
  Creates a **git worktree** + a Space wired to it. `--existing` checks out an existing branch instead of
  creating one. This is git-mutating and can be slow (long timeout). Output by format:
  - `id` → the space UUID. `ids` → `<space> <terminalTab> <terminalPane>` (the Terminal-section shell).
  - `json` → all of the above **plus** `claude_tab_id` / `claude_pane_id` — the auto-seeded **Claude
    session** pane. Use `claude_pane_id` to drive the Space's Claude session.
- `tian worktree remove <spaceId> [--force]` — removes the space and its git worktree; `--force` if dirty.

### Status, notifications, misc
- `tian status set [--label <text>] [--state active|busy|idle|needs_attention|inactive]` — sidebar status
  for the current pane (at least one of `--label`/`--state`). `tian status clear` removes the label.
- `tian notify <message> [--title <t>] [--subtitle <s>]` — macOS notification (fires even when tian is
  backgrounded). Good for "long task done".
- `tian git refresh` — evict the PR cache and refresh the current Space's git/PR sidebar badge after a
  change that doesn't touch local refs (e.g. `gh pr create` on an already-pushed branch).
- `tian config auto-set [--force] [--model <m>]` — generate `.tian/config.toml` for the current repo via
  `claude -p`. `tian open` — launch/focus the app.

## Recipes

**Inspect the current layout before acting**
```bash
tian space list; tian tab list; tian pane list --format json
```

**Spin up an isolated worktree space and prompt its Claude session (don't steal focus)**
```bash
# json gives you the Claude session's pane (claude_pane_id), not just the terminal shell.
out=$(tian worktree create feat/login --background --format json)
claude_pane=$(printf '%s' "$out" | jq -r .claude_pane_id)
# The Claude session takes a few seconds to boot — poll its OWN pane until ready.
until tian pane capture --pane "$claude_pane" | grep -q 'Claude Code'; do sleep 1; done
tian pane send 'run the test suite and summarize any failures' --pane "$claude_pane"
# ...later:
tian notify 'feat/login: done' --title tian
```
Use `--existing` to attach to a branch that already exists. To run shell commands in the same Space
instead, target its Terminal pane: `read space tab pane < <(tian worktree create … --format ids)` then
`tian pane send 'npm install && npm test' --pane "$pane"`.

**Split the current pane and run a dev server beside your work**
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
  yank their focus to a new space/tab/pane.
- **Stale env IDs.** `TIAN_{WORKSPACE,SPACE,TAB}_ID` can go stale if the user drags a tab/space into a
  different container after the shell started; the IPC handler returns an error on mismatch. Panes created
  by `pane split` get fresh, correct IDs.
- **`pane send` ≠ exec.** It pastes keystrokes into whatever is running in that pane; there's no remote
  shell. Use `--no-enter` to stage input you don't want submitted yet.
- **A worktree's `--format ids` pane is the Terminal shell, not the Claude session.** Every Space has a
  Claude section (auto-Claude tab) and a Terminal section; `ids`/`id` and the default targeting reach the
  Terminal shell. To drive the auto-Claude session use `--format json` → `claude_pane_id`.
- **The Claude session boots slowly.** After `worktree create`, its `claude_pane_id` pane needs a few
  seconds before it accepts input — poll `tian pane capture --pane <claude_pane>` until `grep -q 'Claude
  Code'`, then `pane send`. Don't launch your own `claude`; the Space already has one. Use the `SECTION`
  column from `tab list`/`pane list` (or a pane's `sessionState`) to tell Claude panes from shells.
- For exact, current flags on any command: `tian help <subcommand>` (e.g. `tian help pane send`).
