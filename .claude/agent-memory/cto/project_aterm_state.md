---
name: aterm project state
description: Current state of aterm project - M7 polish implemented, sidebar redesign complete, CLI tool spec written.
type: project
---

As of 2026-04-05, aterm has working code through M7 (daily driver polish). 60 Swift source files across App/, Core/, DragAndDrop/, Input/, Models/, Pane/, Persistence/, Tab/, Utilities/, View/, WindowManagement/ directories. The workspace sidebar redesign is implemented (glassmorphism sidebar with disclosure groups, keyboard navigation).

**Current architecture:** SwiftUI app with NSWindow per workspace. WorkspaceWindowController manages windows with NSEvent keyboard monitor for shortcuts. WorkspaceWindowContent -> SidebarContainerView -> SidebarPanelView + terminal ZStack. GhosttyTerminalSurface wraps ghostty_surface_t for terminal rendering. Observable models: WorkspaceManager -> WorkspaceCollection -> Workspace -> SpaceCollection -> SpaceModel -> TabModel -> PaneViewModel -> SplitTree. ProcessDetector for running process checks. Session persistence via SessionSerializer/SessionRestorer.

**CLI tool spec written:** docs/feature/cli-tool/cli-tool-spec.md v1.0. Unix domain socket IPC, env var injection via ghostty_surface_config_s.env_vars, 6 implementation phases. Key env var injection point: GhosttyTerminalSurface.createSurface() builds ghostty_surface_config_s which has env_vars/env_var_count fields (ghostty.h lines 453-454).

**Why:** CLI enables programmatic control of workspace hierarchy, status reporting to sidebar, and macOS notifications from Claude Code hooks and AI agents.

**How to apply:** Implementation should follow the 6 phases in the spec. Phase 1 (IPC foundation) is independently testable. Env var injection (Phase 2) requires careful C memory management matching the existing working_directory pattern.
