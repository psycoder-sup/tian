---
name: aterm project context
description: Core product decisions for aterm - macOS terminal emulator built with Swift, libghostty, Metal. Personal tool for the developer.
type: project
---

aterm is a GPU-accelerated macOS terminal emulator. Key decisions: Swift + SwiftUI for app chrome, libghostty-vt (Zig, C ABI) for VT parsing/terminal state, Metal for GPU rendering (font atlas + instanced cell rendering), POSIX PTY. macOS 26+ only.

Primary differentiators: (1) 4-level workspace hierarchy (Workspace > Space > Tab > Pane) for project-oriented terminal management, (2) more customizable than Ghostty (themes, profiles, extensibility).

Workspace model: Workspace = project, Space = branch/worktree, Tab = standard tabs, Pane = splits. All persist across app launches. Navigation uses chord-based shortcuts (Cmd+Shift+...), no leader key.

v1 bar: full workspace/space/tab/pane model working + persistent sessions + fast GPU rendering. Must be daily-drivable before shipping.

Current navigation state (as of M4): Sidebar redesign implemented with glassmorphism sidebar (SidebarContainerView, SidebarPanelView, SidebarExpandedContentView, SidebarState). SidebarMode has expanded (284pt) and collapsed (0pt) modes. Sidebar shows workspace tree with disclosure groups and space rows. Old components (WorkspaceIndicatorView, SpaceBarView, WorkspaceSwitcherOverlay) still exist in codebase. Workspace sidebar redesign PRD v1.1 (Review status, 2026-04-01) at docs/feature/workspace-sidebar/workspace-sidebar-prd.md. Key decisions: each window's sidebar shows only its own workspace (no cross-window tree), Cmd+Shift+W repurposed as sidebar toggle, focus returns to terminal after sidebar interactions, "Set Default Working Directory" deferred to post-v1 (WORK-261).

IPC/CLI state (as of 2026-04-07): Full IPC infrastructure implemented. IPCServer (Unix domain socket), IPCCommandHandler with full CRUD for workspace/space/tab/pane, status set/clear, and notify. EnvironmentBuilder injects ATERM_SOCKET, ATERM_PANE_ID, ATERM_TAB_ID, ATERM_SPACE_ID, ATERM_WORKSPACE_ID, ATERM_CLI_PATH into every shell session. CLI tool PRD v1.2 (Approved, 2026-04-05) at docs/feature/cli-tool/cli-tool-prd.md. Key decisions: UUID-only targeting, single-window scope, env vars with stale caveat, sidebar status inline with space row, exit code 4 for notification permission denial, process safety checks at IPC handler level. No configuration system yet (TOML config is planned for M6 but not implemented).

Bundle ID: com.aterm.app. App is not sandboxed. XcodeGen project (project.yml).

**Why:** Ghostty lacks workspace/space concepts, has limited customizability, and no session persistence. Developer wants native macOS integration to replace tmux-style workflows.

Worktree Spaces PRD v1.1 (Draft, 2026-04-07) at docs/feature/worktree-spaces/worktree-spaces-prd.md. Feature automates git worktree creation + Space setup with per-project `.aterm/worktree.toml` config. Key decisions: config at `.aterm/worktree.toml` in repo root, layout spec maps directly to PaneNode/SplitTree binary tree model, worktree cleanup offered on Space close, CLI surface via `worktree.create`/`worktree.remove` IPC commands. Resolved: standalone TOML dependency (not waiting for M6), commands typed into terminal after OSC 7 shell readiness detection (fallback delay configurable), duplicate Spaces detected by worktreePath and focused instead of recreated. v1.1 additions: setup runs visibly in single-pane Space before layout application, cancel mechanism for setup, env files always copied from main worktree (via `git worktree list --porcelain`), empty parent dir pruning on cleanup, `--socket` CLI flag for external invocation, logging via Logger. Remaining open: .gitignore automation, detached HEAD support, per-command timeout overrides.

Claude Session Status PRD v1.3 (Approved, 2026-04-07) at docs/feature/claude-session-status/claude-session-status-prd.md. Feature extends existing `status.set` IPC command with optional `--state` parameter for typed Claude Code session states (active, busy, idle, needs_attention, inactive). Per-pane dots (~8pt circles), priority-sorted on Space row's second line, color-coded (green/blue/gray/orange). 6 Claude Code hooks map to state transitions. Key decisions: state and label are independent coexisting fields, no new IPC commands (extends status.set), no persistence across app restarts, aggregation at Space level only (not Workspace), no auto-focus on needs_attention in v1, busy dot uses mesh rainbow gradient with spinning animation (static under Reduce Motion).

Sidebar Git & Claude Session Status PRD v1.1 (Draft, 2026-04-08) at docs/feature/sidebar-status/sidebar-status-prd.md. Combines Claude session dots with git status integration on the Space row's status area. v1.1 key decisions: multi-repo support (one status line per distinct git repo when panes span multiple repos, Claude dots grouped by repo), working directory pinning (sticky git context prevents flickering on cd), worktree-aware git resolution via `git rev-parse --git-dir`/`--git-common-dir`, 60s TTL cache for `gh pr view` (FSEvents reuse cached PR during TTL), full FSEvents lifecycle management (start on git detection, stop on Space close, restart on repo change, watch worktree linked gitdir + main repo refs). Other: GitHub-only for PR in v1, no inline git actions, no workspace-level git aggregation, branch shown for all git-backed Spaces not just worktree ones.

**How to apply:** All feature planning should respect: macOS-only, keyboard-driven, no plugin system in v1, no telemetry. PRD lives at docs/feature/aterm/aterm-prd.md. Doc structure: docs/feature/[feature-name]/[feature-name]-prd.md.
