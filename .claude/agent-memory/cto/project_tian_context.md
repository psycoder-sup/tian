---
name: tian project context
description: Greenfield macOS terminal emulator project - tech stack, doc structure, spec locations, and key architectural decisions
type: project
---

tian is a greenfield GPU-accelerated macOS terminal emulator. No code exists yet as of 2026-03-24. PRD is at docs/feature/tian/tian-prd.md (v1.4, approved).

Tech stack: Swift + SwiftUI (app chrome), libghostty-vt (VT parsing, C ABI from Ghostty project), Metal (GPU rendering), POSIX PTY, macOS 26+.

Doc structure: PRD at docs/feature/tian/tian-prd.md. Specs at docs/feature/tian/specs/. First spec: m2-pane-splitting-spec.md.

Key architectural decision for M2: immutable value-type binary split tree (PaneNode enum -- renamed from SplitNode after validation) with spatial focus navigation (Euclidean distance, not tree traversal). Inspired by Ghostty's PR #7523 approach but implemented natively in Swift.

Key decisions from 2026-03-24 spec validation:
- PaneNode is the canonical type name (enum with .leaf and .split cases), used across all specs
- Cmd+W closes focused pane with cascading close (last pane->tab, last tab->space, last space->workspace, last workspace->app quit)
- Cmd+Shift+W opens workspace switcher (fuzzy search overlay)
- Pane resize is mouse drag-handle only (no keyboard shortcuts)
- Last workspace close quits app (no default workspace creation)
- M5 JSON schema uses binary tree format (first/second fields, not children array)
- Window geometry (x, y, width, height) + is_fullscreen persisted per workspace in M5
- Workspace reorder via drag-and-drop is in M4 scope (FR-01)

Other agent memories exist in feature-planner/ and devils-advocate/ directories with useful project and user context.

**Why:** First spec establishes patterns for future milestone specs.
**How to apply:** Future specs should follow the same format and directory convention. Reference M1 dependencies explicitly since M1 is not yet implemented.
