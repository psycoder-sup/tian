# PRD: Worktree Spaces

**Author:** psycoder
**Date:** 2026-04-07
**Version:** 1.3
**Status:** Approved

---

## 1. Overview

Worktree Spaces is an tian feature that automates the creation of git worktree-backed development environments. When triggered, tian creates a new git worktree on disk, creates a new Space pointed at that worktree directory, copies specified environment files from the main worktree, runs setup scripts, and applies a predefined pane layout with startup commands. The feature is driven by a per-project configuration file (`.tian/config.toml`) checked into the repository root. When a worktree Space is closed, tian offers to remove the associated worktree from disk, completing the lifecycle. The feature is available both as a built-in app command (keyboard shortcut, sidebar context menu) and as a CLI command (`tian-cli worktree create`) over the existing IPC system.

---

## 2. Problem Statement

**User Pain Point:** When a developer needs to work on a new branch in parallel -- a hotfix, a code review, or an experimental feature -- they must manually perform a sequence of steps: run `git worktree add`, copy `.env` files and other untracked configuration, run setup scripts (`npm install`, `bundle install`, etc.), create a new Space in tian, and manually split panes and run startup commands (server, watcher, test runner). This sequence is error-prone (forgetting to copy `.env` breaks the app, forgetting a setup step wastes debugging time) and slow enough to discourage parallel work.

**Current Workaround:** Developers either (a) run all these steps manually each time, (b) maintain personal shell scripts that partially automate the sequence but have no integration with tian's Space model, or (c) avoid parallel worktrees altogether and use `git stash` / branch switching instead, losing the ability to keep multiple branches open simultaneously.

**Business Opportunity:** tian's 4-level hierarchy explicitly maps Space to "branch/worktree" (per the main PRD and the project memory). Today, creating a worktree-backed Space requires manual coordination between git, the filesystem, and tian's UI. Automating this sequence makes the Space-as-worktree concept a first-class, one-command workflow -- the primary differentiator that justifies tian's hierarchy over a flat tab model. It transforms the conceptual model into a practical daily-driver feature.

---

## 3. User Stories

| # | As a... | I want to... | So that... |
|---|---------|--------------|------------|
| 1 | developer | press a shortcut or run a CLI command to create a new worktree-backed Space with one action | I can start working on a new branch in parallel without manual setup steps |
| 2 | developer | define which env files to copy and which setup scripts to run in a project config file | every worktree I create is correctly configured without remembering the steps |
| 3 | developer | define a pane layout (splits, sizes, startup commands) in the config file | my new worktree Space opens with my preferred development environment (e.g., editor + server + test runner) already running |
| 4 | developer | close a worktree Space and have tian clean up the worktree directory on disk | I don't accumulate stale worktree directories that I have to manually prune |
| 5 | developer | run `tian-cli worktree create` from a script or AI agent within tian | worktree creation can be automated as part of larger workflows (e.g., Claude Code setting up a review environment) |

---

## 4. Functional Requirements

### Configuration File

**FR-001:** tian must look for a per-project worktree configuration file at `.tian/config.toml` relative to the git repository root of the current Space's working directory. This file defines env file copy rules, setup scripts, and the default pane layout for new worktree Spaces in that repository.

**FR-002:** If no `.tian/config.toml` file exists in the repository root, the worktree creation flow must still function -- it creates the worktree and Space with a single pane and no file copying or setup scripts. The config file enhances the flow but is not required.

**FR-003:** The configuration file must support specifying env files to copy as a list of source-destination pairs, where paths are relative to the repository root. Glob patterns must be supported for the source path (e.g., `.env*` to match `.env`, `.env.local`, `.env.development`).

**FR-004:** The configuration file must support specifying an ordered list of setup commands. Each command is a shell string executed via the user's default shell in the new worktree directory. See FR-012 for execution behavior.

