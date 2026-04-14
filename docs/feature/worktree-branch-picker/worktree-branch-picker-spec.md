# Worktree Branch Picker — Design Spec

**Date:** 2026-04-12
**Status:** Approved, ready for implementation planning
**Related:** `docs/feature/worktree-spaces/worktree-spaces-spec.md`

## 1. Summary

Extend the worktree-Space creation popover (`BranchNameInputView`) with an inline combobox that lists existing local and remote branches. The list appears below the existing textfield, filters as the user types, and lets them pick a branch without memorising its exact name.

This also fixes the original silent-failure bug: when the user types a remote-only branch name, nothing happens because `git worktree add <path> <name>` fails (no DWIM without `worktree.guessRemote=true`) and the error is swallowed by a `try?` at the call site.

## 2. Goals

- Show existing local and remote branches so the user can pick one instead of typing from memory.
- Make picking a remote-only branch work reliably, without depending on git config.
- Prevent the common "typed an existing name" mistake in New-branch mode.
- Surface errors instead of silently dropping them.

## 3. Non-goals

- Multi-remote UX. We assume a single remote (typically `origin`); the design works with multiple remotes but doesn't add dedicated UI for choosing among them.
- Branch creation from a specific commit/tag.
- Fuzzy scoring / command-palette-style ranking. Substring match only.
- Rename, delete, or other branch management operations.
- Inline display of upstream status (ahead/behind).

## 4. UX decisions (from brainstorming)

| # | Question | Choice |
|---|---|---|
| 1 | Layout | **A** — inline combobox: textfield + filtering list below |
| 2 | In-use branches | **B** — shown greyed out, not selectable, "(in use)" hint |
| 3 | Remote-only branches | **A** — auto-create local tracking branch on submit |
| 4 | New-branch mode | **C** — no full list; inline collision warning row when name conflicts |
| 5 | Sort / group | **A** — flat, recency-sorted, `local` / `origin` badge |
| 6 | Dedup | **A** — one row per branch name (local preferred when both exist) |
| 7 | Fetch | **B** — auto-fetch in background on popover open, stale-then-fresh |
| 8 | Keyboard / click | **A** — click submits; typing filters; arrow-keys + Enter submit highlighted row |

