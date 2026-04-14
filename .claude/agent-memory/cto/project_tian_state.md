---
name: tian project state
description: Current state of tian project - M7 polish implemented, sidebar redesign complete, CLI tool implemented, worktree spaces spec written.
type: project
---

As of 2026-04-09, tian has working code through M7 (daily driver polish). 60+ Swift source files across App/, Core/, DragAndDrop/, Input/, Models/ (rename to Workspace/ pending), Pane/, Persistence/, Tab/, Utilities/, View/, WindowManagement/, Worktree/ directories. The workspace sidebar redesign is implemented (glassmorphism sidebar with disclosure groups, keyboard navigation). CLI tool is fully implemented with IPC over Unix domain socket.

**Current architecture:** SwiftUI app with NSWindow per workspace. WorkspaceWindowController manages windows with NSEvent keyboard monitor for shortcuts. WorkspaceWindowContent -> SidebarContainerView -> SidebarPanelView + terminal ZStack. GhosttyTerminalSurface wraps ghostty_surface_t for terminal rendering. Observable models: WorkspaceManager -> WorkspaceCollection -> Workspace -> SpaceCollection -> SpaceModel -> TabModel -> PaneViewModel -> SplitTree. ProcessDetector for running process checks. Session persistence via SessionSerializer/SessionRestorer (currentVersion=1).

**CLI tool implemented:** tian-cli binary with ArgumentParser. IPC over Unix domain socket at $TMPDIR/tian-<uid>.sock. Commands: workspace.create/list/close/focus, space.create/list/close/focus, tab.create/list/close/focus, pane.split/list/close/focus, status.set/clear, notify. Environment injection via ghostty_surface_config_s.env_vars.

**Worktree Spaces spec written:** docs/feature/worktree-spaces/worktree-spaces-spec.md v1.0. 9 implementation phases. Key technical decisions: TOMLKit for TOML parsing, ghostty_surface_text() for command injection, OSC 7 (surfacePwdNotification) for shell readiness, incremental split approach for layout application preserving initial pane session. Schema version bumps from 1 to 2 for worktreePath persistence.

**Sidebar git status implemented:** SpaceGitContext, GitStatusService, GitRepoWatcher, PRStatusCache all implemented. SidebarSpaceRowView shows repo status lines with branch, diff badges, PR indicators. Claude session dots display per-pane via ClaudeSessionDotsView/BusyDotView/SpaceStatusAreaView.

**Claude Session Status mostly implemented:** ClaudeSessionState enum, PaneStatusManager.sessionStates, IPCCommandHandler.handleStatusSet with --state support, and sidebar dot views all exist. Remaining gaps: CLI --state flag missing, BusyDotView uses rainbow spin instead of opacity pulse, Reduce Motion not respected, status label hidden when sessions present.

**Why:** Claude Session Status spec (docs/feature/claude-session-status/claude-session-status-spec.md) covers only the remaining gaps (4 phases).

**How to apply:** Most of the feature is already working. Implementation only needs: CLI flag addition, BusyDotView animation change, SpaceStatusAreaView label coexistence fix.
