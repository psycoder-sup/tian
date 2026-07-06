# tian

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A native macOS terminal emulator built with SwiftUI, embedding [Ghostty](https://ghostty.org/) as its terminal core — designed from the ground up for **running and managing many Claude Code sessions at once**.

Ghostty handles the PTY, VT parsing, Metal rendering, font atlas, cursor, selection, scrollback, and color themes. tian wraps it in a native macOS shell organized around Claude sessions: a sidebar that shows every session's live state at a glance, git-worktree-backed sessions for parallel work, and a `tian` CLI that lets a session (or Claude itself) script the UI from inside the shell.

![tian](docs/assets/main.png)

## Why tian

Running Claude Code across several projects and branches quickly outgrows a plain tabbed terminal — you lose track of which session is waiting on you, which is still working, and which finished. tian is built around that problem:

- **Every Claude session is a first-class object**, not just a tab of text. Each one is a sidebar row with a name, a live status dot, its git branch and diff, its latest prompt, and a badge for any background work still running.
- **See all sessions at a glance.** The sidebar and the Session Overview grid (`⌘⇧O`) surface the state of every session across every workspace, so a session that needs your input is visible even when its window isn't focused.
- **Never miss a "still working" session.** tian reads Claude Code's hooks — including its background subagents and `run_in_background` shells — so a session that has handed work to background tasks correctly reads **busy**, not idle.
- **Parallelize with git worktrees.** Spin up an isolated session on its own branch and worktree in one command, work several in parallel, and tear them down cleanly.
- **Scriptable from inside the shell.** The bundled `tian` CLI drives workspaces, sessions, panes, and status over a Unix socket — the same primitives the `/tian implement` agent-delegation workflow is built on.

## Concepts

tian organizes terminals in a two-level hierarchy built around Claude sessions:

```
Workspace → Session (Claude pane + optional terminal panel)
```

- **Workspace** — top-level unit, one per OS window (typically one project). Has a name, a default working directory, and a collection of sessions.
- **Session** — one Claude Code session, shown as a single sidebar row. Owns exactly one **Claude pane** (never splittable) plus an optional, toggleable **terminal panel** (`⌃` `` ` ``) docked to the right or bottom with a draggable divider. Its name auto-derives from the Claude pane's title (or the working-directory basename) until you rename it.
- **Pane** — a single terminal surface, mapped 1:1 to a Ghostty surface. The Claude pane is always a single leaf; the terminal panel's panes live in a binary split tree and **can** be split horizontally or vertically.

Sessions can nest: a session that spawns worker sessions (e.g. via `/tian implement`) becomes an orchestrator, and its children are shown indented beneath it in the sidebar.

## Managing many sessions

- **Sidebar** (`⌘⇧S` / `⌘⇧W` to toggle, `⌘0` to focus) — a left rail listing every workspace and the sessions inside it. The workspace holding the focused session auto-expands, and each session row shows, at a glance:
  - a **status dot** driven by Claude Code's state:
    - orange — needs attention (Claude is waiting on your input or a permission prompt)
    - green — active (Claude is responding)
    - animated spinner — busy (a long-running tool call, or background subagents/shells still running)
    - gray — idle (waiting between turns)
    - red — failed
  - the session's **git branch, diff badge, and PR status** (each worktree tracks its own)
  - a **background-activity badge** when subagents or `run_in_background` shells are still working
  - a free-form **status line** any session can set with `tian status set`

  Dots are sorted so a session that needs attention is visible even when its workspace is collapsed.

- **Session Overview** (`⌘⇧O`) — a full-screen grid of every session across every workspace, each card showing a live preview of the Claude pane, its latest prompt, its status, and any background activity. Fully keyboard-driven: arrows to select, Enter to jump in, Escape to dismiss. The card border encodes the session's Claude state.

- **Navigation** — jump to a session with `⌘1`…`⌘9`, step through them with `⌘⇧↑` / `⌘⇧↓` (across workspaces), rename the active one inline with `⌘R`, and drag sidebar rows to reorder workspaces.

## Claude Code integration

tian is wired to Claude Code so sessions report their own state into the UI:

- **State, prompt, and git tracking via hooks.** Panes launched inside tian run `claude` with a bundled settings file that registers `UserPromptSubmit` / `Stop` / `SubagentStop` / `PostToolUse` hooks. These feed the sidebar over the IPC socket — the status dot, the latest submitted prompt on the overview card, the working-directory-derived git branch, and a PR refresh after `gh pr` commands — with no configuration on your part.
- **Background-work awareness.** The `Stop` / `SubagentStop` hooks carry Claude's `background_tasks` snapshot, so tian knows when a "finished" turn still has subagents or background shells running and keeps the session marked busy (with a staleness fallback if a background task ends without a completion hook). `tian session list` reports the same state, so a script polling from the CLI agrees with the sidebar.
- **Worktree-backed sessions.** `tian worktree create <branch>` spins up a new session on its own `git worktree` and branch — optionally in the background — runs any per-repo setup commands, and nests it under the caller in the sidebar. `tian worktree remove` runs archive steps, removes the worktree, and optionally deletes the branch.
- **Agent delegation.** The `/tian implement` skill orchestrates worktree-backed *child* Claude sessions: it delegates a plan to each, polls session state until the work settles, and collects a structured self-verify report — all composed from the `tian` CLI primitives, with no bespoke IPC.

## Inspect panel

A right-side panel for the active session's working directory, with three tabs:

- **Files** — file tree with git status badges
- **Diff** — unified `git diff` against `HEAD`, with per-file additions/deletions
- **Branch** — local and remote branches with a commit graph

Toggle it with the icon on the trailing edge of the window; when hidden, only a thin rail remains. Git tabs populate only when the working directory is inside a git repo.

## Install

Download the latest signed and notarized DMG from the [releases page](https://github.com/psycoder-sup/tian/releases/latest), open it, and drag **tian.app** to **Applications**. macOS 26 on Apple Silicon only.

Optional verification:

```sh
shasum -a 256 -c tian-v*.dmg.sha256
spctl -a -t open --context context:primary-signature -v tian-v*.dmg
```

## Build from source

Requirements:

- macOS 26
- Xcode 26.3
- [`zig`](https://ziglang.org/) (`brew install zig`) — required to build Ghostty
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — generates the Xcode project

```sh
# 1. Build and vendor GhosttyKit.xcframework (run once, or after updating .ghostty-src)
scripts/build-ghostty.sh

# 2. Generate the Xcode project and build the app
scripts/build.sh Release          # or: scripts/build.sh Debug

# 3. Copy the built app to /Applications
scripts/install.sh
```

`project.pbxproj` is gitignored — on a fresh clone, run `xcodegen generate` (or `scripts/build.sh`) once before opening the project in Xcode. Never edit `project.pbxproj` by hand.

## Default key bindings

| Action | Shortcut |
| --- | --- |
| New session | `⌘⇧T` |
| Next / previous session | `⌘⇧↓` / `⌘⇧↑` |
| Jump to session _n_ | `⌘1` … `⌘9` |
| Rename active session | `⌘R` |
| Session overview grid | `⌘⇧O` |
| New workspace (window) | `⌘⇧N` |
| Close workspace | `⌘⇧⌫` |
| Toggle sidebar | `⌘⇧S` or `⌘⇧W` |
| Focus sidebar | `⌘0` |
| Toggle terminal panel | `⌃` `` ` `` |
| Cycle focus (Claude ↔ terminal) | `⌘⇧` `` ` `` or `⌘'` |
| Split terminal pane (horizontal / vertical) | `⌘⇧D` / `⌘⇧E` |
| Focus pane by direction | `⌘⌥←` / `⌘⌥→` / `⌘⌥↑` / `⌘⌥↓` |
| Close pane (Claude pane → closes the session) | `⌘W` |
| Toggle debug overlay | `⌘⇧P` |

`⌘T` is intentionally left unbound so it falls through to the shell.

## `tian` CLI

The app bundles a single `tian` command-line tool. `tian open` launches (or focuses) the app and works from any shell:

```sh
tian open                      # launch the app, or bring it to the front
```

Every pane runs with `TIAN_SOCKET`, `TIAN_PANE_ID`, `TIAN_SESSION_ID`, and `TIAN_WORKSPACE_ID` set, letting `tian` talk to the running app over a Unix socket to script the UI from inside your shell:

```sh
tian ping                      # check the connection
tian workspace …               # create / list / close / focus workspaces
tian session …                 # create / list / close / focus sessions
tian pane …                    # split / list / close / focus; send input; capture output
tian status …                  # set / clear a session's sidebar status label + state
tian prompt …                  # set the latest prompt shown on the overview card
tian activity …                # report outstanding background work (subagents / bg shells)
tian worktree …                # create / remove git-worktree-backed sessions
tian git …                     # refresh git-derived sidebar state
tian notify …                  # send a macOS notification
tian config …                  # read / write .tian/config.toml
```

Apart from `open`, these commands only work from inside a tian terminal session — they error out cleanly if `TIAN_SOCKET` is not set. Run `tian <command> --help` for subcommand details.

## Logs

File-logged categories (`ipc`, `lifecycle`, `persistence`, `git`) write to `~/Library/Logs/tian/tian.log` (rotated to `tian.1.log`). Other categories (`core`, `view`, `ghostty`, `perf`, `worktree`) go to unified logging:

```sh
log stream --predicate 'subsystem == "com.tian.app"'
```

## Project layout

- `tian/` — app source (Workspace, Session, Pane, Core, View, Input, Persistence, Worktree, …)
- `tian-cli/` — `tian` CLI source (Swift, ArgumentParser); built as the bundled `tian` command
- `tianTests/` — unit tests
- `scripts/` — build, ghostty, install
- `docs/` — feature specs, design docs, and live project status (`docs/pm/`)
- `tian/Vendor/` — `GhosttyKit.xcframework` + `ghostty.h` (built via `scripts/build-ghostty.sh`)
- `.dev/tmp/` — gitignored scratch space for experiments

See [`CLAUDE.md`](CLAUDE.md) for deeper architecture notes.

## License

tian is released under the [MIT License](LICENSE).

It embeds and links third-party software — Ghostty, Sparkle, and others — distributed under their own terms. See [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) for their licenses and attributions.
