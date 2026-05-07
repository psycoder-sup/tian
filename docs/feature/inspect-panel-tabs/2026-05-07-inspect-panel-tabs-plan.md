# Plan: Inspect Panel — Files / Diff / Branch Tabs (v2)

**Date:** 2026-05-07
**Status:** Approved
**Based on:** docs/feature/inspect-panel-tabs/2026-05-07-inspect-panel-tabs-prd.md

---

## 1. Approach

The v2 chrome replaces v1's single 48 px header with a 38 px **tab row**
+ 26 px **info strip**, and routes the panel body to one of three
sibling views (`Files`, `Diff`, `Branch`). v1's `InspectPanelView` /
`InspectPanelHeader` / `InspectPanelFileBrowser` already hold the file-
tree behaviour we keep; this plan rewires the header layer and adds two
new bodies + the data services that feed them.

Five load-bearing decisions:

1. **Tab state lives above SwiftUI.** A new `@MainActor @Observable
   InspectTabState` (FR-T28b) is owned by `Workspace` next to
   `inspectPanelState`. It carries `activeTab`, `diffCollapse: [String:
   Bool]`, and the in-memory caches the Diff and Branch view-models
   read. SwiftUI per-tab body views never own `@State` for anything
   that must survive a tab switch — scroll position is restored by
   `ScrollViewReader` named anchors (`"diff-top"`, `"branch-top"`) on
   `.onAppear`. This is the *only* way FR-T04 (tab state survives
   round-trip) compiles correctly.

2. **Diff fetch is its own scheduler bucket.** v1's
   `SpaceGitContext.refreshScheduler` fires on a 250 ms FSEvents
   debounce and is shared with the sidebar; piggy-backing the Diff tab
   on it will cause `git diff HEAD` storms during dev-server churn.
   FR-T18 mandates a separate **≥500 ms trailing debounce + cancel-on-
   new** for `unifiedDiff`. Implementation: a per-`Workspace` actor
   (`InspectDiffViewModel`) holds an in-flight `Task` and a debounce
   timer, mirroring `SpaceGitContext.refreshRepo`'s
   `inFlightTasks[repoID]?.cancel()` pattern. The diff is fed from the
   active space's `SpaceGitContext` repo-status observable (Files-tab-
   identical trigger surface) but routed through this private
   debounce.

3. **Branch fetch needs a watcher predicate that doesn't exist.** FR-
   T28a requires a `GitRepoWatcher.pathsAffectBranchGraph` predicate
   parallel to `pathsAffectPRState`. We add it — matching paths under
   `<commonDir>/refs/heads/`, `<commonDir>/HEAD`, and `<commonDir>/
   packed-refs` — and wire it into `SpaceGitContext`'s existing FSEvents
   callback. A new per-repo `branchGraphDirty: Set<GitRepoID>` flag
   stored on `SpaceGitContext` is set by the watcher and cleared by
   the Branch view-model after a successful refetch. This avoids
   working-tree FSEvents triggering branch-graph fetches.

4. **Two new GitStatusService methods, two new typed payloads.**
   `unifiedDiff(directory:)` calls `git diff --no-color --no-ext-diff
   --unified=3 HEAD` plus `git status --porcelain` for untracked files,
   gates each untracked path on a 512 KB size check (FR-T10a) before
   `git diff --no-index`, and returns `[GitFileDiff]`. `commitGraph
   (directory:)` issues exactly **three** subprocesses — `git log`,
   `git for-each-ref`, `git tag -l --format='%(objectname:short)
   %(refname:short)'` — and assembles a `GitCommitGraph` with lane
   assignment + 6-lane cap (FR-T20a). Both methods follow the existing
   `runGit` cancellation pattern and live in the same file as
   `diffStatus` / `diffStatusFull` so the queueing and error-logging
   conventions match.

5. **Persistence: schema bump v5 → v6, identity migration.** The only
   newly-persisted field is `activeTab: String?` on `WorkspaceState`
   (FR-T29 / FR-T31). Schema bumps from 5 → 6, and the v5 → v6
   migration is identity (`{ json in json }`) — same precedent as v1's
   v4 → v5 bump. Diff collapse map and graph cache stay in-memory.

The view layer reuses v1 widgets where possible: the existing
`InspectPanelEmptyContentView` / `InspectPanelLoadingView` are reused
for empty / loading bodies; the file row, file browser, and rail are
unchanged. The new views (`InspectPanelTabRow`, `InspectPanelInfoStrip`,
`InspectDiffBody`, `InspectBranchBody`) follow the same monospace +
0.5 px-divider + glass-gradient vocabulary v1 already established.

## 2. File-by-file Changes

