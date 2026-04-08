---
name: aterm PRD review status
description: Status and key findings from devil's advocate reviews of aterm PRDs (sidebar-status v1.0 scored 0.68, worktree-spaces v1.1 scored 0.82, workspace-sidebar v1.1 scored 0.93)
type: project
---

## Worktree Spaces PRD

Reviewed worktree-spaces-prd v1.1 on 2026-04-07. Score: 0.82/1.0 (up from 0.72 on v1.0).

**Why:** All 5 required fixes from v1.0 addressed. Two new Major issues from the "type into terminal" execution model.

**v1.0 fixes verified:**
- FR-027: duplicate Space detection with `"existed"` flag -- properly specified
- FR-028: OSC 7 shell readiness + fallback delay -- grounded in existing `surfacePwdNotification`
- FR-010: main worktree source via `git worktree list --porcelain` -- explicit
- FR-011/012/013: create Space first, run setup visibly, then apply layout -- well-sequenced
- FR-014: cancel mechanism (Escape + button) -- present

**Remaining issues (Major, not blocking):**
1. Initial pane reuse during layout application underspecified -- which layout pane inherits the setup terminal? Need explicit mapping rule.
2. FR-012 "stop on non-zero exit" is unreliable when commands are typed into terminal -- aterm has no exit code access from interactively-typed commands. Either specify detection mechanism or soften the requirement.

**Minor:** Escape key conflicts with terminal input during setup cancel (recommend Cmd+. or sidebar button only). OQ#2 (.gitignore) should be resolved before implementation.

**How to apply:** If v1.2 review requested, verify the 2 Major issues above are addressed.

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

## Claude Session Status PRD

Reviewed claude-session-status-prd v1.1 on 2026-04-07. Score: 0.90/1.0 (up from 0.77 on v1.0).

**Why:** All 3 Major issues from v1.0 resolved. needs_attention gap documented as accepted self-resolving behavior, matcher strings verified, icon placement fully specified in FR-019.

**v1.0 Major fixes verified:**
1. needs_attention linger: documented with concrete self-resolution explanation (Stop->idle or UserPromptSubmit->busy within seconds)
2. Notification matcher strings: verified against Claude Code docs, cited in Appendix A note
3. Icon placement: resolved to second line of Space row, left of status label, ~10-12pt

**v1.0 Minor fixes verified:**
- status.clear vs inactive: clarifying note added (nil vs inactive distinction)
- active vs idle priority: rationale added (new session > passive waiting)
- Diagnostic logging: NFR-005 added (debug-level with pane ID, old/new state)
- OQ#2: closed referencing NG4

**Remaining issues (all Minor/Nit):**
1. Second-line visibility condition implicit -- should explicitly state "render when label OR Claude state exists"
2. OQ#1 (color values) still open -- hue choices (blue vs purple, orange vs yellow) should be narrowed before implementation
3. Hook configuration merging strategy unmentioned -- note that hooks are additive to existing arrays

**How to apply:** PRD is implementation-ready. Remaining items are refinement-level.

## Sidebar Status PRD (Git & Claude Session Status)

Reviewed sidebar-status-prd v1.1 on 2026-04-08. Score: 0.85/1.0 (up from 0.68 on v1.0).

**Why:** All 5 required fixes from v1.0 addressed. Three new Major issues are ambiguity, not missing capabilities.

**v1.0 fixes verified:**
- OQ#8 multi-repo: FR-002a/b/c define one line per repo, Claude dot grouping, non-repo handling, ordering
- PR caching: FR-056 specifies 60s TTL, decoupled from FSEvents, cache key by (repo_root, branch_name)
- FSEvents lifecycle: FR-065-069 cover create/teardown/update/scope/watch-paths
- Worktree resolution: FR-021 uses git rev-parse --git-dir and --git-common-dir
- Working directory pinning: FR-020 defines sticky behavior with explicit unpin conditions

**Remaining issues (3 Major, all clarification-level):**
1. FR-021 specifies both manual .git parsing (steps 1-3) and git rev-parse (step 4) without clarifying which to use -- contradictory
2. No fallback for git unavailable/failing (unlike FR-054 for gh) -- needs silent-failure spec
3. Pane-to-repo reassignment policy unspecified -- does a pane move repos when user cd's, or is it fixed at first detection?

**Minor:** NFR-008 3-repo cap needs single decision (not two options), hover popover target too small, sidebar min-width behavior unspecified, FR-002c "pinned first" ambiguous for non-worktree multi-repo Spaces.

**How to apply:** If v1.2 review requested, verify the 3 Major clarification issues are resolved.

## Prior PRD (aterm main PRD, unrelated)

Reviewed aterm PRD v1.3 on 2026-03-24. Score: 0.87/1.0. See git history for details.