**FR-005:** The configuration file must support a layout definition that specifies the split structure, size ratios, and startup commands for each pane in the first tab of the new worktree Space. The layout definition must support horizontal and vertical splits, nesting to arbitrary depth, and a ratio (0.0-1.0) for each split.

### Worktree Creation

**FR-006:** When triggered, tian must prompt the user for a branch name (or accept it as a CLI argument). The branch name is used as both the git worktree branch name and the Space name.

**FR-007:** tian must determine the git repository root from the current Space's working directory (or from a CLI-provided path). If the current directory is not inside a git repository, the operation must fail with a clear error message.

**FR-008:** tian must create the git worktree by running `git worktree add <worktree-path> -b <branch-name>` (new branch) or `git worktree add <worktree-path> <existing-branch>` (existing branch). The user must be able to specify whether to create a new branch or check out an existing one.

**FR-009:** The worktree directory must be created at `<repo-root>/.worktrees/<branch-name>` by default. This path must be configurable in `.tian/config.toml` via a `worktree_dir` setting (relative to repo root).

**FR-010:** After the worktree is created on disk, tian must copy all files matching the env file rules defined in FR-003 from the git repository's **main worktree** to the new worktree, preserving relative paths. The main worktree path must be resolved by parsing the output of `git worktree list --porcelain` (the first listed worktree is the main worktree), NOT derived from the current Space's working directory. This ensures consistent env files regardless of which Space triggers the creation.

**FR-011:** After file copying, tian must create a new Space in the current Workspace with a **single pane**. The Space's `defaultWorkingDirectory` must be set to the new worktree path. The Space name must be set to the branch name. tian must activate (focus) the new Space immediately so the user can see setup output in real time.

**FR-012:** After the single-pane Space is visible, tian must execute each setup command defined in FR-004 sequentially **inside the visible pane** (typed into the terminal per FR-028), so the user can observe output in real time. tian waits for shell readiness (FR-028) between each command before typing the next. tian does not attempt to detect exit codes from interactively-typed commands. If the user observes a failure, they can cancel remaining setup via the cancel button or Ctrl+C (FR-014). The Space remains open so the user can debug.

**FR-013:** After all setup commands complete successfully (or if no config file exists), tian must apply the layout defined in the config file to the first tab. This means constructing the `SplitTree` with the specified split structure and ratios, and sending each pane's startup command to its terminal after shell readiness is detected (per FR-028). If setup was cancelled (FR-014), layout application still proceeds.

**FR-014:** During setup command execution (FR-012), the user must be able to cancel remaining setup via two mechanisms: (1) a small floating cancel button overlaid on the pane (e.g., bottom-right corner), and (2) Ctrl+C. If Ctrl+C is pressed during setup, it cancels the currently running command AND skips all remaining setup commands, proceeding directly to layout application (FR-013). The floating cancel button behaves identically (skips all remaining setup commands). The worktree and Space are preserved.

### Worktree Cleanup

**FR-015:** When a worktree-backed Space is closed (via sidebar, keyboard shortcut, or CLI), tian must offer to remove the associated git worktree from disk. The user must be presented with a confirmation that includes the worktree path and branch name.

**FR-016:** If the user confirms cleanup, tian must run `git worktree remove <worktree-path>` to cleanly remove the worktree. If the worktree has uncommitted changes, `git worktree remove` will fail; tian must surface this error and offer a force option (`git worktree remove --force`).

**FR-017:** tian must track the association between a Space and its worktree path so that cleanup can be offered on Space close. This association must persist across app launches (via the existing session persistence system).

### CLI Surface

