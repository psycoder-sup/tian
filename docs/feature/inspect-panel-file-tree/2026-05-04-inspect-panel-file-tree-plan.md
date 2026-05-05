# Plan: Inspect Panel — File Tree (v1)

**Date:** 2026-05-04
**Status:** Approved
**Based on:** docs/feature/inspect-panel-file-tree/2026-05-04-inspect-panel-file-tree-prd.md

---

## 1. Approach

The feature adds one new SwiftUI column on the trailing edge of every workspace
window (`WorkspaceWindowContent` → `SidebarContainerView`). The window-level
layout becomes `[Sidebar overlay] | [Space content] | [Inspect panel]`. The
panel itself is a thin observable model attached to `Workspace` — visibility
and width persist per workspace via session state — while the *contents* of
the file tree are computed against the **active space's** working directory.
Selection and expansion live in a separate runtime view-model that the panel
view binds to; both reset when the workspace window closes (FR-31).

Three load-bearing decisions:

1. **State scope.** `Workspace.inspectPanelState` (visibility + width) is
   per-window because the PRD explicitly requires per-window state (FR-29/30,
   "Cross-window state sync" in Non-Goals). The file-tree view-model
   (`InspectFileTreeViewModel`) is workspace-scoped too, but its `setRoot`
   call is driven by the active space's working directory (FR-10) — switching
   spaces re-roots the same view-model rather than spawning a fresh one. This
   matches FR-28a: cancellation is straightforward because there's only ever
   one in-flight scan per panel.

2. **File enumeration source of truth.** Inside a git repo we enumerate the
   tree via `git ls-files --cached --others --exclude-standard -z` — that one
   command yields exactly "every tracked file plus every untracked
   non-ignored file" (FR-15). We then derive directory rows from the unique
   path prefixes. Outside a git repo we fall back to `FileManager` directory
   enumeration. This avoids reimplementing `.gitignore` parsing and keeps
   gitignore semantics identical to git itself.

3. **Status badges piggyback on existing infrastructure.** `GitStatusService.
   diffStatus` already returns untracked entries (no `--untracked-files=no`
   flag is passed) and maps `??` to `.added`, so FR-15a / FR-20 are
   intrinsically satisfied by the existing service. The only gap is its
   100-file cap, which the inspect panel cannot live with — we add an
   uncapped variant `diffStatusFull(directory:)` rather than mutate the
   sidebar's call site. Refresh wiring reuses the active space's
   `SpaceGitContext` git status stream, plus a new lightweight
   `WorkingTreeWatcher` for FS-only updates inside non-git directories or
   for non-git-tracked changes (e.g. dotfile creation).

Rendering uses `LazyVStack` inside a `ScrollView` to satisfy the FR-33
virtualization requirement; the view materializes a flat ordered list of
visible rows from a depth-first walk that prunes collapsed subtrees, so the
LazyVStack only realizes rows in the viewport regardless of total tree size.

Persistence: `SessionState.currentVersion` bumps from 4 → 5. New
`WorkspaceState.inspectPanelVisible` and `inspectPanelWidth` are added as
**optional** fields, so the v4 → v5 migration is identity (`{ json in json }`)
and the runtime applies defaults (`true`, `320`) when the optionals decode
nil. This matches the precedent of v1 → v2 / v2 → v3 in `SessionStateMigrator`.

`WorktreeKind` (FR-05a) is a new typed enum that lives in `Core/InspectPanel/`.
Its computation reuses `GitStatusService.detectRepo` — `RepoLocation.isWorktree`
already distinguishes linked worktree vs main checkout — so `WorktreeKind` is
a small adapter, not a re-derivation.

## 2. File-by-file Changes

