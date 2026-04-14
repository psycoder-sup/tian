---
name: tian spec conventions
description: Technical spec format and location conventions for the tian project
type: project
---

Specs are stored at docs/feature/tian/specs/m[N]-[feature-name]-spec.md. The project is greenfield -- no Swift source code exists yet as of 2026-03-24. All milestones (M1-M7) are defined in the PRD at docs/feature/tian/tian-prd.md.

Written specs so far:
- M3: docs/feature/tian/specs/m3-tabs-and-spaces-spec.md (2026-03-24, v1.0)

M3 spec defines a PaneNode interface contract that M2 must satisfy (Section 8). When writing the M2 spec, ensure these are addressed: create single-pane tree, close all panes, "tree empty" signal, activePaneID tracking, isEmpty property.

**Why:** Establishing a consistent spec location so all agents can find and reference specs. Cross-milestone contracts need coordination.

**How to apply:** When creating new specs, follow the path pattern above. Reference the PRD version in the spec header. Check existing specs for interface contracts before designing new milestone APIs.
