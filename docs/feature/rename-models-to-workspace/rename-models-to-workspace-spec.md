# SPEC: Rename Models/ to Workspace/

**Based on:** Work item description (no PRD -- refactoring task)
**Author:** CTO Agent
**Date:** 2026-04-09
**Version:** 1.1
**Status:** Approved

---

## 1. Overview

This spec covers renaming the `tian/Models/` source directory to `tian/Workspace/` to better reflect its contents and align with the project's convention of naming directories after their domain concept (e.g., `Pane/`, `Tab/`, `Core/`). The directory currently holds five files: three workspace-domain types (`Workspace.swift`, `WorkspaceCollection.swift`, `WorkspaceManager.swift`) and two pane-domain types (`PaneHierarchyContext.swift`, `PaneStatusManager.swift`) that were placed in `Models/` as a catch-all.

Because Swift targets compile all sources in a flat namespace (no file-path-based imports), the rename is purely a file-system and documentation change. No Swift import statements, access modifiers, or runtime behavior are affected. The XcodeGen-based build discovers sources via a glob on `tian/` with only `Vendor/**` excluded, so `project.yml` requires no path changes -- only a `xcodegen generate` run after the move.

The key design decision is what to do with `PaneHierarchyContext.swift` and `PaneStatusManager.swift`. These are pane-related types that do not belong in a `Workspace/` directory. This spec recommends relocating them to `tian/Pane/`, which already contains `PaneViewModel.swift`, `PaneNode.swift`, `PaneState.swift`, and related pane-domain files.

---

## 2. Database Schema

N/A -- no database or persistence schema changes. This is a source directory rename with no data model modifications. The `SessionState` persistence format, serialization logic, and all model types remain byte-identical.

---

## 3. API Layer

N/A -- no API, IPC, or RPC changes. All type names, method signatures, and protocols remain unchanged. Only file locations on disk change.

---

## 4. State Management

N/A -- no state management changes. All `@Observable` classes, `NotificationCenter` patterns, and singleton references remain unchanged.

---

## 5. Component Architecture

### 5.1 File System Changes

The entire operation consists of moving eight files across four directories.

**Files moving from `tian/Models/` to `tian/Workspace/` (new directory):**

| File | Type | Rationale |
|------|------|-----------|
| `Workspace.swift` | `Workspace` class, `WorkspaceSnapshot` struct | Core workspace domain type |
| `WorkspaceCollection.swift` | `WorkspaceCollection` class | Per-window workspace ownership |
| `WorkspaceManager.swift` | `WorkspaceManager` class | App-level workspace coordinator |

**Files moving from `tian/Models/` to `tian/Pane/` (existing directory):**

| File | Type | Rationale |
|------|------|-----------|
| `PaneHierarchyContext.swift` | `PaneHierarchyContext` struct | Carries hierarchy IDs for pane environment injection; consumed primarily by `PaneViewModel` (already in `Pane/`) |
| `PaneStatusManager.swift` | `PaneStatusManager` class, `PaneStatus` struct | Manages per-pane status labels; referenced by `PaneViewModel.closePane` and `SidebarSpaceRowView`; the `Pane` prefix makes its domain clear |

**Files moving from `tian/Models/` to `tian/Core/` (existing directory):**

| File | Type | Rationale |
|------|------|-----------|
| `ClaudeSessionState.swift` | `ClaudeSessionState` enum | Session state for Claude Code sessions; core infrastructure type |
| `GitTypes.swift` | `GitBranch`, `GitFileChange`, etc. | Git-related value types; used by `GitStatusService` and `GitRepoWatcher` (both in `Core/`) |

**Files moving from `tian/Models/` to `tian/Tab/` (existing directory):**

| File | Type | Rationale |
|------|------|-----------|
| `SpaceGitContext.swift` | `SpaceGitContext` class | Per-space git repository context; consumed by `SpaceModel` (already in `Tab/`) |

**After the move, the `tian/Models/` directory is deleted entirely.**

### 5.2 Resulting Directory Structure (affected areas only)

```
tian/
    Workspace/                          (NEW -- renamed from Models/)
        Workspace.swift
        WorkspaceCollection.swift
        WorkspaceManager.swift
    Pane/                               (EXISTING -- two files added)
        PaneHierarchyContext.swift       (moved from Models/)
        PaneStatusManager.swift         (moved from Models/)
        PaneNode.swift
        PaneState.swift
        PaneViewModel.swift
        SplitLayout.swift
        SplitNavigation.swift
        SplitTree.swift
    Core/                               (EXISTING -- two files added)
        ClaudeSessionState.swift        (moved from Models/)
        GitTypes.swift                  (moved from Models/)
        GitRepoWatcher.swift
        GitStatusService.swift
        ...
    Tab/                                (EXISTING -- one file added)
        SpaceGitContext.swift            (moved from Models/)
        SpaceModel.swift
        SpaceCollection.swift
        TabModel.swift
```

### 5.3 Why Not Keep PaneHierarchyContext and PaneStatusManager in Workspace/?

These types have "Pane" in their name and are consumed by pane-layer code:

