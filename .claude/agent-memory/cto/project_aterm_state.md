---
name: aterm project state
description: Current state of aterm project - M7 polish implemented, sidebar redesign complete, CLI tool implemented, worktree spaces spec written.
type: project
---

As of 2026-04-08, aterm has working code through M7 (daily driver polish) plus worktree spaces. 70+ Swift source files across App/, Core/, DragAndDrop/, Input/, Models/, Pane/, Persistence/, Tab/, Utilities/, View/, WindowManagement/, Worktree/ directories. The workspace sidebar redesign is implemented (glassmorphism sidebar with disclosure groups, keyboard navigation). CLI tool is fully implemented with IPC over Unix domain socket. Worktree spaces are implemented.

**Current architecture:** SwiftUI app with NSWindow per workspace. WorkspaceWindowController manages windows with NSEvent keyboard monitor for shortcuts. WorkspaceWindowContent -> SidebarContainerView -> SidebarPanelView + terminal ZStack. GhosttyTerminalSurface wraps ghostty_surface_t for terminal rendering. Observable models: WorkspaceManager -> WorkspaceCollection -> Workspace -> SpaceCollection -> SpaceModel -> TabModel -> PaneViewModel -> SplitTree. ProcessDetector for running process checks. Session persistence via SessionSerializer/SessionRestorer.

**CLI tool implemented:** aterm-cli binary with ArgumentParser. IPC over Unix domain socket at $TMPDIR/aterm-<uid>.sock. Commands: workspace.create/list/close/focus, space.create/list/close/focus, tab.create/list/close/focus, pane.split/list/close/focus, status.set/clear, notify, worktree.create/remove. Environment injection via ghostty_surface_config_s.env_vars.

**Sidebar Status spec written (2026-04-08):** docs/feature/sidebar-status/sidebar-status-spec.md v1.0. 8 implementation phases. Key technical decisions: SpaceGitContext per SpaceModel for repo tracking/pinning, GitStatusService (static methods like WorktreeService pattern), GitRepoWatcher with CoreServices FSEvents, PRStatusCache with 60s TTL, ClaudeSessionState enum extending PaneStatusManager, callback-based pwd change forwarding from PaneViewModel to SpaceGitContext. Depends on Claude Session Status PRD (v1.3, Approved) for status.set --state IPC extension.

**Why:** Sidebar Status turns the sidebar into a live project dashboard showing Claude session dots + git branch/diff/PR per Space.

**How to apply:** Phase 1 (session state tracking) and Phase 2 (dots UI) can proceed independently. Phase 3 (git detection) introduces GitStatusService which follows WorktreeService patterns. Phase 5 (FSEvents) is the highest-risk phase due to CoreServices C API.