| File | Change | Notes |
|------|--------|-------|
| `tian/Core/InspectPanel/WorktreeKind.swift` | new | `enum WorktreeKind { linkedWorktree, mainCheckout, notARepo, noWorkingDirectory }` + `label: String?` + `static func classify(directory: String?) async`. |
| `tian/Core/InspectPanel/FileTreeNode.swift` | new | `struct FileTreeNode` value type used by the view-model and view. |
| `tian/Core/InspectPanel/InspectPanelState.swift` | new | `@MainActor @Observable final class InspectPanelState` — visibility + width, with min/max/default constants. |
| `tian/Core/InspectPanel/InspectFileScanner.swift` | new | Stateless async helpers: `scanGitTracked(workingTree:) async throws -> [String]` (runs `git ls-files -coz`) and `scanFileSystem(root:) async throws -> [String]` (FileManager fallback). Returns canonical relative paths. |
| `tian/Core/InspectPanel/WorkingTreeWatcher.swift` | new | Thin FSEvents wrapper modeled on `GitRepoWatcher`. Watches a single root path, debounces batches, calls back on the main actor. |
| `tian/Core/InspectPanel/InspectFileTreeViewModel.swift` | new | `@MainActor @Observable` view-model. Owns scan task, watcher, expanded paths, selection, and the materialized flat row list. Implements FR-27 / FR-28 / FR-28a. |
| `tian/Core/GitStatusService.swift` | modify | Add `static func diffStatusFull(directory:) async -> (summary: GitDiffSummary, files: [GitChangedFile])` — same parser as `diffStatus` but with no 100-file cap. Existing `diffStatus` keeps its cap unchanged so the sidebar is untouched. Refactor shared parsing into a private helper. |
| `tian/Workspace/Workspace.swift` | modify | Store `let inspectPanelState: InspectPanelState`. Initialize from snapshot defaults. Extend `WorkspaceSnapshot` ↔ runtime conversion to round-trip the new fields. |
| `tian/Persistence/SessionState.swift` | modify | Add `inspectPanelVisible: Bool?` and `inspectPanelWidth: Double?` to `WorkspaceState`. Both optional so v4 records decode unchanged. |
| `tian/Persistence/SessionSerializer.swift` | modify | Bump `currentVersion` from `4` to `5`. Update the version comment. |
| `tian/Persistence/SessionStateMigrator.swift` | modify | Register `migrations[4] = { json in json }` (identity — optional fields default to nil and the runtime applies defaults). Update the comment to document the v5 additions. |
| `tian/View/InspectPanel/InspectPanelView.swift` | new | Root SwiftUI view: header + body + status strip; reads `InspectPanelState`, `InspectFileTreeViewModel`, and the active space. Hosts the close (×) button. |
| `tian/View/InspectPanel/InspectPanelHeader.swift` | new | 48 px header with the single-pill "Files" segmented control, space-name + WorktreeKind suffix label, and the close-button pill. |
| `tian/View/InspectPanel/InspectPanelStatusStrip.swift` | new | 20 px bottom strip — `files · {space-name}` left, `inspect` right. |
| `tian/View/InspectPanel/InspectPanelFileBrowser.swift` | new | The Files-tab body. Renders subheader + scrollable `LazyVStack` of `InspectPanelFileRow`. Drives `InspectFileTreeViewModel` interactions. |
| `tian/View/InspectPanel/InspectPanelFileRow.swift` | new | Single-row view: indent + chevron + icon + name + optional badge. Handles hover and selection styling. |
| `tian/View/InspectPanel/InspectPanelEmptyStates.swift` | new | Centered `Loading…`, `Still loading…`, `Nothing to show.`, `No working directory for this space.` views. |
| `tian/View/InspectPanel/InspectPanelRail.swift` | new | The 22 px collapsed rail with rotated `inspect` text; tap to re-show. |
| `tian/View/InspectPanel/InspectPanelResizeHandle.swift` | new | Drag handle on the panel's leading edge — clamps width to 240–480, mutates `InspectPanelState`. |
| `tian/View/Sidebar/SidebarContainerView.swift` | modify | Wrap `spaceContentStack` in an HStack(0) with `InspectPanelView` (or `InspectPanelRail` when hidden) on the trailing edge. Forward the active space + workspace to the panel. Keep the existing sidebar ZStack overlay. |
| `tianTests/WorktreeKindTests.swift` | new | Classifier covers regular repo, linked worktree, non-git dir, nil. |
| `tianTests/InspectFileScannerTests.swift` | new | Git-tracked vs non-git directories; respects `.gitignore`; includes untracked-not-ignored; symlinks counted as files. |
| `tianTests/InspectFileTreeViewModelTests.swift` | new | Scan cancellation on `setRoot`, expansion toggle, selection clears when path disappears, badge map update propagates, slow-scan flag flips after 5 s. |
| `tianTests/InspectPanelStateTests.swift` | new | Width clamping; round-trip through snapshot. |
| `tianTests/SessionMigrationV4ToV5Tests.swift` | new | Decode v4 file → migrated state has nil fields → runtime applies defaults. |
| `tianTests/GitStatusServiceTests.swift` | modify | Add a `diffStatusFull` case that exercises >100 changed files and verifies all are returned. |

