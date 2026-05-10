# tian

A native macOS terminal emulator built with SwiftUI, embedding [Ghostty](https://ghostty.org/) as its terminal core.

Ghostty handles the PTY, VT parsing, Metal rendering, font atlas, cursor, selection, scrollback, and color themes. tian wraps it in a native macOS shell with a 4-level workspace model and a CLI for scripting the UI from inside your shell.

## Concepts

tian organizes terminals in four levels:

```
Workspace → Space → Tab → Pane (split tree)
```

- **Workspace** — top-level unit, one per OS window. Has a name and a default working directory.
- **Space** — a named group of tabs inside a workspace, similar to virtual desktops.
- **Tab** — a single tab inside a space, owning a split tree of panes.
- **Pane** — a single terminal session, mapped 1:1 to a Ghostty surface. Splits horizontally or vertically.

## Requirements

- macOS 26
- Xcode 26.3
- [`zig`](https://ziglang.org/) (`brew install zig`) — required to build Ghostty
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — generates the Xcode project

## Build & install

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
| New tab | `⌘T` |
| Next / previous tab | `⌘⇧]` / `⌘⇧[` |
| Jump to tab _n_ | `⌘1` … `⌘9` |
| New space | `⌘⇧T` |
| Next / previous space | `⌘⇧→` / `⌘⇧←` |
| New workspace (window) | `⌘⇧N` |
| Close workspace | `⌘⇧⌫` |
| Toggle sidebar | `⌘⇧S` or `⌘⇧W` |
| Focus sidebar | `⌘0` |
| Toggle terminal section | `⌃` `` ` `` |
| Cycle section focus | `⌘⇧` `` ` `` |
| Toggle debug overlay | `⌘⇧P` |

## `tian` CLI

Each pane runs with `TIAN_SOCKET`, `TIAN_PANE_ID`, `TIAN_TAB_ID`, `TIAN_SPACE_ID`, and `TIAN_WORKSPACE_ID` set, letting the bundled `tian` CLI talk to the running app over a Unix socket.

```sh
tian ping                  # check the connection
tian workspace …           # workspace commands
tian space …               # space commands
tian tab …                 # tab commands
tian pane …                # pane commands
tian status …              # surface status
tian worktree …            # git worktree helpers
tian git …                 # git helpers
tian notify …              # send a notification
tian config …              # read/write config
```

The CLI only works from inside a tian terminal session — it errors out cleanly if `TIAN_SOCKET` is not set. Run `tian <command> --help` for subcommand details.

## Logs

File-logged categories (`ipc`, `lifecycle`, `persistence`, `git`) write to `~/Library/Logs/tian/tian.log` (rotated to `tian.1.log`). Other categories (`core`, `view`, `ghostty`, `perf`, `worktree`) go to unified logging:

```sh
log stream --predicate 'subsystem == "com.tian.app"'
```

## Project layout

- `tian/` — app source (Workspace, Tab, Pane, Core, View, Input, Persistence, …)
- `tian-cli/` — `tian` CLI source (Swift, ArgumentParser)
- `tianTests/` — unit tests
- `scripts/` — build, ghostty, install
- `docs/` — feature specs and design docs
- `tian/Vendor/` — `GhosttyKit.xcframework` + `ghostty.h` (built via `scripts/build-ghostty.sh`)
- `.dev/tmp/` — gitignored scratch space for experiments

See [`CLAUDE.md`](CLAUDE.md) for deeper architecture notes.
