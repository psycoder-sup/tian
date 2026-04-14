---
name: tian M1 spec context
description: M1 Terminal Fundamentals spec written 2026-03-24. Covers PTY, libghostty-vt bridge, Metal rendering, selection, scrolling, Unicode, color schemes.
type: project
---

M1 spec written at docs/feature/tian/specs/m1-terminal-fundamentals-spec.md (2026-03-24).

Key architectural decisions:
- Five-layer architecture: App Shell (SwiftUI), Terminal Core (serial queue), PTY I/O (dispatch source), Renderer (Metal display link), Selection (main thread)
- libghostty-vt integrated via C bridging header, wrapped in GhosttyBridge Swift class with RAII deinit
- GridSnapshot (immutable value type) decouples renderer from terminal state -- extracted on terminal-core queue, consumed on render thread
- Metal rendering uses 4 passes: background, text, cursor, selection -- all instanced draw calls
- Font atlas uses Core Text + shelf-packing into MTLTexture (grayscale .r8Unorm + separate RGBA for emoji)
- Triple-buffered Metal to avoid CPU/GPU contention
- Smooth scrolling via sub-pixel offset accumulation + whole-line libghostty-vt viewport scrolling
- Selection implemented entirely in tian (not from libghostty-vt)

**Why:** Greenfield project, no existing code. PRD at docs/feature/tian/tian-prd.md. Doc structure: docs/feature/tian/specs/ for specs.

**How to apply:** Future milestones (M2-M7) build on this architecture. TerminalCore will be instantiated per-pane in M2. The view layer splits in M3/M4 for tabs/spaces/workspaces.