- `PaneHierarchyContext` is a stored property on `PaneViewModel` (`tian/Pane/PaneViewModel.swift`, line 44) and is constructed in `SpaceModel` (`tian/Tab/SpaceModel.swift`, line 182). It carries IDs from the workspace chain but its purpose is pane-level environment injection.
- `PaneStatusManager` is called from `PaneViewModel.closePane` (`tian/Pane/PaneViewModel.swift`, line 249) and from `SidebarSpaceRowView` (`tian/View/Sidebar/SidebarSpaceRowView.swift`, line 49). It manages pane-scoped state.

Placing pane-domain types in `Workspace/` would be as misleading as the current `Models/` catch-all. The `Pane/` directory is the natural home.

---

## 6. Navigation

N/A -- no navigation, routing, or screen changes. This is a build-time file organization change with no runtime impact.

---

## 7. Type Definitions

N/A -- no type additions, removals, or modifications. All existing types (`Workspace`, `WorkspaceSnapshot`, `WorkspaceCollection`, `WorkspaceManager`, `PaneHierarchyContext`, `PaneStatus`, `PaneStatusManager`) retain their names, properties, and conformances.

---

## 8. Analytics Implementation

N/A -- no analytics events affected by a directory rename.

---

## 9. Permissions & Security

N/A -- no permission or security model changes.

---

## 10. Performance Considerations

N/A -- file organization has no runtime performance impact. The only build-time consideration is that `xcodegen generate` must be run after the move to regenerate the Xcode project file. Build times are unaffected since the same set of files is compiled.

---

## 11. Documentation Updates

### 11.1 CLAUDE.md (mandatory)

The Source Layout section at line 42 of `CLAUDE.md` currently reads:

```
- `Models/` -- `Workspace`, `WorkspaceCollection`, `WorkspaceManager`
```

This must be updated to reflect the new directory name and the relocated pane types. The updated entry should list `Workspace/` with its three types. The `Pane/` entry (line 44) should be updated to include `PaneHierarchyContext` and `PaneStatusManager` in its listing. The `Models/` entry is removed entirely.

### 11.2 Historical Spec Documents (optional, low priority)

Six documentation files contain references to `tian/Models/` paths. These are historical specs describing what was built at the time of writing. Updating them is optional and low priority since they are reference documents, not living configuration. If updated, the changes are straightforward string replacements.

| File | Occurrences | Content |
|------|-------------|---------|
| `docs/feature/workspace-sidebar/workspace-sidebar-spec.md` | 6 | References to `tian/Models/WorkspaceCollection.swift` and `tian/Models/WorkspaceManager.swift` |
| `docs/feature/cli-tool/cli-tool-spec.md` | 4 | References to `tian/Models/PaneStatusManager.swift` and `tian/Models/PaneHierarchyContext.swift` |
| `docs/feature/cli-tool/cli-tool-design-guideline.md` | 3 | References to `tian/Models/StatusModel.swift` (a design-time name that was never used) |
| `docs/feature/tian/specs/m4-workspaces-spec.md` | 1 | Directory tree showing `Models/` |
| `docs/feature/tian/specs/m3-tabs-and-spaces-spec.md` | 1 | Directory tree showing `Models/` |
| `docs/feature/tian/specs/validation-report.md` | 1 | Mentions `Models/` in a discussion of inconsistent directory layouts |

### 11.3 Agent Memory (mandatory)

The CTO agent memory file `project_tian_state.md` lists `Models/` in the directory enumeration. This must be updated to reflect the rename.

---

## 12. Migration & Deployment

### 12.1 Execution Steps

The following steps must be performed in order:

1. **Create the `tian/Workspace/` directory.**

2. **Move the three workspace files** (using `git mv`) from `tian/Models/` to `tian/Workspace/`:
   - `Workspace.swift`
   - `WorkspaceCollection.swift`
   - `WorkspaceManager.swift`

3. **Move the two pane files** (using `git mv`) from `tian/Models/` to `tian/Pane/`:
   - `PaneHierarchyContext.swift`
   - `PaneStatusManager.swift`

4. **Move the two core files** (using `git mv`) from `tian/Models/` to `tian/Core/`:
   - `ClaudeSessionState.swift`
   - `GitTypes.swift`

5. **Move the space git context file** (using `git mv`) from `tian/Models/` to `tian/Tab/`:
   - `SpaceGitContext.swift`

6. **Delete the now-empty `tian/Models/` directory.**

7. **Update `CLAUDE.md`** -- replace the `Models/` entry in the Source Layout section with `Workspace/` and update the `Pane/` entry to include the two relocated types.

8. **Run `xcodegen generate`** to regenerate `tian.xcodeproj` with the new file locations. The `project.yml` file itself requires no edits because the tian target uses `path: tian` with only `Vendor/**` excluded -- XcodeGen discovers all Swift files via glob.

9. **Build and run tests** to verify the project compiles and all tests pass. Use `xcodebuild -scheme tian -derivedDataPath .build build` and `xcodebuild -scheme tian -derivedDataPath .build test -skip-testing:tianUITests`.