## 3. Types & Interfaces

```swift
// File: tian/Core/InspectPanel/WorktreeKind.swift
import Foundation

enum WorktreeKind: Sendable, Equatable {
    case linkedWorktree
    case mainCheckout
    case notARepo
    case noWorkingDirectory

    /// The lowercase suffix rendered in the header / subheader. `nil` when
    /// the panel should show the empty state instead of a context label.
    var label: String? {
        switch self {
        case .linkedWorktree: "worktree"
        case .mainCheckout:   "repo"
        case .notARepo:       "local"
        case .noWorkingDirectory: nil
        }
    }

    /// Classifies the directory by reusing `GitStatusService.detectRepo`.
    /// Pass `nil` when the active space has no resolvable working directory.
    static func classify(directory: String?) async -> WorktreeKind {
        guard let directory, !directory.isEmpty else { return .noWorkingDirectory }
        guard let location = await GitStatusService.detectRepo(directory: directory) else {
            return .notARepo
        }
        return location.isWorktree ? .linkedWorktree : .mainCheckout
    }
}
```

```swift
// File: tian/Core/InspectPanel/FileTreeNode.swift
import Foundation

struct FileTreeNode: Identifiable, Hashable, Sendable {
    /// Canonical absolute path. Stable across refreshes; used as `Identifiable.id`.
    let id: String
    let name: String
    let kind: Kind
    /// Path relative to the tree root, used to look up `GitFileStatus` for badges.
    let relativePath: String

    enum Kind: Sendable, Hashable {
        case directory(canRead: Bool)
        case file(ext: String?)
    }

    var isDirectory: Bool {
        if case .directory = kind { return true } else { return false }
    }
}
```

```swift
// File: tian/Core/InspectPanel/InspectPanelState.swift
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class InspectPanelState {
    static let defaultWidth: CGFloat = 320
    static let minWidth: CGFloat = 240
    static let maxWidth: CGFloat = 480

    var isVisible: Bool
    var width: CGFloat

    init(isVisible: Bool = true, width: CGFloat = InspectPanelState.defaultWidth) {
        self.isVisible = isVisible
        self.width = min(max(width, Self.minWidth), Self.maxWidth)
    }

    func clampedWidth(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, Self.minWidth), Self.maxWidth)
    }
}
```

```swift
// File: tian/Core/InspectPanel/InspectFileTreeViewModel.swift
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class InspectFileTreeViewModel {

    // Observable state (drives the view)
    private(set) var rootDirectory: URL?
    private(set) var worktreeKind: WorktreeKind = .noWorkingDirectory
    /// Materialized flat list of visible rows (depth-first, ancestors expanded).
    /// Recomputed on scan completion or expand/collapse.
    private(set) var visibleRows: [FileTreeNode] = []
    private(set) var statusByRelativePath: [String: GitFileStatus] = [:]
    private(set) var isInitialScanInFlight: Bool = false
    private(set) var isInitialScanSlow: Bool = false
    private(set) var hasContent: Bool = false   // true once first scan finished and rows non-empty

    var expandedPaths: Set<String> = []   // by canonical absolute path
    var selectedPath: String?

    // MARK: - Public API

    /// Switches the tree to a new root. Any in-flight scan for the previous
    /// root is cancelled (FR-28a). Pass `nil` to enter the empty state.
    func setRoot(_ url: URL?) { /* implemented later */ }

    /// Toggles directory expansion (FR-13).
    func toggle(_ path: String) { /* implemented later */ }

    /// Updates the row selection (FR-23).
    func select(_ path: String?) { /* implemented later */ }

    /// Pushes a fresh `git status` result into the tree so badges re-render.
    func updateStatus(_ files: [GitChangedFile]) { /* implemented later */ }

    /// Tears down the watcher and cancels the scan (called on workspace close).
    func teardown() { /* implemented later */ }

    // MARK: - Private

    private var scanTask: Task<Void, Never>?
    private var slowFlagTask: Task<Void, Never>?
    private var watcher: WorkingTreeWatcher?

    /// Full unfiltered tree (set after each scan). View-only state derives from
    /// this + `expandedPaths` to produce `visibleRows`.
    private var allNodes: [FileTreeNode] = []
    private var childrenByParent: [String: [FileTreeNode]] = [:]
}
```

