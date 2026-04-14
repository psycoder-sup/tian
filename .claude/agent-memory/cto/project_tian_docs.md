---
name: tian doc structure and spec conventions
description: Documentation structure for tian project - PRDs and specs locations, spec format conventions
type: project
---

Doc structure: docs/feature/tian/tian-prd.md for the main PRD. Specs go in docs/feature/tian/specs/ with naming pattern m{N}-{feature}-spec.md.

**Why:** First spec (M5 persistence) was written to this location. No CLAUDE.md exists yet in the project root.

**How to apply:** Place future specs in docs/feature/tian/specs/. Follow the same template structure (14 sections: Overview, Schema, API/Flow, State Management, Components, Navigation, Types, Analytics, Permissions, Performance, Migration, Phases, Risks, Open Questions). No code exists yet -- project is in pre-implementation planning phase.