### 12.2 Rollback

If any issue is discovered, the operation is trivially reversible by moving files back and re-running `xcodegen generate`. Since no type names, APIs, or runtime behavior change, there is no data migration to reverse.

### 12.3 Feature Flags

None needed. This is a build-time-only change with no runtime behavioral difference.

---

## 13. Implementation Phases

This is a single-phase change. There is no meaningful way to split a directory rename into incremental phases.

**Phase 1 (only phase): Directory rename and documentation update**

| Step | Description | Verification |
|------|-------------|--------------|
| 1 | Create `tian/Workspace/`, move 3 workspace files there | Directory exists with 3 files |
| 2 | Move 2 pane files to `tian/Pane/` | `tian/Pane/` contains `PaneHierarchyContext.swift` and `PaneStatusManager.swift` |
| 3 | Delete `tian/Models/` | Directory no longer exists |
| 4 | Update `CLAUDE.md` Source Layout section | `Models/` reference removed, `Workspace/` and updated `Pane/` entries present |
| 5 | Run `xcodegen generate` | `tian.xcodeproj` regenerated with correct group structure |
| 6 | Build the project | `xcodebuild build` succeeds with zero errors |
| 7 | Run unit tests | All existing tests pass (zero regressions) |

---

## 14. Test Strategy

### 14.1 Mapping to Functional Requirements

Since this is a refactoring task with no PRD, the functional requirement is a single constraint: the rename must not change any runtime behavior.

| Requirement | Test Description | Type | Preconditions |
|-------------|-----------------|------|---------------|
| No compile errors after rename | Build the project with `xcodebuild build` | Build verification | Files moved, `xcodegen generate` run |
| No test regressions | Run full unit test suite | Existing unit tests | Project builds successfully |
| XcodeGen project reflects new paths | Inspect generated `tian.xcodeproj` to confirm `Workspace/` group exists and `Models/` group does not | Manual inspection | `xcodegen generate` run |
| CLAUDE.md is accurate | Verify Source Layout section lists `Workspace/` (not `Models/`) and `Pane/` includes the two relocated types | Manual review | CLAUDE.md updated |

### 14.2 Unit Tests

No new unit tests are needed. The existing test suite (`tianTests/`) covers all the types being moved:

- `tianTests/WorkspaceTests.swift` -- tests `Workspace` and `WorkspaceCollection`
- `tianTests/PaneStatusManagerTests.swift` -- tests `PaneStatusManager`
- `tianTests/EnvironmentBuilderTests.swift` -- tests `PaneHierarchyContext`
- `tianTests/IPCCommandHandlerTests.swift` -- tests `IPCCommandHandler` which depends on `PaneStatusManager`

All of these tests reference types by name, not by file path. They will pass without modification as long as the project compiles.

### 14.3 Integration Tests

No new integration tests needed. The existing test suite serves as the integration verification.

### 14.4 End-to-End Tests

No e2e tests needed. The rename has no user-visible effect.

### 14.5 Edge Cases

- **Empty directory cleanup:** After moving all 5 files, the `tian/Models/` directory must be deleted. If it is left behind (even empty), it creates confusion and may cause XcodeGen to generate an empty group.
- **Git history:** Using `git mv` (rather than delete + add) preserves file history and produces a cleaner diff. The implementation should use `git mv` for each file.

---

## 15. Technical Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| XcodeGen does not pick up the new file locations | Build fails -- files not found | Very low. XcodeGen uses a glob on `path: tian` excluding only `Vendor/**`. | Run `xcodegen generate` and verify the generated project before committing. |
| Stale Xcode derived data causes phantom build errors | Confusing build failures referencing old paths | Low. Xcode may cache old module maps. | Clean derived data with `rm -rf .build` and rebuild if needed. |
| Merge conflicts with in-flight branches | Other branches referencing `Models/` will conflict | Low to medium depending on active branches | Communicate the rename to collaborators. Resolve conflicts by applying the rename to conflicting files. |
| Historical docs become misleading | Developers reading old specs may look for `tian/Models/` | Very low. Old specs describe what was built at the time. | Optionally update the 6 affected doc files. The CLAUDE.md update (mandatory) is the authoritative reference. |

---

## 16. Open Technical Questions

| Question | Context | Impact if Unresolved |
|----------|---------|---------------------|
| **Recommendation:** Move the two Pane-prefixed files to `Pane/` | This spec recommends `Pane/` based on domain alignment (see section 5.3). The `Models/` directory is being deleted, so these files must go somewhere. The only options are `Workspace/` or `Pane/`. Given both types have "Pane" in their name and are consumed by pane-layer code, `Pane/` is the natural home. Requires user confirmation since the work item only mentions 3 files. | If moved to `Workspace/` instead, pane-domain types remain misplaced -- perpetuating the catch-all problem under a new name. |
| Should the 6 historical spec/doc files be updated? | These are reference documents describing past work. Updating them is clean but costs time for no runtime benefit. | If unresolved, the historical docs reference a non-existent directory. Low practical impact since CLAUDE.md is the authoritative source layout reference. |