Additional rule (implied by #8 + the original bug): in "Existing branch" mode, Enter with no matching row is a no-op. Prevents the silent-failure shape from recurring.

## 5. Architecture

Two new units plus edits to three existing files. Each unit has one purpose, communicates through a narrow interface, and can be tested independently.

### 5.1 `BranchListService` — git/filesystem layer

**File:** `tian/Worktree/BranchListService.swift`

Pure, stateless, no UI dependencies. Runs off the main actor. Static methods following the `WorktreeService` pattern.

```swift
enum BranchListService {
    static func listBranches(repoRoot: String) async throws -> [BranchEntry]
    static func fetchRemotes(repoRoot: String) async throws
}
```

**Implementation notes:**

- `listBranches` issues a single `git for-each-ref --sort=-committerdate refs/heads refs/remotes --format=<name>%00<upstream>%00<committerdate:iso-strict>%00<objectname>` call. Parses the NUL-separated output into raw entries.
- `git worktree list --porcelain` is parsed to produce the set of branches currently checked out in any worktree. That set is used to flag `isInUse` and `isCurrent` on each entry.
- `fetchRemotes` runs `git fetch --all --prune`. Throws `WorktreeError.gitError` on failure so the view model can degrade gracefully.
- No caching layer. Every `load` re-reads from disk — git's own pack/loose-ref access is fast enough for the expected scale (hundreds of branches).

### 5.2 `BranchEntry` — model

**File:** same as service (`tian/Worktree/BranchListService.swift`).

```swift
struct BranchEntry: Identifiable, Hashable, Sendable {
    let id: String              // "local:feat/auth" or "origin:feat/auth"
    let displayName: String     // "feat/auth"
    let kind: Kind
    let committerDate: Date
    let isInUse: Bool           // checked out in any worktree
    let isCurrent: Bool         // HEAD of any worktree

    enum Kind: Hashable, Sendable {
        case local(upstream: String?)   // upstream e.g. "origin/feat/auth" if tracking
        case remote(remoteName: String) // e.g. "origin"
    }
}
```

Dedup is *not* done here — the service returns raw entries. Dedup is a view-layer concern.

### 5.3 `BranchListViewModel` — presentation state

**File:** `tian/View/Worktree/BranchListViewModel.swift`

`@MainActor @Observable`. Holds the filtered, sorted, deduped view of branches that the SwiftUI view renders.

**Public interface:**

```swift
@MainActor @Observable
final class BranchListViewModel {
    enum Mode { case newBranch, existingBranch }

    var query: String = ""
    var mode: Mode = .newBranch
    private(set) var isFetching: Bool = false
    private(set) var loadError: String?
    private(set) var rows: [BranchRow] = []      // already filtered+deduped+sorted
    private(set) var highlightedID: String?      // id of currently highlighted row

    func load(repoRoot: String) async
    func moveHighlight(_ direction: Direction)   // up/down, skips in-use rows
    func selectedRow() -> BranchRow?             // highlighted row if selectable
    func collision(for query: String) -> BranchRow?  // for new-branch mode warning
}
```

**`BranchRow` (presentation model):**

```swift
struct BranchRow: Identifiable, Hashable {
    let id: String                  // stable id, survives re-sort
    let displayName: String
    let badge: Badge                // .local, .origin, .localAndOrigin
    let relativeDate: String        // "2h ago", "yesterday"
    let committerDate: Date         // for sort stability
    let isInUse: Bool
    let isCurrent: Bool
    let remoteRef: String?          // "origin/feat/x" when this row is a remote-only pick

    enum Badge { case local, origin(String), localAndOrigin(String) }
}
```

**Dedup rule:**
- If both `local:foo` and `origin:foo` exist, emit one row with `badge = .localAndOrigin("origin")`, `remoteRef = nil` (picking this row uses the local branch directly).
- `local:foo` only → `.local`, `remoteRef = nil`.
- `origin:foo` only → `.origin("origin")`, `remoteRef = "origin/foo"`.

**Filter rule:** case-insensitive substring match on `displayName`. First matching row is auto-highlighted; setting `query` recomputes `rows` and updates `highlightedID`.

**Load flow:**

```swift
func load(repoRoot: String) async {
    // Step 1: cache-only read — fast path, populates the list immediately
    await reload(repoRoot: repoRoot)

    // Step 2: kick off background fetch, reload when it finishes
    isFetching = true
    defer { isFetching = false }
    do {
        try await BranchListService.fetchRemotes(repoRoot: repoRoot)
        await reload(repoRoot: repoRoot)
    } catch {
        Log.worktree.info("Remote fetch failed, using cached remotes: \(error)")
        // silent fallback — rows already populated from cache
    }
}
```

**Highlight skip logic:** `moveHighlight(.down)` finds the next row where `!isInUse`. Wraps at the end of the list (circular). Same for `.up`.

### 5.4 Edits — `BranchNameInputView`

**File:** `tian/View/Worktree/BranchNameInputView.swift`

New state: `@State private var viewModel = BranchListViewModel()`.

Callback signature changes:
```swift
// before
let onSubmit: (String, Bool) -> Void
// after
let onSubmit: (String, Bool, String?) -> Void   // (branchName, isExisting, remoteRefToTrack)
```

**Layout additions (below existing textfield, above the resolved-path line):**

- In `.existingBranch` mode: a scrollable `List` of `BranchRow`s, max height 200pt. Each row: badge + displayName + relative date (right-aligned, dimmed). In-use rows have `.opacity(0.4)` and `.allowsHitTesting(false)`, with an italic "(in use)" suffix. Current-worktree row also shows italic "(current)".
- In `.newBranch` mode: no list. If `viewModel.collision(for: query) != nil`, show a single warning row: "⚠ `<name>` already exists as `<badge>`".
- A muted footer spinner+label "Syncing remotes…" while `isFetching` is true. Replaced by "Using cached remotes" if `fetchRemotes` failed.

**Keyboard handling:**

- `.onKeyPress(.upArrow) { viewModel.moveHighlight(.up); return .handled }`
- `.onKeyPress(.downArrow) { viewModel.moveHighlight(.down); return .handled }`
- `.onSubmit` (existing): dispatch to `handleSubmit`
- `.onExitCommand` (existing): cancel

**Click:** tapping a row calls `submit(row:)` directly — single-click submits.

The existing `@State private var branchName: String` is removed — the TextField binds directly to `$viewModel.query`. The existing `@State private var isExistingBranch: Bool` remains; the Picker pushes its value into `viewModel.mode` via `.onChange`.

**`handleSubmit` rewrite:**

```swift
private func handleSubmit() {
    let trimmed = viewModel.query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }

    switch (isExistingBranch, viewModel.selectedRow()) {
    case (true, nil):
        return   // existing mode, no valid row — no-op (prevents original bug)
    case (true, let row?) where row.isInUse:
        return   // defensive: shouldn't reach here since in-use rows can't be highlighted
    case (true, let row?):
        onSubmit(row.displayName, true, row.remoteRef)
    case (false, _):
        onSubmit(trimmed, false, nil)   // new-branch mode: submit raw text
    }
}
```

Loads branches when the view appears, tied to the repo root from the `repoRoot` prop:
```swift
.task { await viewModel.load(repoRoot: repoRoot.path) }
```

### 5.5 Edits — `WorkspaceWindowContent`

**File:** `tian/View/Workspace/WorkspaceWindowContent.swift`

Two changes:

1. Update the `onSubmit` closure to accept and forward `remoteRef`:
   ```swift
   onSubmit: { branch, existing, remoteRef in
       branchInputContext = nil
       Task {
           do {
               _ = try await worktreeOrchestrator.createWorktreeSpace(
                   branchName: branch,
                   existingBranch: existing,
                   remoteRef: remoteRef
               )
           } catch {
               worktreeOrchestrator.presentError(error)
           }
       }
   }
   ```

2. Bind an `.alert` to the orchestrator's `lastError`:
   ```swift
   .alert(
       "Worktree creation failed",
       isPresented: Binding(
           get: { worktreeOrchestrator.lastError != nil },
           set: { if !$0 { worktreeOrchestrator.lastError = nil } }
       ),
       presenting: worktreeOrchestrator.lastError
   ) { _ in
       Button("OK", role: .cancel) {}
   } message: { err in
       Text(err.localizedDescription)
   }
   ```

### 5.6 Edits — `WorktreeOrchestrator`

**File:** `tian/Worktree/WorktreeOrchestrator.swift`

Add:

```swift
var lastError: WorktreeError?

func presentError(_ error: Error) {
    if let wErr = error as? WorktreeError {
        lastError = wErr
    } else {
        lastError = .gitError(command: "unknown", stderr: error.localizedDescription)
    }
}
```

Extend `createWorktreeSpace` signature:

```swift
func createWorktreeSpace(
    branchName: String,
    existingBranch: Bool = false,
    remoteRef: String? = nil,
    repoPath: String? = nil,
    workspaceID: UUID? = nil
) async throws -> WorktreeCreateResult
```

Behavior:
- When `remoteRef != nil`, skip the pre-flight `branchExists` check (we already know it doesn't exist locally).
- Pass `remoteRef` through to `WorktreeService.createWorktree`.

### 5.7 Edits — `WorktreeService.createWorktree`

**File:** `tian/Worktree/WorktreeService.swift`

Accept an optional `remoteRef`:

```swift
static func createWorktree(
    repoRoot: String,
    worktreeDir: String,
    branchName: String,
    existingBranch: Bool,
    remoteRef: String? = nil
) async throws -> String
```

Argument construction:

```swift
var args: [String]
if let remoteRef {
    args = ["worktree", "add", "--track", "-b", branchName, worktreePath, remoteRef]
} else if existingBranch {
    args = ["worktree", "add", worktreePath, branchName]
} else {
    args = ["worktree", "add", worktreePath, "-b", branchName]
}
```

The rest of the method (error parsing, logging) is unchanged.

## 6. Data flow

```
Popover opens
   └─► BranchListViewModel.load(repoRoot)
           ├─► BranchListService.listBranches()         (cache-only, fast)
           └─► Task { fetchRemotes(); listBranches() }  (background refresh)

User types "feat"
   └─► viewModel.query = "feat"
           └─► filteredRows recompute (substring match on displayName)
                  └─► View re-renders, first match auto-highlighted

User presses Enter (or clicks a row)
   ├─ Existing mode, no match     → no-op
   ├─ Existing mode, in-use row   → unreachable (not highlightable)
   ├─ Existing mode, local row    → onSubmit(displayName, true, nil)
   ├─ Existing mode, remote row   → onSubmit(displayName, true, "origin/<name>")
   └─ New-branch mode             → onSubmit(query, false, nil)

WorkspaceWindowContent.onSubmit
   └─► worktreeOrchestrator.createWorktreeSpace(…, remoteRef:)
           └─► WorktreeService.createWorktree(…, remoteRef:)
                  └─► git worktree add [--track -b <branch>] <path> [<remoteRef> | <branch>]
```

## 7. Error handling

| Failure | Behavior |
|---|---|
| `createWorktreeSpace` throws | `presentError` → alert sheet, popover stays dismissed |
| `listBranches` throws | `loadError` set, empty-state row: "Couldn't load branches — <reason>". User can still submit as New branch |
| `fetchRemotes` throws | Silent fallback to cached remotes, footer reads "Using cached remotes", logged at `.info` |
| Branch becomes in-use between list and submit | Git returns error, surfaced via alert |
| Empty repo (no branches) | Single empty-state row: "No branches yet" |
| Query with zero matches | Single row: "No matching branches"; Enter is no-op in existing mode |

## 8. Testing

All under `tianTests/`. No UI tests (per project policy — manual verification only).

### 8.1 `BranchListServiceTests.swift`

Integration tests against real on-disk git repo fixtures via a `GitRepoFixture` helper.

- `listBranches_returnsLocalAndRemoteBranches`
- `listBranches_marksInUseBranches`
- `listBranches_marksCurrentHead`
- `listBranches_handlesEmptyRepo`
- `fetchRemotes_succeedsAgainstLocalBareRepo`
- `fetchRemotes_failureIsLocalisedError`

### 8.2 `BranchListViewModelTests.swift`

Pure-Swift unit tests. To avoid invoking the real git layer, extract a thin protocol:

```swift
protocol BranchListProviding {
    func listBranches(repoRoot: String) async throws -> [BranchEntry]
    func fetchRemotes(repoRoot: String) async throws
}
```

`BranchListService` conforms to it by forwarding to its existing static methods (via a trivial value-type wrapper). `BranchListViewModel` takes a `BranchListProviding` in its init (defaulting to the service wrapper). Tests inject a fake conforming type.

- `dedup_collapsesLocalAndRemoteWithSameName`
- `dedup_keepsRemoteOnlyBranches`
- `filter_isCaseInsensitiveSubstring`
- `filter_autoHighlightsFirstMatch`
- `highlightedRow_skipsInUseBranches`
- `collision_triggersInNewBranchMode`
- `load_showsCacheImmediately_thenRefreshesAfterFetch`

### 8.3 `WorktreeServiceTests.swift` (extended)

- `createWorktree_withRemoteRef_usesTrackAndBranchFlags`
- `createWorktree_fromRemoteOnlyBranch_createsLocalTrackingBranch`

### 8.4 `WorktreeOrchestratorTests.swift` (extended)

- `createWorktreeSpace_withRemoteRef_skipsBranchExistsPreflight`
- `createWorktreeSpace_onGitError_setsLastError`

### 8.5 Manual verification

- Open popover on a repo with ≥5 local, ≥5 remote branches. Confirm list populates quickly from cache.
- Trigger `git fetch` in the background; confirm new remote appears in the list after fetch finishes.
- Pick a local branch — confirm worktree created at `<branch>` with local branch checked out.
- Pick a remote-only branch — confirm worktree created with a new local tracking branch of the same name.
- Type an in-use branch name — confirm row is greyed and not highlightable; Enter is a no-op.
- In "New branch" mode, type the name of an existing branch — confirm warning row appears; Enter still creates (or fails via alert if git refuses).
- Force a failure (e.g., unplug network during fetch) — confirm "Using cached remotes" footer; popover remains usable.
- Force a worktree creation failure (e.g., pick a branch, then delete its ref externally before Enter) — confirm alert appears.

## 9. File summary

| File | Change |
|---|---|
| `tian/Worktree/BranchListService.swift` | **New** — `BranchEntry` + `BranchListService` |
| `tian/View/Worktree/BranchListViewModel.swift` | **New** — presentation model |
| `tian/View/Worktree/BranchNameInputView.swift` | Edit — integrate combobox, update `onSubmit` signature |
| `tian/View/Workspace/WorkspaceWindowContent.swift` | Edit — forward `remoteRef`, bind error alert |
| `tian/Worktree/WorktreeOrchestrator.swift` | Edit — `remoteRef` param, `lastError`, `presentError` |
| `tian/Worktree/WorktreeService.swift` | Edit — `remoteRef` param in `createWorktree` |
| `tianTests/BranchListServiceTests.swift` | **New** |
| `tianTests/BranchListViewModelTests.swift` | **New** |
| `tianTests/Support/GitRepoFixture.swift` | **New** (if not already present) |
| `tianTests/WorktreeServiceTests.swift` | Edit — add 2 tests |
| `tianTests/WorktreeOrchestratorTests.swift` | Edit — add 2 tests |

Remember to run `xcodegen generate` after adding new source files.
