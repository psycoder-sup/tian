---
name: aterm PRD review status
description: Status and key findings from devil's advocate reviews of aterm PRDs (workspace-sidebar v1.1 scored 0.93, implementation-ready)
type: project
---

## Workspace Sidebar PRD

Reviewed workspace-sidebar PRD v1.1 on 2026-04-01. Score: 0.93/1.0 (up from 0.70 on v1.0).

**Why:** All 11 issues from v1.0 review were substantively fixed. Focus management (FR-23-27) went from weakest to strongest area. Cross-window scope decision is explicit and well-reasoned.

**Remaining minor items (none blocking):**
1. OQ#1 (global vs per-window sidebar state) should be resolved as a decision before Phase 1
2. Full-screen glassmorphism behavior needs a one-liner (material blurs nothing meaningful in full-screen)
3. Phase ordering: Phase 4 (icon rail) arguably higher priority than Phase 3 (context menus/DnD)
4. Post-v1 should distinguish "sidebar search" from "cross-workspace fuzzy switcher" as separate capabilities

**How to apply:** PRD is implementation-ready. If v1.2 review requested, verify OQ#1 is resolved and the minor items above are addressed.

## CLI Tool PRD

Reviewed cli-tool-prd v1.0 on 2026-04-05. Score: 0.72/1.0.

**Why:** Two blockers: (1) multi-window entity lookup unspecified -- PRD says "across all windows" but no resolution path exists; (2) name uniqueness (OQ-2/OQ-7) must be decided before CLI grammar is final. Three major issues: stale env vars, status display design undecided, notification permission exit code missing.

**Key findings:**
- ghostty_surface_config_s already has env_vars/env_var_count (unused by aterm) -- validates TB-02
- GHOSTTY_ACTION_DESKTOP_NOTIFICATION callback is a no-op stub (GhosttyApp.swift:308-309) -- accurately cited
- AtermAppDelegate says "Currently single-window" -- PRD doesn't acknowledge this
- WorkspaceManager only tracks activeWorkspaceID, no cross-window lookup
- Tab/Space drag-and-drop exists, creating stale env var risk

**How to apply:** If v1.1 review requested, verify the 5 required fixes are addressed (multi-window resolution, name uniqueness, stale env vars, status display decision, notification permission exit code).

## Prior PRD (aterm main PRD, unrelated)

Reviewed aterm PRD v1.3 on 2026-03-24. Score: 0.87/1.0. See git history for details.