```swift
// File: tian/Core/InspectPanel/InspectFileScanner.swift
import Foundation

enum InspectFileScanner {
    /// Returns POSIX-relative paths (no leading `./`) for every tracked or
    /// untracked-not-ignored file under `workingTree`. Throws if `git`
    /// returns a non-zero exit code.
    static func scanGitTracked(workingTree: String) async throws -> [String]

    /// Returns POSIX-relative paths for every non-hidden file under `root`
    /// using `FileManager`. Used when the directory is not in a git repo.
    /// Skips bundle internals (`*.app/Contents`) and standard junk like
    /// `.DS_Store`.
    static func scanFileSystem(root: URL) async throws -> [String]
}
```

```swift
// File: tian/Core/InspectPanel/WorkingTreeWatcher.swift
import Foundation

final class WorkingTreeWatcher {
    init(root: String, debounce: Duration = .milliseconds(250),
         onChange: @escaping @Sendable () -> Void)
    func stop()
}
```

```swift
// File: tian/Core/GitStatusService.swift   (additions only)
extension GitStatusService {
    /// Same shape as `diffStatus` but returns the full file list (no 100-cap).
    /// Used by the inspect panel where every changed entry must badge.
    static func diffStatusFull(
        directory: String
    ) async -> (summary: GitDiffSummary, files: [GitChangedFile])
}
```

```swift
// File: tian/Workspace/Workspace.swift   (additions)
@MainActor @Observable
final class Workspace: Identifiable {
    // ... existing fields ...
    let inspectPanelState: InspectPanelState

    // Snapshot extension:
    var snapshot: WorkspaceSnapshot {
        WorkspaceSnapshot(
            id: id,
            name: name,
            defaultWorkingDirectory: defaultWorkingDirectory,
            createdAt: createdAt,
            inspectPanelVisible: inspectPanelState.isVisible,
            inspectPanelWidth: inspectPanelState.width
        )
    }
}

struct WorkspaceSnapshot: Sendable, Codable {
    let id: UUID
    let name: String
    let defaultWorkingDirectory: URL?
    let createdAt: Date
    /// Added in schema v5. Optional for back-compat with older snapshots.
    let inspectPanelVisible: Bool?
    let inspectPanelWidth: Double?
}
```

```swift
// File: tian/Persistence/SessionState.swift   (modification)
struct WorkspaceState: Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let activeSpaceId: UUID
    let defaultWorkingDirectory: String?
    let spaces: [SpaceState]
    let windowFrame: WindowFrame?
    let isFullscreen: Bool?
    /// Added in schema v5. Optional so v4 records decode without migration.
    /// Defaults applied at runtime: visible = true, width = 320.
    let inspectPanelVisible: Bool?
    let inspectPanelWidth: Double?
}
```

```swift
// File: tian/Persistence/SessionSerializer.swift   (modification)
enum SessionSerializer {
    static let currentVersion = 5   // bumped from 4 for inspect-panel fields
    // ...
}
```

```swift
// File: tian/Persistence/SessionStateMigrator.swift   (addition)
static let migrations: [Int: Migration] = [
    1: { json in json },
    2: { json in json },
    3: { /* existing v3 → v4 */ },
    // v4 → v5: Added optional `inspectPanelVisible` and `inspectPanelWidth`
    // to `WorkspaceState`. Both fields are optional so v4 decodes as nil and
    // the runtime applies defaults (true / 320) on first load.
    4: { json in json },
]
```

## 4. Test Plan

All tests use Swift Testing (`import Testing`, `@Test`, `#expect`/`#require`)
to match the existing suite conventions.