**FR-018:** The CLI must support a `worktree create` subcommand: `tian-cli worktree create <branch-name> [--existing] [--path <repo-path>]`. The `--existing` flag checks out an existing branch instead of creating a new one. The `--path` flag overrides the repository root detection (defaults to the current Space's working directory via `TIAN_SPACE_ID`).

**FR-019:** The CLI must support a `worktree remove` subcommand: `tian-cli worktree remove <space-id> [--force]`. This closes the Space and removes the worktree from disk. The `--force` flag bypasses the uncommitted-changes check.

**FR-020:** The CLI `worktree create` command must return the Space UUID on success, enabling scripts to chain subsequent commands (e.g., `tian-cli space focus <id>`). The response must include an `"existed": boolean` field indicating whether the Space was newly created or an existing duplicate was focused (per FR-027).

**FR-021:** The CLI commands must use the existing IPC system (Unix domain socket, `IPCRequest`/`IPCResponse` protocol). New IPC commands: `worktree.create` and `worktree.remove`.

### App UI Surface

**FR-022:** The app must provide a keyboard shortcut for creating a worktree Space. The shortcut must be added to the `KeyAction` enum and registered in `KeyBindingRegistry` (configurable in M6).

**FR-023:** The sidebar context menu for workspace headers must include a "New Worktree Space..." option that triggers the same flow as the keyboard shortcut.

**FR-024:** When triggered via the app (shortcut or context menu), tian must present a minimal input UI for the branch name and a toggle for "existing branch" vs. "new branch". This UI should not block the terminal -- it can be a popover, sheet, or inline sidebar input.

### Metadata and Persistence

**FR-025:** The `SpaceModel` must be extended with an optional `worktreePath: URL?` property that stores the filesystem path of the associated worktree. When non-nil, this identifies the Space as worktree-backed and enables cleanup on close.

**FR-026:** The `SpaceState` persistence model must include the worktree path so the association survives app restarts. On restore, if the worktree directory no longer exists on disk, the Space must be restored as a normal (non-worktree) Space with a warning logged. Note: Adding the `worktreePath` field to `SpaceState` requires incrementing the `SessionStateMigrator` schema version (currently at `SessionSerializer.currentVersion`) and adding a migration step for the new field.

### Duplicate Space Detection

**FR-027:** When a worktree Space creation is requested, tian must check all existing Spaces for a matching `worktreePath`. If a Space with the same worktree path already exists, tian must **focus that Space** instead of creating a new one. The IPC response must return the existing Space's UUID with an `"existed": true` flag so callers can distinguish between newly created and already-existing Spaces.

### Shell Readiness Detection

**FR-028:** Before typing startup commands (layout `command` fields) or setup commands into a pane's terminal, tian must detect that the shell is ready. The primary signal is **OSC 7** (Operating System Command for current working directory notification), which modern shells emit after each prompt. If OSC 7 is not received within a configurable fallback delay, tian must proceed after that delay expires. The fallback delay must be configurable in `.tian/config.toml` via a `shell_ready_delay` setting (seconds, default: `0.5`).

### Worktree Cleanup: Directory Pruning

**FR-030:** After `git worktree remove` succeeds, tian must prune empty parent directories upward from the removed worktree path up to (but not including) the `worktree_dir` root. This handles branch names containing slashes (e.g., `feature/payment-api` creates `.worktrees/feature/payment-api/`): after removal, the empty `feature/` directory must be cleaned up. Non-empty parent directories must not be removed.

### Logging

**FR-031:** All worktree creation outcomes (success, failure at each stage -- git operations, file copy, setup commands, Space creation) must be logged via the existing `Logger` utility. Log entries must include the branch name, worktree path, and stage of failure if applicable. This enables post-hoc debugging of worktree creation issues.

### Initial Pane Reuse

**FR-032:** When applying the layout (FR-013), the initial pane (where setup commands ran) must be mapped to the **deepest first child** of the layout tree -- that is, the leftmost/topmost leaf node, found by traversing `first` children from the root. This is consistent with how `PaneViewModel.fromState` resolves focus. The startup command for that pane is still executed after the layout is applied and shell readiness is detected. Setup command output history remains visible in that pane because it is the same terminal session.

### Gitignore Management

**FR-033:** During worktree creation, tian must check the repository's `.gitignore` for the configured `worktree_dir` value (default: `.worktrees`). If the value is not already present, tian must append it to `.gitignore` with a preceding comment line `# tian worktree directory`. If `.gitignore` does not exist, tian must create it. This prevents worktree directories from being accidentally committed.

---

## 5. Non-Functional Requirements

**NFR-001:** Worktree creation (git operations + file copy + setup) must not block the main thread or freeze the UI. All git and filesystem operations must run asynchronously. The UI must show a progress indicator during creation.

**NFR-002:** File copy operations must handle permission errors and missing source files gracefully -- log a warning per failed file but continue with remaining files. Do not abort the entire worktree creation because one optional env file is missing.

**NFR-003:** The `.tian/config.toml` config file must be validated on read. Parsing errors must produce a clear, actionable error message including the line number and expected format. Invalid config must not prevent the basic worktree creation flow (FR-002 applies).

**NFR-004:** Setup commands must have a configurable timeout (default: 300 seconds per command). If a command exceeds the timeout, it must be killed and the flow must continue to layout application.

**NFR-005:** The feature must work correctly when the repository already has existing worktrees (created outside tian). It must not interfere with worktrees it did not create.

---

## 6. User Flow

### Happy Path: Create Worktree Space via Keyboard Shortcut

```
Precondition: User is in a Space whose working directory is inside a git repository.
              The repository contains `.tian/config.toml`.

1. User presses the worktree creation shortcut (e.g., Cmd+Shift+B).
2. tian presents a branch name input (popover or inline).
   - Text field for branch name (auto-focused).
   - Toggle: "New branch" (default) / "Existing branch".
   - Enter to confirm, Escape to cancel.
3. User types "feature/payment-api" and presses Enter.
4. tian checks for an existing Space with the same worktree path.
   - If found: focuses the existing Space and stops (FR-027).
5. tian shows a progress indicator in the sidebar area.
6. tian resolves the git repo root from the current Space's working directory.
7. tian reads and parses `.tian/config.toml` from the repo root.
8. tian runs: git worktree add .worktrees/feature/payment-api -b feature/payment-api
9. tian copies env files from the main worktree per config (e.g., .env, .env.local).
   Source is always the main worktree (resolved via `git worktree list --porcelain`).
10. tian creates a new Space named "feature/payment-api" in the current Workspace
    with a **single pane** and activates it immediately.
    - defaultWorkingDirectory = <repo-root>/.worktrees/feature/payment-api
    - worktreePath = <repo-root>/.worktrees/feature/payment-api
11. tian waits for shell readiness (OSC 7 or fallback delay per FR-028).
12. tian runs setup commands sequentially inside the visible pane (e.g., npm install).
    User sees output in real time. A floating cancel button is overlaid on the pane
    (bottom-right corner). The user can also press Ctrl+C to cancel the current command
    and skip remaining setup.
13. After setup completes (or is cancelled), tian applies the layout from config:
    - Constructs the SplitTree with specified structure and ratios.
    - Waits for shell readiness in each new pane (FR-028).
    - Sends startup commands to each pane's terminal.
14. User is now working in the new worktree with their configured layout.
```

### Happy Path: Close Worktree Space with Cleanup

```
Precondition: User has a worktree-backed Space (worktreePath is set).

1. User closes the Space (via sidebar context menu "Close Space" or CLI).
2. tian detects the Space has an associated worktree.
3. tian presents a confirmation dialog:
   "Remove worktree at .worktrees/feature/payment-api?"
   [Remove Worktree & Close] [Close Only] [Cancel]
4. User clicks "Remove Worktree & Close".
5. tian runs: git worktree remove .worktrees/feature/payment-api
6. tian prunes empty parent directories up to the worktree_dir root (FR-030).
   (e.g., removes empty .worktrees/feature/ after removing .worktrees/feature/payment-api)
7. tian removes the Space from the SpaceCollection.
8. Sidebar updates.
```

### Alternate Flows

- **No config file:** Steps 7, 9, 12, 13 are skipped. Space is created with a single pane at the worktree directory.
- **Existing branch:** Step 8 uses `git worktree add .worktrees/feature/payment-api feature/payment-api` (no `-b`).
- **CLI trigger:** Steps 1-3 are replaced by `tian-cli worktree create feature/payment-api`. Step 4 still applies (returns existing Space UUID with `"existed": true` if duplicate). No UI prompt for branch name.
- **Duplicate Space detected (step 4):** Existing Space is focused. CLI returns `{ "space_id": "<uuid>", "existed": true }`. Flow ends.
- **Setup cancelled (step 12):** Remaining setup commands are skipped. Flow proceeds to step 13 (layout application).

### Error States

- **Not a git repo:** "Not a git repository. Navigate to a project directory first." (Error displayed in UI or CLI stderr.)
- **Branch already exists (new branch mode):** "Branch 'feature/payment-api' already exists. Use --existing to check it out." (Offer to switch to existing-branch mode in UI.)
- **Worktree path already exists (no matching Space):** "Worktree directory already exists at .worktrees/feature/payment-api. A Space may already be using this worktree." (Offer to open existing worktree as a Space instead.)
- **Duplicate Space (matching worktreePath):** Not an error -- the existing Space is focused silently (FR-027).
- **Setup command failure:** tian does not detect setup command exit codes (commands are typed interactively). If the user observes a failure, they can cancel remaining setup via the floating cancel button or Ctrl+C (FR-014). The Space is already visible (FR-012) and layout application still proceeds (FR-013).
- **Uncommitted changes on remove:** "Cannot remove worktree: uncommitted changes. Force remove?" [Force Remove] [Cancel]
- **Config parse error:** "Error in .tian/config.toml line 12: expected string for 'source'. Proceeding without config." (Falls back to FR-002 behavior.)
- **Unhandled git errors:** Any git error from `git worktree add` (or `git worktree remove`) that is not covered by the cases above is surfaced verbatim to the user, alongside tian context: the branch name, worktree path, and the full command that was run. This ensures no git failure is silently swallowed.

### Loading States

- **During worktree + file copy (steps 5-9):** Sidebar shows a progress indicator next to the workspace header with a label like "Creating worktree...". The rest of the app remains interactive.
- **During setup (step 12):** The Space is already visible with a single pane. Setup command output streams in real time. A subtle indicator (e.g., sidebar badge or pane border highlight) signals that setup is in progress. A floating cancel button is overlaid on the pane (bottom-right corner); Ctrl+C also cancels setup.
- **During layout application (step 13):** Brief -- splits are created and startup commands are sent. No additional loading indicator is needed beyond the pane shells initializing.

---

## 7. Design Considerations

### Configuration File Format

The config file lives at `.tian/config.toml` in the git repository root. This keeps it version-controlled and project-specific while using the `.tian` directory as a namespace for future tian project-level config.

Example:

```toml
# .tian/config.toml

# Worktree Spaces configuration

# Where to create worktrees (relative to repo root).
# Default: ".worktrees"
worktree_dir = ".worktrees"

# Timeout for each setup command in seconds. Default: 300
setup_timeout = 120

# Fallback delay (ms) for shell readiness detection when OSC 7 is not
# received. Default: 500
shell_ready_delay = 0.5

# Files to copy from the main worktree to each new worktree.
# Paths are relative to repo root. Source supports glob patterns.
[[copy]]
source = ".env"
dest = ".env"

[[copy]]
source = ".env.local"
dest = ".env.local"

[[copy]]
source = "config/credentials/*.yml"
dest = "config/credentials/"

# Setup commands to run in the new worktree directory (in order).
[[setup]]
command = "npm install"

[[setup]]
command = "npx prisma generate"

# Pane layout for the first tab.
# The layout is a tree of splits. Each split has a direction, ratio,
# and two children (which can be panes or nested splits).
[layout]
direction = "horizontal"
ratio = 0.65

[layout.first]
command = "nvim ."

[layout.second]
direction = "vertical"
ratio = 0.5

[layout.second.first]
command = "npm run dev"

[layout.second.second]
command = ""
```

This layout example produces:

```
+---------------------------+---------------+
|                           |  npm run dev  |
|          nvim .           |               |
|                           +---------------+
|                           |    (shell)    |
|          (65%)            |    (35%)      |
+---------------------------+---------------+
                            |  50%  |  50%  |
```

### Layout Specification Format

The layout uses TOML's nested table syntax to define a binary split tree that maps directly to tian's existing `PaneNode` / `SplitTree` model:

- A **pane** (leaf node) has an optional `command` field. If `command` is empty or omitted, the pane opens a plain shell.
- A **split** (internal node) has `direction` ("horizontal" or "vertical"), `ratio` (0.0-1.0), and two children: `first` and `second`. Each child is either a pane or another split.

The `direction` and `ratio` semantics match `SplitDirection` and `SplitTree` exactly:
- `"horizontal"` = left/right split (matching `SplitDirection.horizontal`)
- `"vertical"` = top/bottom split (matching `SplitDirection.vertical`)
- `ratio` = fraction of space allocated to the first child (matching the `ratio` parameter in `PaneNode.split`)

### Branch Name Input UI

The input should be lightweight -- either a popover anchored to the sidebar's "+" button or a sheet-style overlay. It should contain:
- A text field for the branch name, auto-focused on appear.
- A segmented control or toggle: "New branch" / "Existing branch".
- A description line showing the resolved repo and worktree path.
- Enter to confirm, Escape to dismiss.

This is consistent with the existing inline rename pattern used in `SidebarSpaceRowView` (lightweight, keyboard-driven, non-blocking).

### Sidebar Indicators

Worktree-backed Spaces should have a subtle visual indicator in the sidebar to distinguish them from regular Spaces. A small branch icon or a secondary label showing the worktree path suffix would work. This should be minimal -- the Space name (which is the branch name) already provides context.

### TOML Parser Dependency

This feature requires a TOML parser. A standalone Swift TOML library (e.g., TOMLKit or swift-toml) must be added as a dependency now. The planned M6 configuration system may consolidate TOML parsing later, but this feature should not wait for or depend on M6. If M6 introduces a different TOML library, the worktree config parsing can be migrated at that time.

### Command Execution for Startup and Setup Commands

Both setup commands (FR-012) and layout startup commands (FR-013) are **typed into the pane's terminal** after shell readiness is detected, simulating user input. This means each command appears in shell history and is visible in the terminal output. This is the simplest and most transparent approach -- the user sees exactly what was run.

Shell readiness is detected via **OSC 7** (the Operating System Command that modern shells emit after displaying a prompt, reporting the current working directory). This is the most reliable signal that the shell is ready for input. For shells that do not emit OSC 7, a configurable fallback delay (`shell_ready_delay` in the TOML config, default 500ms) is used.

The alternative (running commands as the shell's initial command via `-c` flag) would prevent the shell from being interactive after the command finishes if the command is not backgrounded. Typing the command avoids this.

### Setup UX: Visible Execution

Setup commands run inside the already-visible single-pane Space (not in a background process). This means:
- The user sees `npm install` output scrolling in real time, just as if they typed it.
- If setup hangs or produces unexpected output, the user can observe and react.
- The cancel mechanism (floating cancel button on the pane, or Ctrl+C) skips remaining setup commands and proceeds to layout application.
- After setup completes, the single pane is replaced by the configured layout. The initial pane's terminal is reused as the deepest first child of the layout tree (FR-032), preserving setup output history.

### Layout Application

When applying the layout from config (FR-013), the `SplitTree` should be constructed using the same pattern as `PaneViewModel.fromState()` -- building the tree from a declarative state description. This keeps layout application consistent with session restore.

---

## 8. Out of Scope

- **Worktree listing/browsing UI:** v1 does not include a dedicated view to browse all git worktrees for a repository. Worktree Spaces appear as regular Spaces in the sidebar.
- **Automatic branch detection:** tian does not watch for branch changes or auto-create Spaces. All worktree creation is user-initiated.
- **Worktree templates:** No support for multiple named layout/setup configurations per project. v1 has a single configuration per repository.
- **Remote repository support:** The feature assumes a local git repository. SSH or HTTP remote operations (e.g., fetching a remote branch before creating a worktree) are not handled.
- **Bare repository support:** `git worktree add` from a bare repository has different semantics. v1 assumes a standard (non-bare) repository.
- **Layout editing UI:** The pane layout is defined in TOML only. No graphical layout editor.
- **Config file creation wizard:** The user writes `.tian/config.toml` manually. No interactive setup.
- **Worktree Space conversion:** Cannot convert an existing Space into a worktree-backed Space or vice versa.
- **Cross-workspace worktrees:** A worktree Space is always created in the current Workspace. No support for creating it in a different Workspace.

---

## 9. Success Metrics

Since tian is a personal tool (single developer, no telemetry), success is measured qualitatively:

- **Primary:** The developer uses Worktree Spaces as the default method for parallel branch work, replacing manual `git worktree add` + setup scripts.
- **Friction test:** Creating a new worktree-backed development environment takes one command / shortcut and under 30 seconds (including setup script execution for a typical project).
- **Reliability:** Worktree creation succeeds on the first attempt in >95% of cases (no silent failures, no corrupted state).
- **Cleanup hygiene:** Closing a worktree Space and confirming removal leaves no stale worktree directories on disk.
- **Persistence:** Worktree Spaces survive app restart with their worktree association intact.

---

## 10. Open Questions

No open questions remain.

**Resolved:**
- ~~OQ#1~~ Commands are typed into the terminal after shell readiness is detected (OSC 7 / fallback delay). See FR-028, Design Considerations.
- ~~OQ#2~~ tian auto-appends `worktree_dir` to `.gitignore` if not already present. See FR-033.
- ~~OQ#4~~ Duplicate Spaces are detected by matching `worktreePath`; existing Space is focused. See FR-027.
- ~~OQ#3~~ Detached HEAD support is out of scope for v1. Only named branches are supported.
- ~~OQ#5~~ Global timeout is sufficient for v1. Per-command overrides are not needed.
- ~~OQ#6~~ Standalone TOML dependency added now; M6 can consolidate later. See Design Considerations.

---

## 11. Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-04-07 | psycoder | Initial draft |
| 1.1 | 2026-04-07 | psycoder | Post-review revision: added duplicate Space detection (FR-027), shell readiness via OSC 7 (FR-028), CLI --socket flag (FR-029), directory pruning on cleanup (FR-030), logging requirement (FR-031), setup cancel mechanism (FR-014). Updated FR-010 (explicit main worktree source), FR-011/012/013 (create Space first, run setup visibly, then apply layout). Added TOML dependency requirement, SessionStateMigrator version note, PaneViewModel.fromState layout pattern note, TIAN_SOCKET limitation acknowledgment. Resolved OQ#1, OQ#4, OQ#6. |
| 1.2 | 2026-04-07 | psycoder | Targeted fixes: replaced Escape cancel with floating cancel button + Ctrl+C (FR-014). Added initial pane reuse as deepest first child of layout tree (FR-032). Softened FR-012 to remove unreliable exit code detection; setup uses sequential typing with shell readiness waits. Resolved OQ#2: tian auto-appends worktree_dir to .gitignore (FR-033). Added git error passthrough in error states. |
| 1.3 | 2026-04-07 | psycoder | Proofreading pass: fixed CLI binary name to `tian-cli` throughout. Removed `--socket` flag and FR-029 (CLI is internal-only). Renamed config file from `.tian/worktree.toml` to `.tian/config.toml`. Standardized timeout units to seconds (`shell_ready_delay = 0.5`). Fixed FR-004 timing wording. Resolved OQ#3 (detached HEAD out of scope) and OQ#5 (global timeout sufficient). All open questions now resolved. |
