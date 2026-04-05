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

Existing IPC/CLI state: No URL scheme, no XPC service, no CLI tool, no socket-based IPC. GhosttyApp handles actions via C callbacks (ghostty_action_s). ProcessDetector uses ghostty_surface_needs_confirm_quit for foreground process detection. No existing notification (UNUserNotification) support — GHOSTTY_ACTION_DESKTOP_NOTIFICATION is received but returns true without handling. CLI tool PRD v1.1 (Draft, 2026-04-05) at docs/feature/cli-tool/cli-tool-prd.md — covers CRUD for all 4 hierarchy levels, status reporting to sidebar, notifications, Unix domain socket IPC, env var injection (ATERM_SOCKET, ATERM_PANE_ID, ATERM_CLI_PATH, etc.). Key v1.1 decisions: UUID-only targeting (no name-based lookups), single-window scope, env vars trusted with stale caveat (IPC handler detects mismatch), sidebar status inline with space row (most recently updated pane), exit code 4 for notification permission denial, process safety checks at IPC handler level.

Bundle ID: com.aterm.app. App is not sandboxed. XcodeGen project (project.yml).

**Why:** Ghostty lacks workspace/space concepts, has limited customizability, and no session persistence. Developer wants native macOS integration to replace tmux-style workflows.

**How to apply:** All feature planning should respect: macOS-only, keyboard-driven, no plugin system in v1, no telemetry. PRD lives at docs/feature/aterm/aterm-prd.md. Doc structure: docs/feature/[feature-name]/[feature-name]-prd.md.
