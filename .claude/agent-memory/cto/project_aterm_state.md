---
name: aterm project state
description: Current state of aterm project - M7 polish implemented, sidebar redesign complete, CLI tool implemented, worktree spaces spec written.
type: project
---

As of 2026-04-07, aterm has working code through M7 (daily driver polish). 60+ Swift source files across App/, Core/, DragAndDrop/, Input/, Models/, Pane/, Persistence/, Tab/, Utilities/, View/, WindowManagement/ directories. The workspace sidebar redesign is implemented (glassmorphism sidebar with disclosure groups, keyboard navigation). CLI tool is fully implemented with IPC over Unix domain socket.

**Current architecture:** SwiftUI app with NSWindow per workspace. WorkspaceWindowController manages windows with NSEvent keyboard monitor for shortcuts. WorkspaceWindowContent -> SidebarContainerView -> SidebarPanelView + terminal ZStack. GhosttyTerminalSurface wraps ghostty_surface_t for terminal rendering. Observable models: WorkspaceManager -> WorkspaceCollection -> Workspace -> SpaceCollection -> SpaceModel -> TabModel -> PaneViewModel -> SplitTree. ProcessDetector for running process checks. Session persistence via SessionSerializer/SessionRestorer (currentVersion=1).

**CLI tool implemented:** aterm-cli binary with ArgumentParser. IPC over Unix domain socket at $TMPDIR/aterm-<uid>.sock. Commands: workspace.create/list/close/focus, space.create/list/close/focus, tab.create/list/close/focus, pane.split/list/close/focus, status.set/clear, notify. Environment injection via ghostty_surface_config_s.env_vars.

**Worktree Spaces spec written:** docs/feature/worktree-spaces/worktree-spaces-spec.md v1.0. 9 implementation phases. Key technical decisions: TOMLKit for TOML parsing, ghostty_surface_text() for command injection, OSC 7 (surfacePwdNotification) for shell readiness, incremental split approach for layout application preserving initial pane session. Schema version bumps from 1 to 2 for worktreePath persistence.

**Why:** Worktree Spaces is the next feature after CLI tool, automating git worktree-backed development environments.

**How to apply:** Implementation should follow the 9 phases in the spec. Phase 1 (TOML parsing) and Phase 2 (git service) are independently testable. Phase 4 (text injection) should validate ghostty_surface_text() early.