- **FR-05a** (task 2): `WorktreeKindTests.classifiesMainCheckoutAsRepo` —
  builds a temp git repo, asserts `WorktreeKind.classify` returns
  `.mainCheckout`.
- **FR-05a** (task 2): `WorktreeKindTests.classifiesLinkedWorktreeAsWorktree` —
  uses `git worktree add` then asserts `.linkedWorktree`.
- **FR-05a** (task 2): `WorktreeKindTests.classifiesNonGitDirAsLocal` — temp
  dir without `.git`.
- **FR-05a / FR-18** (task 2): `WorktreeKindTests.classifiesNilDirAsNoWorkingDirectory`.
- **FR-15 / FR-15a / FR-20** (task 4): `InspectFileScannerTests.gitTrackedReturnsTrackedAndUntrackedNotIgnored`
  — repo with a tracked file, an untracked file, and a `.gitignore`d file;
  scanner returns the first two only.
- **FR-15 / FR-22** (task 4): `InspectFileScannerTests.fileSystemFallbackEnumeratesNonGitDir`
  — empty + populated non-git dir.
- **FR-16** (task 4): `InspectFileScannerTests.dotfilesShownWhenNotIgnored` —
  `.env` is tracked / untracked-not-ignored, scanner includes it.
- **FR-17** (task 4): `InspectFileScannerTests.symlinksReturnedAsFiles` —
  symlink target not followed; entry kind is `.file`.
- **FR-19a** (task 5): `InspectFileTreeViewModelTests.statusBadgeMatchesByRelativePath`
  — feeds a `GitChangedFile(path: "auth/middleware.ts", status: .modified)`,
  expects the matching `FileTreeNode` to look up `.modified` via
  `statusByRelativePath["auth/middleware.ts"]`.
- **FR-19b** (task 5): `InspectFileTreeViewModelTests.renamedFileBadgesNewPath`
  — rename produces an `R` badge on the new path; old path is absent if
  removed from FS, `D` if still present.
- **FR-21** (task 5): `InspectFileTreeViewModelTests.directoryRowsHaveNoBadge`
  — even when descendants are modified, the dir row's `statusByRelativePath`
  lookup returns nil.
- **FR-23 / FR-26** (task 5): `InspectFileTreeViewModelTests.selectionClearsWhenPathDisappears`
  — select a row, run a scan that no longer contains it, selection becomes
  nil.
- **FR-27 / FR-28a** (task 5): `InspectFileTreeViewModelTests.setRootCancelsInFlightScan`
  — first `setRoot` starts a long scan (delayed by a fake scanner); second
  `setRoot` cancels the first and the cancelled scan never writes to
  `visibleRows`.
- **FR-28** (task 5): `InspectFileTreeViewModelTests.refreshPreservesExpansionAndSelection`
  — expand `auth/`, select `auth/tokens.ts`, push a fresh scan that still
  contains both — expansion + selection survive.
- **FR-32 / FR-34** (task 5): `InspectFileTreeViewModelTests.slowScanFlagFlipsAfterFiveSeconds`
  — fake scanner blocks; advance time, flag flips to `isInitialScanSlow`.
- **FR-29 / FR-30** (task 6): `InspectPanelStateTests.widthClampsToMinAndMax`
  — init with 100 → clamped to 240; init with 9999 → clamped to 480.
- **FR-29 / FR-30** (task 6): `InspectPanelStateTests.snapshotRoundTripsValues`
  — set isVisible=false, width=380, snapshot, decode, restore — values match.
- **PRD §7** (task 6): `SessionMigrationV4ToV5Tests.v4FileDecodesAsV5WithDefaults`
  — load a fixture v4 JSON, migrate, decode → `inspectPanelVisible == nil`
  and `inspectPanelWidth == nil` in `WorkspaceState`; the runtime restorer
  produces an `InspectPanelState(isVisible: true, width: 320)`.
- **PRD §7** (task 6): `SessionMigrationV4ToV5Tests.v5RoundTripPreservesValues`
  — encode a v5 state with non-default values, migrator passes through, decode
  matches.
- **FR-19 / no cap** (task 1): `GitStatusServiceTests.diffStatusFullReturnsAllFilesUnscapped`
  — repo with 150 changed files; `diffStatusFull` returns 150,
  `diffStatus` still returns 100.