| File | Change | Notes |
|------|--------|-------|
| `tian/Core/InspectPanel/InspectTab.swift` | new | `enum InspectTab: String, Codable, Sendable, CaseIterable { case files, diff, branch }`. |
| `tian/Core/InspectPanel/InspectTabState.swift` | new | `@MainActor @Observable final class InspectTabState` — owns `activeTab`, `diffCollapse`, plus references to `InspectDiffViewModel` / `InspectBranchViewModel`. |
| `tian/Core/InspectPanel/InspectDiffViewModel.swift` | new | `@MainActor @Observable` view-model. Owns the latest `[GitFileDiff]`, in-flight `Task`, debounce timer, and per-file collapse state surface. Implements FR-T18. |
| `tian/Core/InspectPanel/InspectBranchViewModel.swift` | new | `@MainActor @Observable` view-model. Owns the latest `GitCommitGraph`, in-flight task, and dirty-flag handshake with `SpaceGitContext`. Implements FR-T20 / FR-T20a / FR-T26 / FR-T28. |
| `tian/Core/GitTypes.swift` | modify | Add `GitFileDiff`, `GitDiffHunk`, `GitDiffLine` (with `Kind` nested enum), `GitCommitGraph`, `GitLane`, `GitCommit` per PRD §3 specs. All `Sendable` + `Equatable`. |
| `tian/Core/GitStatusService.swift` | modify | Add `unifiedDiff(directory:) async -> [GitFileDiff]` and `commitGraph(directory:) async -> GitCommitGraph?`. Internal helpers: `parseUnifiedDiff(_:)`, `parseCommitGraph(log:refs:tags:)`, `assignLanes(commits:headRef:trackedRemote:cap:)` (FR-T20a). Untracked-binary gate via `FileManager.attributesOfItem` before `git diff --no-index`. |
| `tian/Core/GitRepoWatcher.swift` | modify | Add `static func pathsAffectBranchGraph(_ paths: [String], canonicalCommonDir: String) -> Bool` mirroring `pathsAffectPRState`. Matches `<commonDir>/refs/heads/*`, `<commonDir>/HEAD`, `<commonDir>/packed-refs`. |
| `tian/Tab/SpaceGitContext.swift` | modify | In FSEvents callback, also call `pathsAffectBranchGraph` and set `branchGraphDirty: Set<GitRepoID>` (new published field). Expose `clearBranchGraphDirty(repoID:)` for the Branch view-model. |
| `tian/Workspace/Workspace.swift` | modify | Add `let inspectTabState: InspectTabState`. Initialize from `WorkspaceState.activeTab`. Snapshot extension round-trips the new field. Hold strong references to the per-workspace `InspectDiffViewModel` and `InspectBranchViewModel` instances (lazily wired against the active space's `SpaceGitContext`). |
| `tian/Persistence/SessionState.swift` | modify | Add `let activeTab: String?` to `WorkspaceState`. Optional so v5 records decode unchanged. |
| `tian/Persistence/SessionSerializer.swift` | modify | Bump `currentVersion` 5 → 6. Round-trip `activeTab` from `Workspace.inspectTabState.activeTab.rawValue`. |
| `tian/Persistence/SessionStateMigrator.swift` | modify | Add `migrations[5] = { json in json }` (identity — optional field, runtime defaults). Update comment to document the v6 addition. |
| `tian/View/InspectPanel/InspectPanelTabRow.swift` | new | 38 px tab row: capsule-pill `Files` / `Diff` / `Branch` segmented control on left (glass gradient on active), inspect-panel hide button on right (FR-T01 / FR-T02 / FR-T03). Disabled (muted, `.allowsHitTesting(false)`) for Diff/Branch during initial scan (FR-T16a). |
| `tian/View/InspectPanel/InspectPanelInfoStrip.swift` | new | 26 px info strip; switches content per active tab (FR-T06 / FR-T07 / FR-T08): `{spaceName} · {worktreeKind.label}` for Files, `{N} files +{add} −{del}` for Diff, `{branch} · graph` for Branch. Empty / no-repo state per FR-T19. |
| `tian/View/InspectPanel/InspectPanelHeader.swift` | modify | Replace v1's single-pill body. New header is a `VStack(spacing: 0) { InspectPanelTabRow; InspectPanelInfoStrip }` — total chrome 64 px (FR-T01). The old `filesPill` / `spaceLabel` markup is removed. |
| `tian/View/InspectPanel/InspectPanelFileBrowser.swift` | modify | Drop the in-body `subheader` (v1 FR-11) — content moved to `InspectPanelInfoStrip` (FR-T09). The `LazyVStack` of rows starts immediately. |
| `tian/View/InspectPanel/InspectDiffBody.swift` | new | Diff tab body. `ScrollViewReader { ScrollView { LazyVStack { ForEach(viewModel.files) { GitDiffFileGroup } } } }`. Anchor id `"diff-top"`. Uses `viewModel.collapsed[file.path]` from `InspectTabState`. |
| `tian/View/InspectPanel/GitDiffFileGroup.swift` | new | Single file's diff group: 28 px header (chevron, status dot, path, status word, +/− counts), then per-hunk header bar + per-line grid (`[old #][new #][marker][text]`) per FR-T11 / FR-T12 / FR-T13. Tints from PRD design tokens. |
| `tian/View/InspectPanel/InspectBranchBody.swift` | new | Branch tab body. `LazyVStack` of `BranchCommitRow` over `viewModel.graph.commits`, with an SVG-equivalent `Canvas` overlay for lane rails + parent edges (FR-T22). Lane legend at top (FR-T23). Anchor id `"branch-top"`. |
| `tian/View/InspectPanel/BranchCommitRow.swift` | new | One commit row: 38 px tall, short SHA + subject + branch chip(s) + tag chip + author/time/merge meta footer (FR-T21). |
| `tian/View/InspectPanel/InspectPanelView.swift` | modify | Switch on `tabState.activeTab` to pick `InspectPanelFileBrowser` / `InspectDiffBody` / `InspectBranchBody`. Pass `tabState`, `diffViewModel`, `branchViewModel`. During `isInitialScanInFlight` force `activeTab = .files` for rendering and tell the tab row to mute Diff/Branch (FR-T16a). |
| `tian/View/InspectPanel/InspectPanelStatusStrip.swift` | modify | Accept `activeTab: InspectTab` input; render `files · {space}` / `diff · {space}` / `branch · {space}` accordingly (FR-T35). Wire it back into `InspectPanelView.body` (today it lives in the file but isn't rendered). |
| `tian/View/Sidebar/SidebarContainerView.swift` | modify | Forward `inspectTabState` + the two new view-models when constructing `InspectPanelView`. Subscribe `inspectDiffStatusTask` to active-space `SpaceGitContext.repoStatuses` to drive Diff refresh; subscribe to `branchGraphDirty` to drive Branch refresh. |
| `tianTests/GitStatusServiceUnifiedDiffTests.swift` | new | Verifies parser, untracked-as-added, 512 KB binary gate, `Binary file, N bytes` placeholder, 5 000-line per-file cap with `… N more lines` placeholder, gitignored files excluded. |
| `tianTests/GitStatusServiceCommitGraphTests.swift` | new | Verifies 3-subprocess shape (no per-SHA tag calls), HEAD-first lane order, lane cap at 6 with "other" lane, tag dict lookup by short SHA, detached HEAD short-SHA branch label, empty repo (HEAD only). |
| `tianTests/GitRepoWatcherBranchGraphTests.swift` | new | `pathsAffectBranchGraph` returns true for `refs/heads/*`, `HEAD`, `packed-refs`; false for `refs/remotes/*` (PR predicate's domain), working-tree files, unrelated paths. |
| `tianTests/SpaceGitContextBranchDirtyTests.swift` | new | A simulated FSEvents batch hitting `refs/heads/feature` flips `branchGraphDirty`; one hitting only working-tree files does not. `clearBranchGraphDirty` removes the flag. |
| `tianTests/InspectDiffViewModelTests.swift` | new | Cancel-in-flight when a new `refresh(directory:)` arrives mid-run; ≥500 ms trailing debounce coalesces a burst; collapse map survives a refresh when the file is still present, drops when the file disappears (FR-T18, FR-T11). |
| `tianTests/InspectBranchViewModelTests.swift` | new | Lane assignment: HEAD's lane first, tracked remote next, ties broken alphabetically; lane cap = 6 with surplus lanes folded into "other"; merge-commit hollow-node flag set; `branchGraphDirty` clears after fetch. |
| `tianTests/InspectTabStateTests.swift` | new | `activeTab` defaults to `.files`; round-trips through `WorkspaceState.activeTab` String; nil persisted value yields `.files` (FR-T29 default for pre-v6 records). |
| `tianTests/SessionMigrationV5ToV6Tests.swift` | new | A v5 fixture decodes through migrator → `WorkspaceState.activeTab == nil`; runtime restorer produces `InspectTabState(activeTab: .files)`. v6 round-trip with non-default `activeTab = .diff` preserves the value. |

## 3. Types & Interfaces

```swift
// File: tian/Core/InspectPanel/InspectTab.swift
import Foundation

enum InspectTab: String, Codable, Sendable, CaseIterable {
    case files, diff, branch
}
```

```swift
// File: tian/Core/InspectPanel/InspectTabState.swift
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class InspectTabState {
    var activeTab: InspectTab
    var diffCollapse: [String: Bool] = [:]   // path → collapsed

    let diffViewModel: InspectDiffViewModel
    let branchViewModel: InspectBranchViewModel

    init(
        activeTab: InspectTab = .files,
        diffViewModel: InspectDiffViewModel = InspectDiffViewModel(),
        branchViewModel: InspectBranchViewModel = InspectBranchViewModel()
    ) {
        self.activeTab = activeTab
        self.diffViewModel = diffViewModel
        self.branchViewModel = branchViewModel
    }
}
```

```swift
// File: tian/Core/GitTypes.swift  (additions only — keeps existing types untouched)

struct GitFileDiff: Sendable, Equatable {
    let path: String
    let status: GitFileStatus
    let additions: Int
    let deletions: Int
    let hunks: [GitDiffHunk]
    /// True when the file was skipped because it failed the 512 KB binary
    /// gate or `git diff` reported it as binary. `hunks` is empty in this
    /// case; `additions` / `deletions` reflect git's reported counts (or 0
    /// for the size-gated case).
    let isBinary: Bool
}

struct GitDiffHunk: Sendable, Equatable {
    let header: String   // `@@ -A,B +C,D @@ optional context`
    let lines: [GitDiffLine]
    /// Set when the hunk's emitted line count was capped at 5 000. Renderer
    /// shows a muted `… N more lines` placeholder line below.
    let truncatedLines: Int
}

struct GitDiffLine: Sendable, Equatable {
    enum Kind: Sendable, Equatable { case context, added, deleted }
    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}

struct GitCommitGraph: Sendable, Equatable {
    /// Ordered, HEAD's lane first; surplus lanes (FR-T20a) collapse into a
    /// single trailing lane with `id == "__other__"`.
    let lanes: [GitLane]
    /// Newest → oldest, max 50 entries (FR-T20).
    let commits: [GitCommit]
    /// Number of branch tips folded into the trailing "other" lane. 0 when
    /// the cap was not hit.
    let collapsedLaneCount: Int
}

struct GitLane: Sendable, Equatable {
    let id: String         // branch ref name, or "__other__"
    let label: String
    let colorIndex: Int    // resolved to a Color by the view from a fixed palette
    let isCollapsed: Bool  // true only for the "other" lane
}

struct GitCommit: Sendable, Equatable {
    let sha: String        // 40-char
    let shortSha: String   // 7-char
    let laneIndex: Int     // index into `GitCommitGraph.lanes`
    let parentShas: [String]
    let author: String
    let when: Date
    let subject: String
    let isMerge: Bool
    let headRefs: [String] // e.g. ["feature-auth", "origin/main"]
    let tag: String?
}
```

```swift
// File: tian/Core/GitStatusService.swift  (additions)
extension GitStatusService {
    /// Returns the working-tree-vs-HEAD diff for the active space's repo.
    /// Untracked files are included as fully-added entries; files larger
    /// than 512 KB or reported as binary by git produce a `GitFileDiff`
    /// with `isBinary == true` and no hunks. Each file's `lines` array is
    /// capped at 5 000 entries; hunks past the cap set `truncatedLines`.
    /// Returns `[]` when not inside a git repo.
    static func unifiedDiff(directory: String) async -> [GitFileDiff]

    /// Returns the commit graph rooted at HEAD for the active space's repo.
    /// Walks back up to 50 commits along first-parent of all local branch
    /// tips; lanes capped at 6 (FR-T20a). Returns `nil` when not inside a
    /// git repo. Issues exactly three subprocess calls: `git log`,
    /// `git for-each-ref`, `git tag -l`.
    static func commitGraph(directory: String) async -> GitCommitGraph?
}
```

```swift
// File: tian/Core/GitRepoWatcher.swift  (addition)
extension GitRepoWatcher {
    /// True if any event path indicates a local-ref or HEAD change — i.e. a
    /// commit, branch switch, or `packed-refs` rewrite that invalidates the
    /// commit graph. Mirrors `pathsAffectPRState`. `canonicalCommonDir`
    /// must already be resolved via `canonicalizedPath`.
    static func pathsAffectBranchGraph(
        _ paths: [String],
        canonicalCommonDir: String
    ) -> Bool
}
```

```swift
// File: tian/Tab/SpaceGitContext.swift  (additions only)
@MainActor @Observable
final class SpaceGitContext {
    // ... existing fields ...

    /// Set of repos whose branch graph has been invalidated by an FSEvents
    /// batch since the last successful Branch-tab fetch. The Branch view-
    /// model reads + clears this. Working-tree-only events do NOT add to
    /// this set.
    private(set) var branchGraphDirty: Set<GitRepoID> = []

    func clearBranchGraphDirty(repoID: GitRepoID)
}
```

```swift
// File: tian/Core/InspectPanel/InspectDiffViewModel.swift
import Foundation
import Observation

@MainActor @Observable
final class InspectDiffViewModel {
    private(set) var files: [GitFileDiff] = []
    private(set) var isLoadingInitial: Bool = false
    private(set) var lastDirectory: String?

    /// Coalescing trailing debounce window (FR-T18). 500 ms.
    static let debounce: Duration = .milliseconds(500)

    /// Asks the view-model to refresh against `directory`. Coalesces calls
    /// inside the debounce window; cancels any in-flight diff before
    /// starting a new one.
    func scheduleRefresh(directory: String?)

    /// Tears down debounce + in-flight task. Called on space switch /
    /// workspace close.
    func teardown()

    private var inFlightTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
}
```

```swift
// File: tian/Core/InspectPanel/InspectBranchViewModel.swift
import Foundation
import Observation

@MainActor @Observable
final class InspectBranchViewModel {
    private(set) var graph: GitCommitGraph?
    private(set) var isLoadingInitial: Bool = false
    private(set) var lastDirectory: String?

    /// Asks the view-model to refresh. Unlike Diff this does NOT debounce
    /// on file events — it is driven by `SpaceGitContext.branchGraphDirty`
    /// transitions and direct calls (tab activation, space switch).
    func scheduleRefresh(directory: String?, repoID: GitRepoID?, in context: SpaceGitContext?)

    /// Tears down the in-flight task.
    func teardown()

    private var inFlightTask: Task<Void, Never>?
}
```

```swift
// File: tian/Workspace/Workspace.swift  (additions)
@MainActor @Observable
final class Workspace: Identifiable {
    // ... existing fields ...
    let inspectTabState: InspectTabState

    var snapshot: WorkspaceSnapshot {
        WorkspaceSnapshot(
            // ... existing fields ...
            inspectPanelVisible: inspectPanelState.isVisible,
            inspectPanelWidth: inspectPanelState.width,
            activeTab: inspectTabState.activeTab.rawValue
        )
    }
}

struct WorkspaceSnapshot: Sendable, Codable {
    // ... existing fields including v5 inspect-panel fields ...
    /// Added in schema v6. Optional for back-compat with v5 snapshots.
    /// Decoded values that don't match `InspectTab.rawValue` fall back to
    /// `.files` at runtime.
    let activeTab: String?
}
```

```swift
// File: tian/Persistence/SessionState.swift  (modification)
struct WorkspaceState: Codable, Sendable, Equatable {
    // ... existing fields including v5 inspect-panel fields ...
    /// Added in schema v6. Optional so v5 records decode without migration.
    /// Default applied at runtime: activeTab = .files.
    let activeTab: String?
}
```

```swift
// File: tian/Persistence/SessionSerializer.swift  (modification)
enum SessionSerializer {
    static let currentVersion = 6   // bumped from 5 for activeTab field
    // ...
}
```

```swift
// File: tian/Persistence/SessionStateMigrator.swift  (addition)
static let migrations: [Int: Migration] = [
    1: { json in json },
    2: { json in json },
    3: { /* existing v3 → v4 */ },
    4: { json in json },   // existing v4 → v5
    // v5 → v6: Added optional `activeTab: String?` to `WorkspaceState`. The
    // field is optional so v5 decodes as nil; the runtime applies the
    // default (`.files`) on load.
    5: { json in json },
]
```

## 4. Test Plan

All new tests use Swift Testing (`import Testing`, `@Test`, `#expect` /
`#require`) — same conventions as the existing `tianTests/` suite.

- **FR-T10 / FR-T15** (task 3): `GitStatusServiceUnifiedDiffTests.parsesAddDeleteContextLines`
  — temp repo with one staged + one unstaged change; assert the resulting
  `GitFileDiff` has correct `additions`, `deletions`, line kinds, and
  `oldLineNumber` / `newLineNumber` values.
- **FR-T10 / FR-T15** (task 3): `GitStatusServiceUnifiedDiffTests.untrackedFilesAppearAsAdded`
  — untracked text file shows as `status == .added` with every line as
  `.added`.
- **FR-T10a** (task 3): `GitStatusServiceUnifiedDiffTests.binaryGate512KB`
  — untracked file at 600 KB never spawns `git diff --no-index`; result
  has `isBinary == true` and empty `hunks`.
- **FR-T10a** (task 3): `GitStatusServiceUnifiedDiffTests.gitReportedBinaryFlagged`
  — staged binary blob (e.g. PNG) returns `isBinary == true`; we never
  parse "Binary files differ" as line text.
- **FR-T15** (task 3): `GitStatusServiceUnifiedDiffTests.linesCapsAt5000`
  — synthetic file with 6 000 changed lines yields capped `lines.count`
  per hunk and `truncatedLines == 1000` summed across the file.
- **FR-T10** (task 3): `GitStatusServiceUnifiedDiffTests.gitignoredFilesExcluded`
  — `.gitignore`d file does not appear.
- **FR-T20 / FR-T25** (task 4): `GitStatusServiceCommitGraphTests.threeSubprocessesOnly`
  — instrument `runGit` with a counter (test-only injection or fake
  shell); assert exactly 3 invocations per `commitGraph`.
- **FR-T20** (task 4): `GitStatusServiceCommitGraphTests.headLaneFirst`
  — repo with 3 active branches; HEAD's branch is `lanes[0]`.
- **FR-T20a** (task 4): `GitStatusServiceCommitGraphTests.laneCapAtSixWithOther`
  — repo with 9 active branch tips inside the 50-commit window; result
  has 7 lanes (6 named + 1 `__other__`); `collapsedLaneCount == 3`.
- **FR-T20a** (task 4): `GitStatusServiceCommitGraphTests.lanePriorityOrdering`
  — HEAD lane first, tracked-remote second, then most-commits, then
  alphabetical; verified with a constructed-priority repo.
- **FR-T25** (task 4): `GitStatusServiceCommitGraphTests.tagsResolvedFromBulkCall`
  — repo with 5 tags including one on HEAD; each tagged commit's
  `tag` field is populated, no per-SHA `git tag` invocation.
- **FR-T20** (task 4): `GitStatusServiceCommitGraphTests.detachedHEADUsesShortSha`
  — checkout an arbitrary SHA; the active commit's branch label is its
  7-char short SHA.
- **FR-T28a** (task 5): `GitRepoWatcherBranchGraphTests.matchesLocalRefsAndHEAD`
  — `["<commonDir>/refs/heads/feature", "<commonDir>/HEAD",
  "<commonDir>/packed-refs"]` each return `true`.
- **FR-T28a** (task 5): `GitRepoWatcherBranchGraphTests.ignoresRemoteRefsAndWorkingTree`
  — `<commonDir>/refs/remotes/origin/main`, working-tree files, and
  unrelated paths return `false`.
- **FR-T28a** (task 6): `SpaceGitContextBranchDirtyTests.refHeadsBatchSetsDirty`
  — simulate a watcher batch hitting `refs/heads/feature`; assert the
  repo's `GitRepoID` is in `branchGraphDirty`.
- **FR-T28a** (task 6): `SpaceGitContextBranchDirtyTests.workingTreeBatchDoesNotSetDirty`
  — simulate a batch hitting only working-tree files; `branchGraphDirty`
  remains empty.
- **FR-T28a** (task 6): `SpaceGitContextBranchDirtyTests.clearRemovesEntry`
  — `clearBranchGraphDirty` removes the repo from the set.
- **FR-T18** (task 7): `InspectDiffViewModelTests.cancelsInFlightOnNewRefresh`
  — schedule with `directory: A` (blocks via fake service), then schedule
  with `directory: B`; the first task is cancelled; only B's result lands
  in `files`.
- **FR-T18** (task 7): `InspectDiffViewModelTests.debounceCoalescesBurst`
  — 5 calls within 100 ms produce exactly 1 fetch; the call ≥500 ms
  later produces a second fetch.
- **FR-T11** (task 7): `InspectDiffViewModelTests.collapseMapSurvivesRefreshWhenFilePresent`
  — collapse `auth/middleware.ts`; refresh; the collapse flag persists
  in `InspectTabState.diffCollapse`. Then refresh with the file removed;
  the entry is dropped.
- **FR-T20a / FR-T25** (task 8): `InspectBranchViewModelTests.assemblesGraphFromService`
  — fake `commitGraph` returns a 3-lane graph; view-model's `graph`
  matches.
- **FR-T28** (task 8): `InspectBranchViewModelTests.dirtyFlagDrivesRefresh`
  — set `branchGraphDirty` on the fake `SpaceGitContext`; view-model
  triggers a fetch and clears the flag on success.
- **FR-T29 / FR-T31** (task 1): `SessionMigrationV5ToV6Tests.v5FileMigratesToV6Defaults`
  — load a v5 fixture; migrator output has `activeTab == nil`; runtime
  restorer produces `InspectTabState(activeTab: .files)`.
- **FR-T29** (task 1): `SessionMigrationV5ToV6Tests.roundTripPreservesNonDefault`
  — v6 state with `activeTab = .diff` round-trips through encoder +
  migrator + decoder unchanged.
- **FR-T29** (task 2): `InspectTabStateTests.defaultsToFiles`
  — `InspectTabState()` has `activeTab == .files`.
- **FR-T29** (task 2): `InspectTabStateTests.unknownRawValueFallsBackToFiles`
  — restorer with `activeTab: "garbage"` from disk yields `.files`.

UI-layer tests are not added (matches v1 plan precedent — no SwiftUI
snapshot infra). Visual fidelity for FR-T01 / T02 / T06–T09 / T11–T13 /
T21–T23 is verified manually against the design bundle's `Inspect
Panel.html` + `tian-inspect-v2.jsx` during task 11.

Skeleton for the cancel-on-new test:

```swift
// FR-T18:
@Test func cancelsInFlightOnNewRefresh() async throws {
    let fake = BlockingDiffService()
    let vm = InspectDiffViewModel(service: fake)

    vm.scheduleRefresh(directory: "A")
    try await Task.sleep(for: .milliseconds(50))
    vm.scheduleRefresh(directory: "B")

    fake.releaseAll()
    await vm.waitForFirstResult()
    #expect(vm.lastDirectory == "B")
    #expect(fake.cancelledDirectories == ["A"])
}
```

## 5. Tasks

1. **[model: sonnet]** Persistence: schema bump v5 → v6, add `activeTab` field
   - Files: `tian/Persistence/SessionState.swift`,
     `tian/Persistence/SessionSerializer.swift`,
     `tian/Persistence/SessionStateMigrator.swift`,
     `tianTests/SessionMigrationV5ToV6Tests.swift`
   - Depends on: —
   - Done when: `currentVersion == 6`; v5 fixture migrates to v6 with
     `activeTab == nil`; round-trip with `activeTab = "diff"` preserves;
     existing v4 → v5 + earlier migration tests still pass.

2. **[model: haiku]** Core types: `InspectTab` enum + `InspectTabState`
   - Files: `tian/Core/InspectPanel/InspectTab.swift`,
     `tian/Core/InspectPanel/InspectTabState.swift`,
     `tianTests/InspectTabStateTests.swift`
   - Depends on: —
   - Done when: enum + state class compile; default `.files`; unknown
     raw-value falls back to `.files`. (View-model fields can be
     placeholder protocols for now — task 7/8 fill them in.)

3. **[model: sonnet]** GitStatusService: `unifiedDiff` + diff types + binary gate
   - Files: `tian/Core/GitTypes.swift` (Diff types only),
     `tian/Core/GitStatusService.swift`,
     `tianTests/GitStatusServiceUnifiedDiffTests.swift`
   - Depends on: —
   - Done when: parser handles add/delete/context lines + hunk headers
     with correct line numbers; untracked files appear as added; 512 KB
     gate works; git's "Binary files differ" marker yields `isBinary`;
     5 000-line cap engages with `truncatedLines` set; gitignored files
     excluded.

4. **[model: sonnet]** GitStatusService: `commitGraph` + commit types + lane assignment
   - Files: `tian/Core/GitTypes.swift` (CommitGraph types only),
     `tian/Core/GitStatusService.swift`,
     `tianTests/GitStatusServiceCommitGraphTests.swift`
   - Depends on: —
   - Done when: exactly 3 subprocess calls per fetch; HEAD lane first;
     6-lane cap with `__other__` lane; tag resolution from bulk call
     dict; detached-HEAD short-SHA branch label.

5. **[model: haiku]** GitRepoWatcher: `pathsAffectBranchGraph` predicate
   - Files: `tian/Core/GitRepoWatcher.swift`,
     `tianTests/GitRepoWatcherBranchGraphTests.swift`
   - Depends on: —
   - Done when: predicate matches `refs/heads/*`, `HEAD`, `packed-refs`;
     ignores `refs/remotes/*` and working-tree paths.

6. **[model: sonnet]** SpaceGitContext: branch-graph dirty flag + watcher wiring
   - Files: `tian/Tab/SpaceGitContext.swift`,
     `tianTests/SpaceGitContextBranchDirtyTests.swift`
   - Depends on: 5
   - Done when: FSEvents callback adds the repoID to `branchGraphDirty`
     iff `pathsAffectBranchGraph` returns true; `clearBranchGraphDirty`
     removes; existing PR-cache eviction path unaffected.

7. **[model: opus]** `InspectDiffViewModel`: in-flight cancel + 500 ms debounce + collapse map
   - Files: `tian/Core/InspectPanel/InspectDiffViewModel.swift`,
     `tianTests/InspectDiffViewModelTests.swift`
   - Depends on: 2, 3
   - Done when: cancel-on-new-refresh works; 500 ms trailing debounce
     coalesces bursts; collapse map persists across refresh when file is
     present and drops when file disappears; `teardown` cancels
     everything.

8. **[model: opus]** `InspectBranchViewModel`: graph fetch + dirty-flag handshake
   - Files: `tian/Core/InspectPanel/InspectBranchViewModel.swift`,
     `tianTests/InspectBranchViewModelTests.swift`
   - Depends on: 2, 4, 6
   - Done when: graph populates from `commitGraph`; dirty-flag transition
     in `SpaceGitContext` triggers refresh and clears the flag on
     success; teardown cancels.

9. **[model: sonnet]** SwiftUI views: tab row, info strip, status strip update
   - Files: `tian/View/InspectPanel/InspectPanelTabRow.swift`,
     `tian/View/InspectPanel/InspectPanelInfoStrip.swift`,
     `tian/View/InspectPanel/InspectPanelStatusStrip.swift` (modify),
     `tian/View/InspectPanel/InspectPanelHeader.swift` (modify),
     `tian/View/InspectPanel/InspectPanelFileBrowser.swift` (modify —
     drop subheader)
   - Depends on: 2
   - Done when: views compile under `#Preview`; visual check vs design
     for tab-row glass gradient, info-strip per-tab content, 64 px total
     chrome; status strip shows `files`/`diff`/`branch` correctly;
     accessibility labels per FR-T32 with SwiftUI primitives.

10. **[model: opus]** SwiftUI Diff + Branch bodies, plumbed into `InspectPanelView`
    - Files: `tian/View/InspectPanel/InspectDiffBody.swift`,
      `tian/View/InspectPanel/GitDiffFileGroup.swift`,
      `tian/View/InspectPanel/InspectBranchBody.swift`,
      `tian/View/InspectPanel/BranchCommitRow.swift`,
      `tian/View/InspectPanel/InspectPanelView.swift` (modify),
      `tian/View/Sidebar/SidebarContainerView.swift` (modify),
      `tian/Workspace/Workspace.swift` (modify — instantiate
      `InspectTabState` + view-models)
    - Depends on: 1, 7, 8, 9
    - Done when: tabs route to correct body; Diff body renders
      collapsible groups with hunk headers + line gutters per design
      tokens; Branch body renders lane gutter, parent edges, HEAD ring,
      branch + tag chips, and the lane legend; `ScrollViewReader`
      preserves scroll across tab switches; FR-T16a muting fires during
      initial scan; active space's `SpaceGitContext` is wired to both
      view-models for refresh.

11. **[model: haiku]** Polish + accessibility + manual smoke
    - Files: any of the new view files (a11y label tweaks),
      `InspectPanelTabRow.swift`, `BranchCommitRow.swift`,
      `GitDiffFileGroup.swift`
    - Depends on: 10
    - Done when: VoiceOver reads each tab button correctly (FR-T32),
      diff group headers per FR-T33, branch rows per FR-T34; manual
      smoke against a real repo: switch tabs (state survives), view a
      diff with one binary file (placeholder shown), open a repo with
      ≥7 active branches (lane cap engages, "other" lane visible),
      stage a commit and confirm Branch tab refreshes within ~1 s of
      the ref move, save a file rapidly and confirm Branch does not
      refetch on FS-only changes, app relaunch restores last `activeTab`.

## 6. Risks & Open Questions

- **Risk: `git diff HEAD` cost on warm vs cold packs.** The 500 ms
  debounce + cancel-on-new mitigates queue depth, but a single fetch
  on a cold pack can still take 1–2 s on a large repo. Mitigation: log
  the duration during smoke (task 11) and consider a 750 ms debounce
  if worst-case feedback feels laggy. Ceiling stays bounded — it's a
  configurable constant.
- **Risk: untracked-binary detection on encrypted volumes / sandboxed
  paths.** `FileManager.attributesOfItem` can fail with permission
  errors on macOS sandboxed paths. Mitigation: treat any `.fileSize`
  read failure the same as the >512 KB case (`isBinary = true`,
  no diff) — fail closed, never spawn the subprocess. Coded into the
  `unifiedDiff` parser, covered by a test in task 3.
- **Risk: lane assignment on long-lived repos.** The 6-lane cap +
  alphabetic tiebreaker is deterministic but may surprise users whose
  preferred branch falls outside the priority window. Mitigated by
  the FR-T20a info-strip `+N more` count; the open-question
  "user-pinned lanes" backlog item in the PRD §8 is the long-term
  fix.
- **Risk: tab-row hide button vs floating window-edge rail.** Both
  exist in v1. The plan keeps both: in-row button for *hide* while
  open, floating rail for *re-open* when closed. Smoke verifies
  there's no double-toggle when the floating rail is over the in-row
  button — `InspectPanelRail` is anchored to the window's trailing
  edge with `padding(.trailing, 10)`, while the in-row button sits
  inside the panel's own trailing edge, so they don't visually
  collide.
- **Risk: `Canvas` performance for branch edges.** SwiftUI `Canvas`
  redraws on every observation tick; with 50 commits and 6 lanes
  that's ~300 path segments. Mitigation: wrap the `Canvas` in
  `.drawingGroup()` so it Metal-rasterizes once per graph change. If
  it shows up in profiling, fall back to pre-rasterized `Image`
  cached on `GitCommitGraph` identity.
- **Open question:** should `InspectDiffViewModel` and
  `InspectBranchViewModel` live on `Workspace` (window-scoped, kept
  alive while panel is hidden) or be re-created when the relevant
  tab becomes active? Plan: window-scoped, mirroring v1's
  `InspectFileTreeViewModel`. Trade-off: keeps the in-flight task
  channels open even while the user is on the Files tab. If memory
  shows up, switch to lazy creation in a follow-up.
- **Open question:** does the `__other__` collapsed lane need to
  expand on click in v2? Plan: no — clicking is a no-op (FR-T24
  reads "clicking a row is a no-op"). If users complain, "Show
  more" / "Expand other" follows in a future revision.
- **Open question:** the Diff tab info strip's `{N} files +{add}
  −{del}` totals — should they exclude binary-gated files (which
  contribute 0 add/0 del) or count them (with their git-reported
  totals if any)? Plan: include them with whatever counts git
  reports; binary placeholders show in the body but are visible in
  the totals. Revisit if it confuses.
- **Open question:** does the schema bump risk colliding with any
  in-flight v5 → v6 migration the user might land separately?
  Project has only one active schema chain in `SessionStateMigrator`,
  and `currentVersion` is currently 5, so no collision. Worth a
  re-check at PR review time.
