---
name: aterm spec conventions
description: Technical spec format, file location, and conventions established for aterm project specs.
type: project
---

Milestone specs live at: docs/feature/aterm/specs/m{N}-{feature-slug}-spec.md
Feature specs live at: docs/feature/{feature-slug}/{feature-slug}-spec.md (co-located with PRD)

Examples:
- docs/feature/aterm/specs/m7-daily-driver-polish-spec.md
- docs/feature/workspace-sidebar/workspace-sidebar-spec.md
- docs/feature/cli-tool/cli-tool-spec.md

**Why:** Milestone specs are grouped under the main PRD. Standalone feature specs are co-located with their PRD in a feature-specific directory.

**How to apply:** Future specs should follow the same template structure (prose, tables, directory trees -- no code snippets). Sections typically include: Overview, IPC/data layer, state management, component architecture, type definitions, permissions, performance, implementation phases, risks, open questions. Reference specific file paths, line numbers, and method names from the codebase.