Skeleton for the cancellation test (the one with non-trivial timing):

```swift
// FR-28a:
@Test func setRootCancelsInFlightScan() async throws {
    let vm = InspectFileTreeViewModel(scanner: BlockingScanner())
    let dir1 = try makeTempGitRepo()
    let dir2 = try makeTempGitRepo()

    vm.setRoot(URL(filePath: dir1))   // scan blocks
    vm.setRoot(URL(filePath: dir2))   // must cancel #1

    await vm.waitForFirstScan()
    #expect(vm.rootDirectory?.path == dir2)
    #expect(vm.visibleRows.allSatisfy { $0.id.hasPrefix(dir2) })
}
```

UI-layer tests (`InspectPanelView` rendering) are not added in v1 — they
would require SwiftUI snapshot infrastructure the project doesn't currently
have. UI fidelity is verified manually against `tian-inspect.jsx` per FR-03 /
FR-09 / FR-12 etc.

## 5. Tasks

1. **[model: sonnet]** GitStatusService: uncapped diff variant
   - Files: `tian/Core/GitStatusService.swift`, `tianTests/GitStatusServiceTests.swift`
   - Depends on: —
   - Done when: `diffStatusFull` returns all entries; `diffStatus` still capped at 100; new test passes.

2. **[model: sonnet]** Core types + WorktreeKind classifier
   - Files: `tian/Core/InspectPanel/WorktreeKind.swift`, `tian/Core/InspectPanel/FileTreeNode.swift`, `tian/Core/InspectPanel/InspectPanelState.swift`, `tianTests/WorktreeKindTests.swift`
   - Depends on: —
   - Done when: §3 type declarations compile; classifier tests pass; width clamping unit-verified.

3. **[model: sonnet]** Persistence: bump schema, add fields, identity migration
   - Files: `tian/Persistence/SessionState.swift`, `tian/Persistence/SessionSerializer.swift`, `tian/Persistence/SessionStateMigrator.swift`, `tian/Workspace/Workspace.swift`, `tianTests/SessionMigrationV4ToV5Tests.swift`, `tianTests/InspectPanelStateTests.swift`
   - Depends on: 2
   - Done when: `currentVersion == 5`; v4 fixture decodes through migrator and yields nil inspect-panel fields; round-trip with non-default values preserves them; existing migration tests still pass.

4. **[model: opus]** Inspect file scanner + WorkingTreeWatcher
   - Files: `tian/Core/InspectPanel/InspectFileScanner.swift`, `tian/Core/InspectPanel/WorkingTreeWatcher.swift`, `tianTests/InspectFileScannerTests.swift`
   - Depends on: 2
   - Done when: scanner correctly enumerates git-tracked + untracked-not-ignored, falls back to FileManager outside a repo, and respects `.gitignore`; watcher fires debounced callback on FS changes (timing-sensitive test marked with reasonable timeouts).

5. **[model: opus]** InspectFileTreeViewModel — scan, cancellation, selection, badge map
   - Files: `tian/Core/InspectPanel/InspectFileTreeViewModel.swift`, `tianTests/InspectFileTreeViewModelTests.swift`
   - Depends on: 1, 2, 4
   - Done when: all FR-19..FR-28a tests in §4 pass; FR-32 / FR-34 timer behavior verified.

6. **[model: sonnet]** SwiftUI views: header, status strip, file row, file browser, empty states, rail, resize handle
   - Files: every file under `tian/View/InspectPanel/*.swift` listed in §2
   - Depends on: 2, 5
   - Done when: views compile in isolation behind a `#Preview`; visual check against `tian-inspect.jsx` for header height (48 px), row height (24 px), status strip (20 px), badge colors (#f59e0b / #6ee19a / #ff9a9a / #60a5fa), selection background, hover background. No live wire-up yet.

7. **[model: opus]** Wire panel into the workspace window
   - Files: `tian/View/Sidebar/SidebarContainerView.swift`, `tian/View/InspectPanel/InspectPanelView.swift`, `tian/Workspace/Workspace.swift` (instantiation)
   - Depends on: 3, 6
   - Done when: panel renders on the trailing edge of every workspace window; toggle (× / rail) works; resize drag works and clamps; switching active spaces re-roots the tree; closing/reopening the window restores visibility + width; sidebar overlay still functions.

8. **[model: sonnet]** Active-space → file-tree wiring + git status integration
   - Files: `tian/View/InspectPanel/InspectPanelView.swift`, `tian/Tab/SpaceModel.swift` (read-only access to working dir), `tian/Tab/SpaceGitContext.swift` (subscribe to changes)
   - Depends on: 7
   - Done when: tree refreshes within 1 s of active-space switch (FR-27); badges update when `SpaceGitContext` repo status changes; non-git dirs render without badges (FR-22).

9. **[model: haiku]** Accessibility labels + final polish pass
   - Files: `tian/View/InspectPanel/InspectPanelHeader.swift`, `tian/View/InspectPanel/InspectPanelRail.swift`, `tian/View/InspectPanel/InspectPanelFileRow.swift`
   - Depends on: 8
   - Done when: VoiceOver reads each row per FR-36 and the close/rail per FR-37; no other behavior changes.

10. **[model: sonnet]** Manual smoke + regression check
    - Files: none (verification only)
    - Depends on: 9
    - Done when: open a repo with ≥1 modified, ≥1 untracked, ≥1 deleted, ≥1 renamed, ≥1 ignored file — tree shows correct badges and excludes the ignored entry; switch spaces, observe re-root + cancellation; close × → rail visible → click rail → panel restored at last width; full app relaunch preserves visibility + width; sidebar still functions; existing tests all green.

## 6. Risks & Open Questions

- **Risk: large-repo scan latency.** `git ls-files -coz` is fast even on huge
  repos but file enumeration outside git uses `FileManager`, which is slower.
  Mitigation: stream chunks and update `visibleRows` incrementally so the user
  sees results as they arrive (FR-34's incremental population). Bound by the
  perf ceiling in FR-33.
- **Risk: WorkingTreeWatcher event storms.** During an active dev server
  (Vite/Webpack rebuilds), FSEvents can fire 100+ events/sec inside
  `node_modules`-adjacent paths. Mitigation: 250 ms trailing debounce
  (matching `SpaceGitContext.refreshScheduler`) and ignore changes inside
  gitignored paths (we already filter at scan time).
- **Risk: sidebar layout regression.** `SidebarContainerView` currently uses a
  ZStack with absolute positioning for the sidebar overlay; adding a trailing
  HStack column changes intrinsic sizing semantics. Mitigation: task 7 is
  tagged `opus` precisely because the wiring is layout-sensitive; manual
  smoke verifies sidebar collapse/expand still works. If sidebar overlay
  breaks, fall back to wrapping at the `WorkspaceWindowContent` level instead.
- **Risk: `git ls-files` quirks in submodules.** Tian's working spaces don't
  currently use submodules in any documented flow, so v1 treats submodule
  contents as opaque (per `--ignore-submodules` already used in
  `diffStatus`). Mitigation: explicit non-goal noted here; revisit if a
  user reports a submodule-heavy project.
- **Open question:** Should `InspectFileTreeViewModel` live on `Workspace`
  (window-scoped) or be re-created each time the panel becomes visible?
  Current plan: window-scoped, kept alive even while hidden, so reopening
  the rail is instant. Trade-off: holds the watcher's FSEvents stream open
  while hidden — measure during smoke; if RSS impact is non-trivial, switch
  to lazy creation in a follow-up.
- **Open question:** Whether `WorkingTreeWatcher` should subscribe to
  *only* the working-tree root or also a small set of git refs to detect
  branch switches that change the tracked-file set without an FS-level
  rewrite. v1 plan: working-tree only, because branch switches *do* mutate
  the FS and FSEvents picks them up. If we see staleness reports, add a
  `SpaceGitContext` repo-status subscription as a secondary trigger (FR-27
  already says "git status changes" trigger refresh — task 8 wires this).
- **Open question:** Does the panel's `expandedPaths` need a memory ceiling?
  An adversarial repo could have millions of directories; expanding them all
  would balloon the set. v1: no cap (typical workflows expand a handful);
  revisit if anyone hits it.
