# SPEC: Sidebar Git & Claude Session Status

**Based on:** docs/feature/sidebar-status/sidebar-status-prd.md v1.3
**Author:** CTO Agent
**Date:** 2026-04-08
**Version:** 1.1
**Status:** Approved

### Version History
| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-04-08 | Initial draft |
| 1.1 | 2026-04-08 | Spec review fixes: separate sessionStates storage (non-breaking), lazy SpaceGitContext detection for non-worktree Spaces, in-flight task cancellation, changedFiles cap at 100, concrete rainbowColors access change, restored-session init wiring, gh pr view deduplication, GitRepoID as struct, time injection for PRStatusCache tests |

---

## 1. Overview

This spec covers the implementation of a rich status area in each sidebar Space row (`SidebarSpaceRowView`) that combines per-pane Claude Code session dots with per-repository git status information (branch name, diff summary badges, PR state). The feature introduces three new service-layer types (`GitStatusService`, `GitRepoWatcher`, `PRStatusCache`), extends the existing `PaneStatusManager` with a parallel `sessionStates` dictionary for typed session state tracking (without modifying the existing `PaneStatus` struct), adds a new `SpaceGitContext` observable model that maintains the per-Space repository pinning with lazy detection for non-worktree Spaces and in-flight task cancellation, and replaces the current single-line status label in `SidebarSpaceRowView` with a multi-line status area driven by these new data sources.

The implementation fits into the existing architecture by following established patterns: `@MainActor @Observable` for new model types, `NotificationCenter`-based event flow for OSC 7 pwd changes, background subprocess execution via the same `Process` + `DispatchQueue.global` pattern used in `WorktreeService`, and the existing `PaneStatusManager` singleton for per-pane state storage. No new IPC commands are introduced -- Claude session state flows through the `status.set --state` extension defined in the Claude Session Status PRD (v1.3, Approved, not yet implemented).

---

## 2. Data Layer

### 2.1 PaneStatusManager Extension

The existing `PaneStatusManager` (at `aterm/Models/PaneStatusManager.swift`) must be extended to track typed session state alongside the existing free-form label. Currently it stores `[UUID: PaneStatus]` where `PaneStatus` has `label: String` (non-optional) and `updatedAt: Date`.

**New enum: `ClaudeSessionState`**

| Case | Raw String | Priority (1 = highest) | Description |
|------|-----------|----------------------|-------------|
| `needsAttention` | `"needs_attention"` | 1 | Claude blocked on permission prompt |
| `busy` | `"busy"` | 2 | Claude actively working |
| `active` | `"active"` | 3 | Session started, no prompt yet |
| `idle` | `"idle"` | 4 | Waiting for user input |
| `inactive` | `"inactive"` | 5 | Session ended (dot not shown) |

The enum should conform to `Sendable`, `Equatable`, `Comparable` (by priority), and `CaseIterable`. It should be initializable from a raw string value, returning nil for unrecognized values.

**PaneStatus struct: NO changes.** The existing `PaneStatus` struct retains its current shape: `label: String` (non-optional) and `updatedAt: Date`. This preserves all existing tests and callers without any breaking changes.

**Separate session state storage:** Add a new private dictionary `sessionStates: [UUID: ClaudeSessionState]` to `PaneStatusManager`, alongside the existing `statuses: [UUID: PaneStatus]` dictionary. Session state and label state are stored independently -- they share the same pane ID key space but live in separate dictionaries.

**New PaneStatusManager methods:**

| Method | Description |
|--------|-------------|
| `setSessionState(paneID:state:)` | Sets the session state for a pane in the `sessionStates` dictionary. Does not create or modify any entry in the `statuses` dictionary. Logs old and new state at debug level via `Log.ipc`. |
| `clearSessionState(paneID:)` | Removes the session state entry for a pane from `sessionStates`. Does not affect `statuses`. |
| `sessionState(for:)` | Returns the session state for a single pane from `sessionStates`, or nil if absent. |
| `sessionStates(in:)` | Returns all `(paneID, ClaudeSessionState)` pairs across all panes in a Space that have non-nil, non-inactive state. Iterates all tabs and all leaves in each tab's split tree (same traversal as existing `latestStatus(in:)`). |

**Existing method changes:**
- `setStatus(paneID:label:)` remains completely unchanged. It only writes to `statuses`.
- `clearStatus(paneID:)` now clears both the `statuses` entry AND the `sessionStates` entry for the pane. This ensures cleanup on pane close removes all associated state.
- `clearAll(for:)` now clears both `statuses` and `sessionStates` entries for the given pane IDs.
- `latestStatus(in:)` remains completely unchanged -- it only reads from `statuses` and returns `PaneStatus?`. No semantic change, no breaking change.

### 2.2 IPCCommandHandler Extension

The existing `handleStatusSet` method in `IPCCommandHandler` (at `aterm/Core/IPCCommandHandler.swift`, line 419) currently requires a `label` parameter. Per the Claude Session Status PRD FR-005 through FR-008:

- Accept an optional `state` parameter in addition to `label`.
- At least one of `label` or `state` must be provided.
- If `state` is provided, validate against the `ClaudeSessionState` enum. Return error with valid values list if unrecognized.
- If `state` is provided, call `statusManager.setSessionState(paneID:state:)`.
- If `label` is provided, call `statusManager.setStatus(paneID:label:)` as before.
- Both can be provided in a single call.

The `handleStatusClear` method clears both label and session state (calls existing `clearStatus`).

### 2.3 SpaceGitContext (New Observable)

A new `@MainActor @Observable` class that maintains the per-Space git repository context. One instance per `SpaceModel`. This is the core orchestrator that ties pane working directories to git repos, manages FSEvents watchers, and exposes git status data for the view layer.

**Placement:** `aterm/Models/SpaceGitContext.swift`

**Owned by:** `SpaceModel` (as an `@Observable` property, created in `SpaceModel.init`). The context object itself is always created eagerly; repo detection within the context is lazy for non-worktree Spaces (see Initialization below).

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `repoStatuses` | `[GitRepoID: GitRepoStatus]` | Map of detected repos to their current status. `GitRepoID` is the canonicalized `--git-common-dir` path. Observable -- drives sidebar re-renders. |
| `paneRepoAssignments` | `[UUID: GitRepoID?]` | Maps each pane ID to its detected repo (or nil for non-repo panes). Not directly observed by views but used internally. |
| `pinnedRepoOrder` | `[GitRepoID]` | Ordered list of pinned repos. First element is the `worktreePath`-derived repo if applicable. Additional repos in alphabetical order. |
| `inFlightTasks` | `[GitRepoID: Task<Void, Never>]` | Tracks in-flight refresh tasks per repo. Used for cancellation on rapid re-triggers. Private/internal to the class. |

**GitRepoID type:** A struct wrapping a `String` path: `struct GitRepoID: Hashable, Sendable { let path: String }`. This is consistent with the codebase convention of using distinct types for identifiers (e.g., `UUID` for model IDs rather than plain strings). The `path` value is the canonicalized absolute path from `git rev-parse --git-common-dir`. Two panes in the same repo (even different worktrees of the same repo) share the same `GitRepoID`.

**GitRepoStatus struct:**

| Field | Type | Description |
|-------|------|-------------|
| `repoID` | `GitRepoID` | Canonical repo root |
| `branchName` | `String?` | Current branch name or abbreviated SHA for detached HEAD |
| `isDetachedHead` | `Bool` | True when HEAD is detached |
| `diffSummary` | `GitDiffSummary` | Counts of modified, added, deleted, renamed, unmerged files |
| `changedFiles` | `[GitChangedFile]` | Changed files for popover display. Capped at 100 entries at the `GitStatusService.diffStatus` parsing level (see Section 2.4). The view further truncates display at 30. |
| `prStatus` | `PRStatus?` | Cached GitHub PR status, or nil |
| `lastUpdated` | `Date` | Timestamp of last successful git status query |

**GitDiffSummary struct:**

| Field | Type |
|-------|------|
| `modified` | `Int` |
| `added` | `Int` |
| `deleted` | `Int` |
| `renamed` | `Int` |
| `unmerged` | `Int` |

Computed property `isEmpty: Bool` returns true when all counts are zero.

**GitChangedFile struct:**

| Field | Type | Description |
|-------|------|-------------|
| `status` | `GitFileStatus` (enum: M, A, D, R, U) | Single-letter change type |
| `path` | `String` | File path relative to repo root |

**PRStatus struct:**

| Field | Type | Description |
|-------|------|-------------|
| `state` | `PRState` (enum: open, draft, merged, closed) | PR state |
| `url` | `URL` | PR URL for opening in browser |

**Key methods on SpaceGitContext:**

| Method | Description |
|--------|-------------|
| `paneWorkingDirectoryChanged(paneID:newDirectory:)` | Called when a pane's OSC 7 reports a new working directory. Runs git repo detection on background thread. Updates `paneRepoAssignments`. May add a new repo to pinned context or unpin an abandoned repo. Triggers initial git status + PR fetch for newly detected repos. |
| `paneAdded(paneID:workingDirectory:)` | Called when a new pane is created in this Space. Triggers repo detection for the pane's initial working directory. |
| `paneRemoved(paneID:)` | Called when a pane is closed. Updates `paneRepoAssignments`. If no other pane references the pane's former repo, unpins that repo and stops its FSEvents watcher. |
| `refresh()` | Manually triggers a git status refresh for all pinned repos. Called when the Space becomes active (FR-062). |
| `teardown()` | Cancels all in-flight tasks, stops all FSEvents watchers, evicts PR cache, and clears state. Called on Space close. |

**Initialization and lazy detection:** `SpaceGitContext` is initialized with the Space's `worktreePath`, `defaultWorkingDirectory`, and `workspaceDefaultDirectory`. However, repo detection on init depends on the type of Space:

- **Worktree-backed Spaces** (where `worktreePath` is non-nil): Repo detection happens eagerly on init, since the path to the git repo is known and stable. The `worktreePath` is used directly for initial `detectRepo` and monitoring.
- **Non-worktree Spaces** (regular Spaces): Repo detection is deferred. The init does NOT attempt repo detection. Instead, detection happens lazily when the first real working directory arrives via one of two paths: (a) the `paneWorkingDirectoryChanged` callback fires from an OSC 7 report, or (b) `paneAdded` is called with a valid working directory path. This avoids speculative repo detection against potentially stale or generic initial paths (e.g., `$HOME`).

There will be a brief period after non-worktree Space creation where no git status is shown, until a pane reports its working directory via OSC 7. This is expected and acceptable.

**Restored-session init path:** When `SpaceModel` is initialized via the restore constructor (`init(id:name:tabs:activeTabID:defaultWorkingDirectory:)`), it must wire `onPaneDirectoryChanged` for each restored tab (same as the regular init wires `wireDirectoryFallback`). Additionally, for each restored tab, the init must call `SpaceGitContext.paneAdded(paneID:workingDirectory:)` for each leaf pane that has a known working directory. This ensures that restored sessions detect repos from their persisted pane working directories rather than waiting for the first OSC 7 event.

**In-flight task management:** `SpaceGitContext` maintains an `inFlightTasks: [GitRepoID: Task<Void, Never>]` dictionary. Each refresh operation (triggered by FSEvents, Space activation, or initial detection) cancels any existing in-flight task for that repo before dispatching a new one. This prevents stale result ordering bugs during rapid branch switches -- if two refreshes fire in quick succession, the first task's results are discarded via cooperative cancellation (`Task.isCancelled` checks before writing to `repoStatuses`). The new task replaces the entry in `inFlightTasks`. When a task completes (success or cancellation), it removes its own entry from `inFlightTasks`.

### 2.4 GitStatusService (New)

A stateless service (enum with static methods, following the `WorktreeService` pattern at `aterm/Worktree/WorktreeService.swift`) that wraps git and gh CLI subprocess calls. All methods are `async` and run on background threads.

**Placement:** `aterm/Core/GitStatusService.swift`

**Methods:**

| Method | Signature (described) | Description |
|--------|----------------------|-------------|
| `detectRepo` | Takes a directory path string. Returns an optional tuple of `(gitDir: String, commonDir: String)` or nil if not a git repo. | Runs `git rev-parse --git-dir` and `git rev-parse --git-common-dir` from the given directory. Returns nil on non-zero exit code (directory not in a git repo). |
| `currentBranch` | Takes a directory path string. Returns an optional string. | Runs `git symbolic-ref --short HEAD` from the directory. On failure (detached HEAD), falls back to `git rev-parse --short HEAD` for the abbreviated SHA. Returns nil on total failure. |
| `diffStatus` | Takes a directory path string. Returns a tuple of `(summary: GitDiffSummary, files: [GitChangedFile])`. | Runs `git status --porcelain=v1 --ignore-submodules` from the directory. Parses the two-character status codes from each line. Maps XY codes to the M/A/D/R/U categories. The `GitDiffSummary` totals always reflect the full count of all changed files. However, the `files` array is capped at 100 entries -- parsing stops appending to `files` after 100 entries but continues counting for the summary totals. Since the view only displays 30 files plus an "N more" count, 100 entries provides ample headroom while bounding memory usage for repos with thousands of changes. |
| `fetchPRStatus` | Takes a directory path string and branch name. Returns optional `PRStatus`. | Runs `gh pr view --json state,url,isDraft` from the directory. Parses JSON output. Maps `isDraft` to `.draft` state. Returns nil on any failure (gh not installed, not authenticated, not GitHub, no PR). Has a 10-second timeout (NFR-006). |

**Subprocess execution pattern:** Uses the same `Process` + `DispatchQueue.global(qos: .userInitiated)` + `withCheckedThrowingContinuation` pattern as `WorktreeService.runGit`. The implementation should extract a shared helper or reuse `WorktreeService.runGit` if it can be made internal/package-accessible. If not, duplicate the subprocess runner pattern within `GitStatusService`.

**git status parsing logic:** The `--porcelain=v1` output has format `XY path` where X is the staging area status and Y is the working tree status. The mapping to PRD categories:

| Porcelain Code(s) | PRD Category |
|-------------------|-------------|
| `M` in X or Y position | M (Modified) |
| `?` in both X and Y (untracked) | A (Added) |
| `A` in X position | A (Added) |
| `D` in X or Y position | D (Deleted) |
| `R` in X position | R (Renamed) |
| `U` in X or Y, or both modified in merge | U (Unmerged) |

A file should be counted once in the highest-priority category if it appears in multiple.

**Timeout for git status:** If `git status` takes longer than 5 seconds (FR-064), the pending result is discarded and the previous status remains. This is implemented by adding a `Task.sleep`-based timeout wrapper around the subprocess call. The previous `GitRepoStatus` in `SpaceGitContext.repoStatuses` stays unchanged.

**Timeout for gh:** 10-second timeout (NFR-006). Same pattern.

### 2.5 GitRepoWatcher (New)

Manages FSEvents streams for git repository directories. One watcher instance per detected repo per Space.

**Placement:** `aterm/Core/GitRepoWatcher.swift`

**Design:** Uses `DispatchSource.makeFileSystemObjectSource` (or `FSEventStreamCreate` via CoreServices) to watch the `.git` directory (or linked gitdir for worktrees). The PRD specifies FSEvents (FR-060), and `DispatchSource.makeFileSystemObjectSource` is the Swift-native way to do this on macOS.

However, `DispatchSource.makeFileSystemObjectSource` monitors a single file descriptor and does not recursively watch subdirectories. For `.git/` monitoring where we need to detect changes to `HEAD`, `refs/`, and `index`, the CoreServices `FSEventStream` API is more appropriate as it recursively monitors directory trees. The implementation should use `FSEventStreamCreate` via the CoreServices C API, wrapped in a Swift class.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `watchPaths` | `[String]` | Paths being monitored. For regular repos: `[".git/"]`. For worktrees: `[linkedGitDir, commonDir + "/refs/"]` per FR-069. |
| `onChangeDetected` | `() -> Void` | Callback fired (debounced) when filesystem changes are detected. |

**Debounce:** The FSEvents stream is configured with a latency of 2.0 seconds (FR-061), which provides built-in debouncing. `FSEventStreamCreate` accepts a `latency` parameter that coalesces events within the specified window before delivering them. This naturally satisfies NFR-003 (no more than one callback per 2-second window).

**Lifecycle:**
- Created when a repo is first detected for a Space.
- The FSEvents stream starts immediately upon creation.
- Stopped and deallocated when the repo is unpinned from the Space (no panes reference it) or when the Space is closed.
- All Spaces with detected repos have active watchers, not just the active Space (FR-068).

**Watch path resolution (FR-069):**
- Call `GitStatusService.detectRepo(directory:)` which returns `(gitDir, commonDir)`.
- If `gitDir` is `.git` (relative) or ends with `/.git`: this is a regular repo. Watch path is the absolute `.git/` directory.
- If `gitDir` is an absolute path containing `/worktrees/`: this is a linked worktree. Watch both `gitDir` (the linked gitdir) AND `commonDir + "/refs/"` to catch branch updates from other worktrees.

### 2.6 PRStatusCache (New)

A simple in-memory cache for `gh pr view` results with a 60-second TTL per the PRD FR-056.

**Placement:** `aterm/Core/PRStatusCache.swift`

**Design:** `@MainActor @Observable` singleton (or per-`SpaceGitContext` instance -- per-context is preferred for lifecycle management per FR-056.6).

**Constructor parameter:** `PRStatusCache` accepts a `now: @Sendable () -> Date` parameter (defaulting to `{ Date() }`). This clock function is used for all TTL checks, enabling deterministic testing of expiry behavior without real-time waits.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `entries` | Dictionary keyed by `CacheKey` (struct with `repoID: GitRepoID` and `branch: String`, conforming to `Hashable`) to `CacheEntry` | Cached PR results |
| `pending` | `Set<CacheKey>` | Keys for which a `fetchPRStatus` call is currently in flight. Used to deduplicate concurrent requests. |

**CacheEntry struct:**

| Field | Type | Description |
|-------|------|-------------|
| `prStatus` | `PRStatus?` | The cached result (nil means "no PR found") |
| `fetchedAt` | `Date` | When the result was fetched |

**Methods:**

| Method | Description |
|--------|-------------|
| `get(repoID:branch:)` | Returns the cached `PRStatus?` if the entry exists and is within the 60-second TTL (checked via the `now()` clock). Returns a sentinel "cache miss" value (distinct from "no PR") if expired or absent. |
| `set(repoID:branch:status:)` | Stores a cache entry with the timestamp from `now()`. Also removes the key from `pending`. |
| `markPending(repoID:branch:)` | Adds the key to `pending`. Returns `true` if the key was not already pending (caller should proceed with fetch). Returns `false` if already pending (caller should skip, the in-flight call will populate the cache). |
| `clearPending(repoID:branch:)` | Removes the key from `pending`. Called on fetch failure to allow retry. |
| `evictAll()` | Clears all entries and all pending keys. Called on Space close (FR-056.6). |

**Deduplication flow:** Before dispatching `fetchPRStatus`, the caller checks `markPending(repoID:branch:)`. If it returns `false`, the fetch is skipped because an identical request is already in flight. When the fetch completes (success or failure), `set(repoID:branch:status:)` or `clearPending(repoID:branch:)` is called respectively, which removes the key from `pending` and allows future fetches.

The cache is checked before every `gh pr view` call. On cache miss, a fresh query is dispatched (if not already pending). On cache hit, the cached result is used. When the branch name changes (detected during git status refresh), the new branch triggers a fresh query immediately (cache miss for the new key). The old branch's entry naturally expires after 60 seconds but is not proactively evicted.

### 2.7 Data Flow

The complete data flow for a git status update:

1. **FSEvents fires** for a watched `.git/` directory (or linked gitdir / common refs).
2. **GitRepoWatcher** delivers the debounced callback to **SpaceGitContext**.
3. **SpaceGitContext** cancels any existing in-flight task for this repo (from `inFlightTasks[repoID]`), then creates a new `Task` that dispatches async calls to **GitStatusService** on a background thread: `currentBranch(directory:)` and `diffStatus(directory:)`. The new task is stored in `inFlightTasks[repoID]`.
4. If the branch name differs from the previous value, **SpaceGitContext** checks **PRStatusCache** for the new branch. On cache miss, calls `markPending(repoID:branch:)` -- if not already pending, dispatches `GitStatusService.fetchPRStatus(directory:branch:)`.
5. If the branch name is unchanged and within the 60-second TTL, the cached PR result is reused (FR-056.4).
6. Before writing results, the task checks `Task.isCancelled`. If cancelled, results are discarded (stale). Otherwise, **SpaceGitContext** updates `repoStatuses[repoID]` with the new `GitRepoStatus` on the main actor and removes the task from `inFlightTasks`.
7. **SidebarSpaceRowView** observes `SpaceGitContext.repoStatuses` and re-renders the status area.

The complete data flow for a Claude session state change:

1. Claude Code hook fires `aterm-cli status set --state busy`.
2. IPC arrives at `IPCCommandHandler.handleStatusSet`.
3. Handler calls `PaneStatusManager.setSessionState(paneID:state:)`.
4. `PaneStatusManager` (being `@Observable`) triggers observation updates.
5. **SidebarSpaceRowView** accesses `PaneStatusManager.shared.sessionStates(in: space)` and re-renders the dots.

The complete data flow for a pane working directory change:

1. Shell reports new working directory via OSC 7.
2. `GhosttyApp.surfacePwdNotification` is posted.
3. `PaneViewModel` observes it and calls `splitTree.updateWorkingDirectory(paneID:newWorkingDirectory:)`.
4. A new notification (or direct callback) informs `SpaceGitContext.paneWorkingDirectoryChanged(paneID:newDirectory:)`.
5. `SpaceGitContext` runs repo detection on the new directory, updates `paneRepoAssignments`, and may add/remove repo lines.

---

## 3. API Layer

### 3.1 IPC Command Changes

**`status.set` extension:**

The existing command at `IPCCommandHandler.handleStatusSet` (line 419) currently requires `label`. The change:

- Extract `label` from params (optional, was required).
- Extract `state` from params (optional, new).
- If neither `label` nor `state` is provided, return error: "Missing required parameter: at least one of 'label' or 'state' must be provided."
- If `state` is provided, validate against `ClaudeSessionState.init(rawValue:)`. On failure, return error: "Invalid state: '\(value)'. Valid values: active, busy, idle, needs_attention, inactive."
- If `state` is valid, call `statusManager.setSessionState(paneID:state:)`.
- If `label` is provided, call `statusManager.setStatus(paneID:label:)`.

**`status.clear` (unchanged behavior):** Already clears via `clearStatus(paneID:)` which will now also clear session state.

### 3.2 No New IPC Commands

Per the PRD, git status is read locally by aterm. No new IPC commands are introduced for git operations.

### 3.3 GitStatusService Static Methods

These are async static methods (not IPC), following the `WorktreeService` pattern. They shell out to `git` and `gh` CLI tools and return parsed results. See Section 2.4 for full method signatures.

---

## 4. State Management

### 4.1 SpaceGitContext Lifecycle

Each `SpaceModel` owns a `SpaceGitContext` instance. The context is created when the `SpaceModel` is initialized and torn down when the Space is closed.

**Creation timing:** In `SpaceModel.init`, after the Space is fully initialized, create the `SpaceGitContext` with the Space's initial working directory context. For worktree-backed Spaces (`worktreePath` is non-nil), the context eagerly detects the git repo from `worktreePath`. For non-worktree Spaces, the context defers repo detection until the first pane reports a real working directory (see Section 2.3).

**Wiring to pane events:** `SpaceGitContext` needs to be notified when:
- A pane's working directory changes (OSC 7). Currently, `PaneViewModel` handles `surfacePwdNotification` and updates the split tree. Add a secondary notification (or a callback on `SpaceModel`) that forwards pwd changes to `SpaceGitContext.paneWorkingDirectoryChanged(paneID:newDirectory:)`.
- A pane is added to the Space (new tab creation, pane split). Hook into `SpaceModel.createTab()` and `PaneViewModel.splitPane()` to call `SpaceGitContext.paneAdded(paneID:workingDirectory:)`.
- A pane is removed from the Space. Hook into `PaneViewModel.closePane(paneID:)` to call `SpaceGitContext.paneRemoved(paneID:)`.

**Restored-session wiring:** The restore constructor `SpaceModel.init(id:name:tabs:activeTabID:defaultWorkingDirectory:)` currently calls `wireTabClose` and `wireDirectoryFallback` for each restored tab. It must additionally:
1. Wire `onPaneDirectoryChanged` for each restored tab (forwarding to `SpaceGitContext.paneWorkingDirectoryChanged`).
2. For each restored tab, iterate the split tree's leaf panes and call `SpaceGitContext.paneAdded(paneID:workingDirectory:)` for each leaf that has a non-nil working directory persisted in the `PaneNode`. This triggers repo detection from the persisted paths rather than waiting for the first OSC 7 event post-restore.

**Notification approach for pwd changes:** Add a new `NotificationCenter` notification `SpaceGitContext.panePwdChanged` (or use a direct callback pattern). The preferred approach is a callback closure on `PaneViewModel` (matching the existing `onEmpty` and `directoryFallback` patterns). `SpaceModel` wires this callback when creating or restoring tabs:

- Add `var onPaneDirectoryChanged: ((UUID, String) -> Void)?` to `PaneViewModel`.
- In `PaneViewModel`'s `surfacePwdNotification` observer, after calling `splitTree.updateWorkingDirectory(...)`, also call `onPaneDirectoryChanged?(paneID, pwd)`.
- `SpaceModel` sets `tab.paneViewModel.onPaneDirectoryChanged = { [weak self] paneID, dir in self?.gitContext.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: dir) }` for each tab. This wiring must happen in both the regular `init(name:initialTab:)` and the restore `init(id:name:tabs:activeTabID:defaultWorkingDirectory:)` constructors. A shared `wireGitContext(_ tab:)` private method (following the existing `wireTabClose`/`wireDirectoryFallback` pattern) is recommended.

**Space activation refresh:** When a Space becomes active, `SpaceGitContext.refresh()` is called. This is triggered by `SpaceCollection.activateSpace(id:)` or by observing `activeSpaceID` changes in the view layer.

**Teardown:** `SpaceGitContext.teardown()` cancels all in-flight tasks (iterating `inFlightTasks` and calling `.cancel()` on each), stops all `GitRepoWatcher` instances, and calls `PRStatusCache.evictAll()`. This is called from `SpaceModel`'s cleanup path (when the space is removed via `SpaceCollection.removeSpace`). Since cleanup currently happens by iterating tabs and calling `tab.cleanup()`, add `gitContext.teardown()` to the `SpaceModel` removal flow -- specifically in `SpaceCollection.removeSpace(id:)` before calling `tab.cleanup()`.

### 4.2 Observable Data Flow for Views

The view layer (`SidebarSpaceRowView`) accesses:

1. **Claude session dots:** `PaneStatusManager.shared.sessionStates(in: space)` -- returns `[(paneID: UUID, state: ClaudeSessionState)]` sorted by priority.
2. **Git repo statuses:** `space.gitContext.repoStatuses` -- the dictionary of `[GitRepoID: GitRepoStatus]`.
3. **Repo ordering:** `space.gitContext.pinnedRepoOrder` -- ordered list of repo IDs for display.
4. **Pane-to-repo mapping:** `space.gitContext.paneRepoAssignments` -- maps each pane to its repo (used to group Claude dots by repo).

All of these are `@Observable` properties, so SwiftUI automatically re-renders when they change. No manual `objectWillChange` calls are needed.

### 4.3 Local View State

The following state is managed locally in the view:

| State | Location | Description |
|-------|----------|-------------|
| `isHoveringBadges` | `@State` on badge area view | Tracks hover for popover display |
| `hoveredRepoID` | `@State` on status area | Which repo's badges are being hovered (for multi-repo) |
| `busyDotRotation` | Driven by `.animation(.linear.repeatForever)` | Continuous rotation for busy dot rainbow gradient |

---

## 5. Component Architecture

### 5.1 Feature Directory Structure

New files follow the existing source layout conventions:

```
aterm/
  Models/
    PaneStatusManager.swift          (modified -- add session state tracking)
    SpaceGitContext.swift             (new -- per-Space git context orchestrator)
    ClaudeSessionState.swift          (new -- enum definition)
    GitTypes.swift                    (new -- GitRepoID struct, GitRepoStatus, GitDiffSummary, GitChangedFile, PRStatus, PRState)
  Core/
    IPCCommandHandler.swift          (modified -- status.set state param)
    GitStatusService.swift           (new -- git/gh CLI wrapper)
    GitRepoWatcher.swift             (new -- FSEvents wrapper)
    PRStatusCache.swift              (new -- 60s TTL cache)
  Tab/
    SpaceModel.swift                 (modified -- owns SpaceGitContext, wires callbacks)
    SpaceCollection.swift            (modified -- teardown git context on space removal)
  Pane/
    PaneViewModel.swift              (modified -- add onPaneDirectoryChanged callback)
  View/
    Sidebar/
      SidebarSpaceRowView.swift      (modified -- new status area)
      SpaceStatusAreaView.swift      (new -- multi-line status area)
      RepoStatusLineView.swift       (new -- single repo status line)
      ClaudeSessionDotsView.swift    (new -- row of colored dots)
      GitBadgesView.swift            (new -- compact count badges)
      GitFileListPopover.swift       (new -- hover popover with file list)
      PRStatusIndicatorView.swift    (new -- clickable PR status icon)
      BusyDotView.swift              (new -- rainbow gradient spinning dot)
  Utilities/
    Logger.swift                     (modified -- add git log category)
```

### 5.2 Screen Specifications

#### SidebarSpaceRowView (Modified)

**Current structure:** An `HStack` containing active dot, optional worktree icon, VStack (name + optional status label), Spacer, tab count badge.

**New structure:** The VStack inside the HStack changes from:
- Line 1: `InlineRenameView` (space name)
- Line 2: Optional status label text

To:
- Line 1: `InlineRenameView` (space name) -- unchanged
- Line 2+: `SpaceStatusAreaView` -- the new multi-line status area, rendered when at least one condition is met: (a) any pane has non-nil/non-inactive session state, (b) any pane is in a git repo, (c) a free-form status label exists.

The existing worktree branch icon (`arrow.triangle.branch`) is removed from the first line of the HStack since branch information now appears in the status area. The active dot and tab count badge remain unchanged.

**Accessibility:** The Space row's `.accessibilityValue` is updated to include a combined description of all repo status lines and Claude session states, announced sequentially (FR-070).

#### SpaceStatusAreaView (New)

**Inputs:** `space: SpaceModel`, computed from `space.gitContext` and `PaneStatusManager.shared`.

**Layout:** A `VStack(alignment: .leading, spacing: 2)` containing zero or more `RepoStatusLineView` instances, one per pinned repo in order, plus an optional "no-repo" line for panes without a git repo.

**Logic for line generation:**
1. Collect pinned repos from `space.gitContext.pinnedRepoOrder`.
2. For each repo, build a `RepoStatusLineView` with: Claude dots for panes in that repo, repo's branch name, repo's PR status, repo's diff badges.
3. Collect non-repo panes (panes with nil repo assignment that have active Claude sessions).
4. If there is exactly one repo line and non-repo dots exist: prepend non-repo dots to the single repo line (FR-002b, 4pt gap).
5. If there are multiple repo lines and non-repo dots exist: add a separate no-repo line with dots only.
6. If there are no repo lines but non-repo dots exist: single line with dots only.
7. If there are no dots and no repo lines but a free-form status label exists: display the label text only (preserving current behavior, FR-005).

**Max lines:** If more than 3 repo lines exist (FR NFR-008), show the first 3 and a "+N more" truncation indicator.

#### RepoStatusLineView (New)

**Inputs:** Optional non-repo Claude dots (only for single-repo case), repo-specific Claude dots, branch name, isDetachedHead, PR status, diff summary, changed files list, onPRTap callback.

**Layout:** An `HStack(spacing: 0)` with:
1. Non-repo Claude dots (if provided) -- `ClaudeSessionDotsView`, followed by 4pt spacer.
2. Repo-specific Claude dots -- `ClaudeSessionDotsView`, followed by 5pt spacer (FR-002 item 2).
3. Branch name -- `Text` with 10pt system font, `.secondary` foreground, `.lineLimit(1)`, `.truncationMode(.tail)`. If detached HEAD, show abbreviated SHA.
4. `PRStatusIndicatorView` (if PR exists) -- 4pt leading spacing.
5. `Spacer(minLength: 4)` -- flexible space.
6. `GitBadgesView` -- compact count badges, right-aligned.

If no Claude dots exist for this line, items 1-2 are omitted and the line starts with the branch name (FR-003).

#### ClaudeSessionDotsView (New)

**Inputs:** Array of `ClaudeSessionState` values (sorted by priority, highest first).

**Layout:** An `HStack(spacing: 3)` of circles. Each circle is ~8pt diameter. Color determined by state:
- `needsAttention`: `Color(hex: "#FF9F0A")` (orange)
- `busy`: Rendered via `BusyDotView` (rainbow gradient, spinning)
- `active`: `Color(hex: "#34C759")` (green)
- `idle`: `Color(hex: "#8E8E93")` (gray)

#### BusyDotView (New)

**Layout:** An 8pt circle filled with a `MeshGradient` (or `AngularGradient` using the existing `rainbowColors` array from `RainbowGlowBorder.swift`) that rotates continuously. Uses `.rotationEffect(Angle.degrees(rotation))` with a `@State` rotation variable animated via `.onAppear { withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { rotation = 360 } }`.

Per FR-013 and FR-072, the animation is always active regardless of Reduce Motion. This differs from the Claude Session Status PRD FR-023 which specifies respecting Reduce Motion -- the Sidebar Status PRD v1.3 explicitly overrides this to "always spins."

The rainbow gradient reuses the `rainbowColors` constant already defined in `aterm/View/Shared/RainbowGlowBorder.swift`. Currently this constant is declared as `private let rainbowColors` at file scope. Change the access level by removing the `private` keyword, making it `let rainbowColors` (internal access, the Swift default). No file move is needed -- internal access is sufficient since all source files are in the same module. The `BusyDotView` can then reference `rainbowColors` directly.

#### GitBadgesView (New)

**Inputs:** `GitDiffSummary`.

**Layout:** An `HStack(spacing: 4)` of badge pills. Each non-zero count renders as a `Text` in 9pt monospaced font with muted foreground, inside a `RoundedRectangle(cornerRadius: 4)` background filled with `Color.white.opacity(0.06)` -- matching the existing tab count badge style in `SidebarSpaceRowView` (line 65-67).

Badge format: `"\(count)\(letter)"` where letter is M, A, D, R, or U. Only non-zero counts are shown. Order: M, A, D, R, U.

**Hover interaction:** The entire `GitBadgesView` has an `.onHover` modifier that sets `isHoveringBadges` state. When hovering and `diffSummary.isEmpty` is false, the `GitFileListPopover` is shown.

#### GitFileListPopover (New)

**Inputs:** `[GitChangedFile]`, appears as a `.popover` anchored below the `GitBadgesView`.

**Layout:** A `VStack(alignment: .leading, spacing: 4)` in a popover with dark background consistent with sidebar glassmorphism. Each row is an `HStack`:
- Status letter (`Text`, 9pt monospaced, color-coded: M = yellow/amber, A = green, D = red, R = blue, U = orange)
- File path (`Text`, 10pt system font, `.secondary` foreground, truncated)

Maximum 30 rows displayed (FR-043). If more than 30 files, a footer row shows "and N more files..." in muted text.

**Dismissal:** The popover is dismissed when the mouse leaves the badge area or the popover itself (FR-042). This uses SwiftUI's `.popover(isPresented:)` with the hover state binding.

**Accessibility:** The popover content is accessible via VoiceOver (FR-071). Each row has an accessibility label like "Modified src/auth/middleware.ts".

#### PRStatusIndicatorView (New)

**Inputs:** `PRStatus?`, `onTap: () -> Void`.

**Layout:** When PR status is present, renders a small label or icon:
- Open: "PR" text in green (9pt, semibold) or small circle icon filled green
- Draft: "PR" text in gray
- Merged: "PR" text in purple
- Closed: "PR" text in red
- No PR: View renders as `EmptyView` (nothing shown)

**Interaction:** Tappable. On tap, opens `prStatus.url` in the default browser via `NSWorkspace.shared.open(url)` (FR-053).

---

## 6. Navigation

### 6.1 No New Routes

This feature does not add new screens, windows, or navigation routes. All UI changes are within the existing `SidebarSpaceRowView` in the sidebar panel.

### 6.2 Navigation Flow

- The hover popover (`GitFileListPopover`) is shown/hidden based on mouse hover state over the badge area. It is not a navigation destination.
- The PR status indicator opens an external URL in the default browser. This is a leave-the-app action, not in-app navigation.

---

## 7. Type Definitions

### 7.1 ClaudeSessionState

| Case | Raw Value | Priority | Color (hex) |
|------|-----------|----------|-------------|
| `needsAttention` | `"needs_attention"` | 1 | #FF9F0A |
| `busy` | `"busy"` | 2 | #3282F6 |
| `active` | `"active"` | 3 | #34C759 |
| `idle` | `"idle"` | 4 | #8E8E93 |
| `inactive` | `"inactive"` | 5 | (not shown) |

Conforms to: `Sendable`, `Equatable`, `Comparable`, `CaseIterable`.

### 7.2 GitRepoID

A struct (not a typealias) conforming to `Hashable` and `Sendable`. Contains a single `path: String` field representing the canonicalized absolute path from `git rev-parse --git-common-dir`. Using a distinct struct type rather than a bare `String` prevents accidental misuse (e.g., passing a branch name where a repo ID is expected) and is consistent with the codebase convention of typed identifiers.

### 7.3 GitRepoStatus

| Field | Type | Description |
|-------|------|-------------|
| `repoID` | `GitRepoID` | Canonical repo root path |
| `displayName` | `String` | Last path component of `repoID.path` (e.g., "aterm") for future use |
| `branchName` | `String?` | Short branch name or abbreviated SHA |
| `isDetachedHead` | `Bool` | True when HEAD is a detached commit |
| `diffSummary` | `GitDiffSummary` | Aggregate change counts |
| `changedFiles` | `[GitChangedFile]` | Full list of changed files |
| `prStatus` | `PRStatus?` | GitHub PR status (nil = no PR or gh unavailable) |
| `lastUpdated` | `Date` | Timestamp of last successful query |

### 7.4 GitDiffSummary

| Field | Type |
|-------|------|
| `modified` | `Int` |
| `added` | `Int` |
| `deleted` | `Int` |
| `renamed` | `Int` |
| `unmerged` | `Int` |

Computed: `isEmpty: Bool` (all counts zero), `totalCount: Int` (sum).

### 7.5 GitChangedFile

| Field | Type |
|-------|------|
| `status` | `GitFileStatus` |
| `path` | `String` |

### 7.6 GitFileStatus

Enum with cases: `modified`, `added`, `deleted`, `renamed`, `unmerged`. Each case has a `letter: String` computed property (M, A, D, R, U) and a `color: Color` computed property (yellow/amber, green, red, blue, orange).

### 7.7 PRStatus

| Field | Type |
|-------|------|
| `state` | `PRState` |
| `url` | `URL` |

### 7.8 PRState

Enum with cases: `open`, `draft`, `merged`, `closed`. Each case has a `color: Color` computed property (green, gray, purple, red).

---

## 8. Analytics Implementation

This project does not have an analytics framework. No analytics events are defined. Debug logging via `os.Logger` serves as the observability mechanism.

| Log Event | Logger Category | Level | Trigger |
|-----------|----------------|-------|---------|
| Session state change | `Log.ipc` | debug | `PaneStatusManager.setSessionState` called. Log pane ID, old state, new state. |
| Git repo detected for pane | new `Log.git` | debug | `SpaceGitContext.paneWorkingDirectoryChanged` finds a git repo. Log pane ID, repo ID. |
| Git repo unpinned | `Log.git` | debug | All panes left a repo. Log repo ID. |
| FSEvents watcher started | `Log.git` | debug | `GitRepoWatcher` created. Log watch paths. |
| FSEvents watcher stopped | `Log.git` | debug | `GitRepoWatcher` deallocated. Log watch paths. |
| Git status refresh | `Log.git` | debug | `GitStatusService.currentBranch` / `diffStatus` called. Log repo ID, duration. |
| Git status timeout | `Log.git` | warning | `git status` exceeds 5s. Log repo ID. |
| PR status fetched | `Log.git` | debug | `GitStatusService.fetchPRStatus` returns. Log branch, state, duration. |
| PR status cache hit | `Log.git` | debug | `PRStatusCache.get` returns valid entry. Log branch. |
| gh unavailable | `Log.git` | debug | `gh pr view` fails (not installed, not authenticated). Log error. |
| git unavailable | `Log.git` | debug | `git rev-parse` fails in a way suggesting git is not installed. Log error. |

**New logger category:** Add `static let git = Logger(subsystem: "com.aterm.app", category: "git")` to the `Log` enum in `aterm/Utilities/Logger.swift`.

---

## 9. Permissions & Security

### 9.1 Subprocess Execution

The feature shells out to `git` and `gh` CLI tools. Both are executed with the user's environment and permissions. No elevated privileges are required.

- `git` is located at `/usr/bin/git` (same as `WorktreeService`).
- `gh` is located via `PATH` resolution. The implementation should use `/usr/bin/env gh` or find `gh` via `Process.launchPath` with `PATH` lookup, since `gh` may be installed via Homebrew at `/opt/homebrew/bin/gh` or other locations.

### 9.2 No Sandbox Implications

The app has `ENABLE_APP_SANDBOX: false` in `project.yml` (line 99). Subprocess execution and filesystem access are unrestricted.

### 9.3 FSEvents Permissions

FSEvents monitoring requires no special entitlements. The app monitors `.git/` directories within the user's working directories, which are already accessible.

### 9.4 Client-Side Guards

- No feature flag is defined for v1. The status area renders conditionally based on data availability (no git repo = no git status shown; no session state = no dots shown).
- The `gh` CLI path should be resolved once at app startup (or lazily on first use) and cached. If resolution fails, all PR status features are silently disabled for the session.

---

## 10. Performance Considerations

### 10.1 Background Execution

All `git` and `gh` subprocess calls run on `DispatchQueue.global(qos: .userInitiated)` via `async` methods. Results are dispatched to the main actor for state updates. No subprocess execution blocks the main thread (NFR-001).

### 10.2 FSEvents Efficiency

FSEvents streams are lightweight. The 2-second coalescing latency means the system delivers at most one callback per 2-second window per watcher, regardless of how many filesystem events occur. With 10+ concurrent watchers (one per repo per Space), the overhead is negligible.

### 10.3 Debounce and Rate Limiting

- FSEvents 2-second latency provides debouncing (FR-061).
- PR status has a 60-second TTL cache, reducing `gh` CLI invocations (FR-056). Additionally, `PRStatusCache.pending` deduplicates concurrent requests for the same branch/repo.
- `SpaceGitContext.inFlightTasks` ensures at most one refresh task per repo at any time, cancelling stale tasks.
- Git status timeout of 5 seconds prevents blocking on very large repos (FR-064).
- `gh` timeout of 10 seconds prevents blocking on network issues (NFR-006).

### 10.4 Memory

- `SpaceGitContext` stores `GitRepoStatus` per detected repo. Each status includes up to 100 changed files (capped at the `GitStatusService.diffStatus` parsing level). This bounds memory usage even for repos with thousands of changes.
- `PRStatusCache` entries are small and evicted on Space close.
- `GitRepoWatcher` instances hold an FSEvents stream reference. Minimal memory overhead.

### 10.5 View Rendering

- The multi-line status area uses `VStack` with `ForEach` over the repo list. With typically 1-2 repos per Space, this is trivial.
- Claude session dots use `HStack` with `ForEach` over at most ~10 dots (one per pane). Lightweight.
- The busy dot animation uses SwiftUI's built-in `.rotationEffect` + `.animation`, which is GPU-accelerated and has negligible CPU overhead (NFR-005).

### 10.6 Sidebar Row Height

The status area adds height to the Space row. With 1 repo line, this adds approximately 16pt (10pt text + 2pt spacing + 4pt padding). With 3 repo lines, approximately 48pt. The NFR-008 cap at 3 lines with "+N more" truncation prevents unbounded growth.

---

## 11. Migration & Deployment

### 11.1 No Database Migration

There is no persistent storage for git status or Claude session state. All data is ephemeral and computed at runtime.

### 11.2 PaneStatusManager Schema Change

The `PaneStatus` struct is NOT modified. It retains its existing `label: String` (non-optional) and `updatedAt: Date` fields. A new parallel `sessionStates: [UUID: ClaudeSessionState]` dictionary is added to `PaneStatusManager` alongside the existing `statuses` dictionary. Since `PaneStatusManager` is in-memory only (not persisted in `SessionState`), there is no migration needed. The change is fully additive -- `setStatus(paneID:label:)`, `latestStatus(in:)`, and all other existing methods continue to work without any modification. Existing tests pass without changes.

### 11.3 Session Persistence

Claude session state and git status are NOT persisted across app restarts. On app launch, all `SpaceGitContext` instances are freshly initialized and perform initial repo detection and git status queries. This is acceptable because:
- Session persistence for session restore already recreates panes with their working directories.
- `SpaceGitContext` initializes from the Space's working directory and detects repos on startup.
- Claude Code hooks will re-fire `status.set --state active` on `SessionStart` when Claude Code sessions reconnect.

### 11.4 XcodeGen

After adding new source files, run `xcodegen generate` to regenerate `aterm.xcodeproj`. The new files are all within the existing `aterm/` source tree and will be auto-discovered by the `sources: - path: aterm` directive in `project.yml`.

### 11.5 Deployment Order

No special deployment order. All changes ship together. No feature flag gating for v1.

### 11.6 Rollback

Since there are no persistent schema changes, rollback is simply reverting the code changes. The `PaneStatusManager` changes are backward-compatible -- removing the session state field just means dots stop appearing.

---

## 12. Implementation Phases

### Phase 1: Claude Session State Tracking (Foundation)

**Goal:** Implement the `ClaudeSessionState` enum, extend `PaneStatusManager` with session state tracking, and extend the `status.set` IPC command to accept the `--state` parameter. No UI changes yet.

**Deliverables:**
- `ClaudeSessionState` enum in `aterm/Models/ClaudeSessionState.swift`
- `PaneStatusManager` extended with `sessionStates: [UUID: ClaudeSessionState]` parallel dictionary and new methods: `setSessionState`, `clearSessionState`, `sessionState(for:)`, `sessionStates(in:)`. The existing `PaneStatus` struct is NOT modified -- `label` remains non-optional `String`.
- `clearStatus(paneID:)` and `clearAll(for:)` updated to also clear `sessionStates` entries
- `IPCCommandHandler.handleStatusSet` extended to accept `state` param
- Unit tests for `PaneStatusManager` session state methods (all existing tests must pass unmodified)
- Unit tests for `IPCCommandHandler` with `state` param (valid values, invalid values, label+state together, state-only, label-only, neither)

**Independently testable:** Yes. Can be verified via `aterm-cli status set --state busy` and checking `PaneStatusManager` state.

### Phase 2: Claude Session Dots in Sidebar

**Goal:** Render per-pane Claude session dots on the Space row status line. No git integration yet.

**Deliverables:**
- `ClaudeSessionDotsView` component
- `BusyDotView` component with rainbow gradient spinning animation
- Remove the `private` keyword from `let rainbowColors` in `aterm/View/Shared/RainbowGlowBorder.swift` (changing from `private let` to `let`, which gives internal access)
- `SpaceStatusAreaView` component (initially only handles Claude dots, no git lines)
- `SidebarSpaceRowView` modified to use `SpaceStatusAreaView` instead of inline status label
- Accessibility labels for dots (FR-070)

**Independently testable:** Yes. With Phase 1 in place, set session states via IPC and verify dots appear in sidebar.

### Phase 3: Git Repository Detection & Branch Name

**Goal:** Detect git repos from pane working directories, resolve branch names, and display branch names in the sidebar.

**Deliverables:**
- `GitStatusService` with `detectRepo` and `currentBranch` methods
- `GitTypes.swift` with `GitRepoID` (as a struct with `path: String`, conforming to `Hashable, Sendable`), `GitRepoStatus`, and related structs (partial -- no diff or PR fields yet, or with placeholder defaults)
- `SpaceGitContext` with basic repo detection, pane-to-repo mapping, lazy detection for non-worktree Spaces, eager detection for worktree Spaces, and `inFlightTasks` cancellation tracking
- `PaneViewModel` extended with `onPaneDirectoryChanged` callback
- `SpaceModel` wires `onPaneDirectoryChanged` to `SpaceGitContext` in both the regular init and the restore init (via shared `wireGitContext` helper)
- `SpaceModel` restore init calls `paneAdded` for each restored leaf pane with a persisted working directory
- `RepoStatusLineView` showing branch name only
- `SpaceStatusAreaView` updated to generate repo lines
- New `Log.git` logger category
- Unit tests for `GitStatusService.detectRepo` and `currentBranch` (using temp git repos, same pattern as `WorktreeServiceTests`)
- Unit tests for `SpaceGitContext` repo detection logic, including lazy vs. eager init behavior
- Unit tests for in-flight task cancellation (verify that rapid sequential refreshes cancel the prior task)

**Independently testable:** Yes. Open aterm with a pane in a git repo, verify branch name appears. For non-worktree Spaces, branch name appears after the shell reports its first working directory via OSC 7.

### Phase 4: Git Diff Summary & Badges

**Goal:** Run `git status --porcelain=v1`, parse results, display compact count badges.

**Deliverables:**
- `GitStatusService.diffStatus` method
- `GitDiffSummary`, `GitChangedFile`, `GitFileStatus` types (complete)
- `GitBadgesView` component
- `RepoStatusLineView` updated with badges
- `SpaceGitContext` updated to fetch and store diff status alongside branch
- Unit tests for `diffStatus` parsing logic (various porcelain output scenarios)

**Independently testable:** Yes. Modify files in a git repo, verify badges appear.

### Phase 5: FSEvents Watching & Auto-Refresh

**Goal:** Implement FSEvents-based file watching so git status updates automatically when files change.

**Deliverables:**
- `GitRepoWatcher` class with CoreServices FSEvents integration
- `SpaceGitContext` creates/manages watchers per repo
- Watcher lifecycle tied to repo pinning (start on detect, stop on unpin/close)
- 2-second debounce via FSEvents latency parameter
- Git status timeout (5 seconds, FR-064)
- Space activation refresh (FR-062)
- Debug logging for watcher start/stop and refresh events

**Independently testable:** Yes. Save a file in a git repo, verify sidebar updates within ~3 seconds.

### Phase 6: Working Directory Pinning & Multi-Repo Support

**Goal:** Implement the full pinning behavior (FR-020) and multi-repo status lines.

**Deliverables:**
- `SpaceGitContext` pinning logic: sticky repos, pane-to-repo reassignment on cd, unpin when no pane references a repo
- Multi-line status area rendering in `SpaceStatusAreaView`
- Non-repo pane dot grouping (FR-002b: prepend to single line, separate line for multi)
- Repo line ordering (FR-002c: pinned first, then alphabetical, then no-repo)
- 3-line cap with "+N more" indicator (NFR-008)
- Integration tests for pinning behavior

**Independently testable:** Yes. Create panes in different repos, verify separate status lines. `cd` out of repo, verify pinning holds.

### Phase 7: GitHub PR Status

**Goal:** Fetch and display GitHub PR status via `gh` CLI.

**Deliverables:**
- `GitStatusService.fetchPRStatus` method with 10-second timeout
- `PRStatusCache` with 60-second TTL, `now` clock injection parameter, and `pending` deduplication set
- `PRStatusIndicatorView` component
- `RepoStatusLineView` updated with PR indicator
- `SpaceGitContext` integrates PR fetching into refresh flow (check cache, check pending, fetch on miss/expiry)
- Click-to-open-PR behavior (NSWorkspace.shared.open)
- Silent failure when `gh` unavailable
- Unit tests for PR status parsing, cache TTL behavior (using injected clock), and deduplication (verify `markPending` prevents duplicate fetches)

**Independently testable:** Yes. Check out a branch with an open PR, verify PR indicator appears.

### Phase 8: Hover Popover & Polish

**Goal:** Implement the git file list hover popover and final polish.

**Deliverables:**
- `GitFileListPopover` component with color-coded status letters, 30-file cap, "+N more" footer
- Hover interaction on `GitBadgesView` to show/hide popover
- Per-repo popover (hovering badges on one repo line shows only that repo's files)
- VoiceOver accessibility for popover content (FR-071)
- Full accessibility values on Space row including multi-repo status (FR-070)
- Remove worktree branch icon from Space row first line (now redundant with branch name in status area)
- Final visual polish: spacing, alignment, colors matching Figma reference

**Independently testable:** Yes. Hover over badges, verify popover appears with correct file list.

---

## 13. Test Strategy

### 13.1 Mapping to PRD Success Criteria

| PRD Success Metric | Target | Verification Method | Phase |
|--------------------|--------|---------------------|-------|
| Status line renders correctly for git-backed Spaces | 100% of Spaces inside a git repo show branch name | Integration test: create Space with git-backed working dir, assert `SpaceGitContext.repoStatuses` contains branch name. Manual QA across worktree and non-worktree Spaces. | 3 |
| Multi-repo Spaces show separate status lines | Spaces with panes in 2+ repos show one line per repo | Integration test: create Space with panes in 2 different repos, assert `pinnedRepoOrder.count == 2`. Manual QA. | 6 |
| Working directory pinning prevents flickering | Sidebar branch name does not change when active pane `cd`s out of repo | Integration test: set up repo, call `paneWorkingDirectoryChanged` with non-git dir, assert `repoStatuses` still contains original repo. | 6 |
| Claude dots reflect session state within 100ms | <100ms from IPC receipt to sidebar update | Instrumented test: timestamp before `setSessionState`, check observation propagation. Debug logging with timestamps. | 1, 2 |
| Git status refresh latency after file change | <3s from file save to badge update | Manual testing with debug logging timestamps. The 2s FSEvents debounce + <1s git query should meet this. | 5 |
| No main-thread blocking from git queries | 0 main-thread hangs >16ms caused by git/gh subprocess calls | Xcode Instruments Time Profiler during git operations. All subprocess calls are verified async. | 3, 4, 7 |
| Hover popover displays full file list | Popover shown on hover with correct file list | Manual QA with repos having 1-100+ changed files. | 8 |
| PR status shown for branches with open PRs | PR indicator appears when `gh pr view` returns data | Integration test with mock `gh` output. Manual QA with test repo. | 7 |
| PR cache reduces gh CLI calls | Repeated FSEvents within 60s do not trigger additional `gh pr view` calls | Unit test: verify cache hit within TTL. Debug logging: count gh invocations per 60s window. | 7 |
| Busy dot always spins | Busy dot mesh rainbow animation is active regardless of Reduce Motion | Manual verification with Reduce Motion enabled and disabled. | 2 |
| FSEvents streams cleaned up on Space close | No orphaned FSEvents streams after closing Spaces | Unit test: create `GitRepoWatcher`, call `teardown`, verify stream is stopped. Instruments leak check. | 5 |

### 13.2 Mapping to Functional Requirements

| FR ID | Test Description | Type | Preconditions |
|-------|-----------------|------|---------------|
| FR-001 | Status area renders when pane has non-inactive session state | Unit | PaneStatusManager has at least one non-inactive state for a pane in the Space |
| FR-001 | Status area renders when pane working directory is in a git repo | Integration | SpaceGitContext detects a repo |
| FR-001 | Status area renders when free-form label exists | Unit | PaneStatusManager has a label for a pane in the Space |
| FR-002 | Status line layout: dots, branch, PR, spacer, badges in correct order | UI/Manual | Git repo with changes and active Claude sessions |
| FR-002a | Multiple repo lines rendered for multi-repo Space | Integration | Space with panes in 2+ different git repos |
| FR-002b | Non-repo dots prepended to single repo line with 4pt gap | Unit/Manual | 1 repo line + non-repo panes with sessions |
| FR-002b | Non-repo dots on separate line when multiple repo lines exist | Unit/Manual | 2+ repo lines + non-repo panes with sessions |
| FR-002c | Repo lines ordered: pinned first, alphabetical, no-repo last | Unit | Space with worktreePath and 2 additional repos |
| FR-003 | Line starts with branch name when no dots exist for that repo | Unit | Repo with no panes having active Claude sessions |
| FR-004 | Only Claude dots shown when no pane is in a git repo | Unit | Active Claude sessions, no git repos detected |
| FR-005 | Only label text shown when no dots and no git info exist | Unit | PaneStatusManager has label but no session state and no git repo |
| FR-010 | Each non-nil/non-inactive pane produces one dot | Unit | 3 panes with states: active, busy, nil |
| FR-011 | Dots sorted by priority (highest-priority leftmost) | Unit | Panes with idle, needsAttention, busy states |
| FR-012 | Dots spaced ~3pt apart | Manual/UI | Multiple dots visible |
| FR-013 | Busy dot has rainbow gradient with spinning animation | Manual | Pane in busy state |
| FR-014 | Nil and inactive panes produce no dot | Unit | Pane with nil state and pane with inactive state |
| FR-015 | Dots update reactively on state change | Integration | Change session state via IPC, verify dots re-render |
| FR-020 | Pinned repo stays when pane cd's to non-git dir | Integration | Detect repo, change pane wd to non-git dir, verify repo still pinned |
| FR-020.4 | Pane repo reassignment on cd to different repo | Integration | Pane in repo A, change wd to repo B, verify pane moves to repo B |
| FR-021 | Git repo detection uses git rev-parse --git-dir and --git-common-dir | Unit | Call detectRepo on git dir and non-git dir |
| FR-022 | Branch shown for non-worktree Spaces in git repos (after first OSC 7 report) | Integration | Space without worktreePath but pane has reported wd in git repo via OSC 7 or paneAdded |
| FR-023 | Branch name 10pt, secondary foreground, truncated with ellipsis | Manual | Long branch name |
| FR-024 | No branch/git status when no pane in git repo | Unit | Space with no git-backed panes |
| FR-024a | Silent failure when git not installed or fails | Unit | Mock git failure, verify no error in UI |
| FR-025 | Detached HEAD shows abbreviated SHA | Unit | detectRepo returns detached HEAD |
| FR-030 | git status --porcelain=v1 --ignore-submodules used | Unit | Verify command arguments in GitStatusService |
| FR-031 | Compact badge format: "3M 1A 1D" | Unit | GitDiffSummary with modified=3, added=1, deleted=1 |
| FR-032 | All 5 change types tracked (M, A, D, R, U) | Unit | Porcelain output with each type |
| FR-033 | Badges 9pt monospaced with pill background | Manual | Non-zero change counts |
| FR-034 | No badges when clean working tree | Unit | GitDiffSummary.isEmpty == true |
| FR-040 | Hover over badges shows popover with changed files | Manual | Non-zero changes, hover |
| FR-041 | Popover rows: status letter (colored) + relative file path | Manual | Popover visible |
| FR-042 | Popover dismissed on mouse-out | Manual | Move mouse away from badges/popover |
| FR-043 | Popover capped at 30 files with "+N more" footer | Unit/Manual | Repo with 35+ changes |
| FR-044 | No popover when clean working tree | Unit | No badges rendered, hover has no effect |
| FR-050 | PR status shown for branches with associated PR | Integration | Branch with open PR, gh installed |
| FR-051 | gh pr view --json state,url,isDraft used for PR fetch | Unit | Verify command in GitStatusService |
| FR-052 | PR indicator color-coded by state (open=green, draft=gray, merged=purple, closed=red) | Unit/Manual | Each PR state |
| FR-053 | PR indicator clickable, opens URL in browser | Manual | Click PR indicator |
| FR-054 | Silent failure when gh unavailable | Unit | Mock gh not found, verify no error indicator |
| FR-055 | PR status fetched on initial load and refreshed per cache policy | Integration | Initial load and TTL expiry |
| FR-056 | PR cache 60s TTL, reused during FSEvents refreshes | Unit | Set cache, query within 60s, query after 60s |
| FR-060 | Git status refreshes via FSEvents monitoring | Integration | Change file, verify status updates |
| FR-061 | FSEvents debounced ~2s | Unit/Manual | Rapid file changes, verify single git status call per 2s window |
| FR-062 | Git status refreshes on Space activation | Integration | Switch away and back to Space, verify refresh |
| FR-063 | New pane in new repo triggers new repo line | Integration | Add pane with working dir in different repo |
| FR-064 | 5s timeout, previous status retained | Unit | Mock slow git, verify previous status unchanged |
| FR-065 | FSEvents stream created on first repo detection | Unit | Detect repo, verify watcher started |
| FR-066 | FSEvents stream torn down on Space close | Unit | Close Space, verify watcher stopped |
| FR-067 | FSEvents stream restarted when pinned context changes | Integration | All panes leave repo, verify watcher stopped |
| FR-068 | All Spaces with git repos have active watchers | Unit | Inactive Space with git repo has watcher running |
| FR-069 | Worktree watch path includes linked gitdir + common refs | Unit | Detect worktree repo, verify watch paths include both |
| FR-070 | Accessibility value includes multi-repo status | Manual/VoiceOver | Multi-repo Space with sessions |
| FR-071 | Hover popover accessible via VoiceOver | Manual/VoiceOver | Popover visible, VoiceOver active |
| FR-072 | Busy dot spins regardless of Reduce Motion | Manual | Enable Reduce Motion, verify busy dot still spins |

### 13.3 Unit Tests

All tests use Swift Testing (`import Testing`, `@Test` macro, `#expect`), following the project's existing pattern (e.g., `PaneStatusManagerTests.swift`, `WorktreeServiceTests.swift`).

**PaneStatusManager tests (extend existing `atermTests/PaneStatusManagerTests.swift`):**
- `setSessionState` stores state in `sessionStates` dictionary, does not create or affect entries in `statuses` dictionary
- `setStatus` (label) does not affect `sessionStates` dictionary
- `clearStatus` clears both the `statuses` entry and the `sessionStates` entry
- `clearSessionState` clears only the `sessionStates` entry, leaves `statuses` intact
- `clearAll` clears both `statuses` and `sessionStates` entries for given pane IDs
- `sessionStates(in:)` returns sorted non-nil/non-inactive states
- `sessionStates(in:)` returns empty array when all states are nil or inactive
- `sessionStates(in:)` spans all tabs and panes in the space
- All existing `PaneStatusManager` tests pass without modification (label remains non-optional `String`, `latestStatus` unchanged)

**IPCCommandHandler tests (extend existing `atermTests/IPCCommandHandlerTests.swift`):**
- `status.set` with `state` only (valid values)
- `status.set` with invalid `state` returns error with valid values list
- `status.set` with both `label` and `state`
- `status.set` with neither `label` nor `state` returns error
- `status.clear` clears both label and session state

**ClaudeSessionState tests (new test file):**
- Init from valid raw values
- Init from invalid raw value returns nil
- Comparable ordering matches priority
- All cases iterable

**GitStatusService tests (new test file, similar pattern to `WorktreeServiceTests`):**
- `detectRepo` on a git directory returns non-nil with correct gitDir and commonDir
- `detectRepo` on a non-git directory returns nil
- `detectRepo` on a worktree directory returns correct linked gitDir and shared commonDir
- `currentBranch` returns branch name for symbolic ref
- `currentBranch` returns abbreviated SHA for detached HEAD
- `diffStatus` parsing for each porcelain status code (M, A, D, R, U, ??)
- `diffStatus` returns empty summary for clean repo
- `diffStatus` with `--ignore-submodules` excludes submodule changes
- `diffStatus` caps `changedFiles` at 100 entries: create a repo with 150 changes, verify `files.count == 100` but `summary.totalCount == 150`

**PRStatusCache tests (new test file):**
All TTL-dependent tests use an injected `now` clock that returns a controllable date, enabling deterministic testing without real-time waits.
- `get` returns nil for missing entry (cache miss)
- `set` then `get` within 60s (by advancing injected clock by 59s) returns cached value
- `get` after 60s (by advancing injected clock by 61s) returns nil (expired)
- `evictAll` clears all entries and all pending keys
- Different branches have independent cache entries
- Cache hit for "no PR" (nil PRStatus) is distinct from cache miss
- `markPending` returns `true` on first call for a key, `false` on second call (deduplication)
- `set` removes the key from `pending`
- `clearPending` removes the key from `pending` without adding a cache entry (for failure cases)
- After `clearPending`, a subsequent `markPending` for the same key returns `true` (retry is allowed)

**SpaceGitContext tests (new test file):**
- Repo detection on pane with git-backed working directory
- Repo detection on pane with non-git working directory
- Lazy detection: non-worktree Space does NOT detect repo on init, only after `paneWorkingDirectoryChanged` or `paneAdded` with a real path
- Eager detection: worktree-backed Space (with `worktreePath` set) detects repo immediately on init
- Restored-session detection: calling `paneAdded` with persisted working directories triggers repo detection
- Pinning: repo stays after pane cd's to non-git dir
- Unpinning: repo removed when last pane leaves it
- Multi-repo: two panes in different repos produce two entries
- Pane-to-repo reassignment on cd to different repo
- pinnedRepoOrder: worktreePath repo first, then alphabetical
- paneRemoved clears assignments and unpins if needed
- In-flight task cancellation: starting a new refresh for the same repo cancels the prior in-flight task
- In-flight task cancellation: cancelled task does not write stale results to `repoStatuses`
- teardown cancels all in-flight tasks and stops all watchers

**GitRepoWatcher tests (new test file):**
- Watcher creation sets up FSEvents stream for given paths
- Watcher teardown stops FSEvents stream
- Callback fires after filesystem change (integration-ish, uses temp directory)

### 13.4 Integration Tests

These tests use real git repos (following the `WorktreeServiceTests` pattern of creating temp git repos):

- Full flow: create temp git repo, create Space with working directory in it, verify `SpaceGitContext` detects repo and populates `repoStatuses` with branch name and diff summary.
- Worktree detection: create temp git repo with worktree, verify `detectRepo` returns correct linked gitDir and commonDir, verify watch paths include both.
- PR status integration: difficult to test without a real GitHub repo. Verify silent failure when gh is not available (mock by pointing to a non-existent gh path).
- Status.set IPC flow: send IPC request with `state` param through the full `IPCCommandHandler` -> `PaneStatusManager` chain, verify state is stored correctly.

### 13.5 End-to-End Tests

Critical user flows mapped to PRD user stories:

| Flow | Steps | Assertions | PRD User Stories |
|------|-------|------------|-----------------|
| Branch name visibility | Open Space in git repo | Branch name appears in status area | US-1 |
| Diff badges | Modify files in repo | Badge counts match actual changes | US-2 |
| Hover popover | Hover over badges | Popover shows correct file list | US-3 |
| PR status | Checkout branch with PR | PR indicator appears with correct state | US-4 |
| Claude session dots | Run `aterm-cli status set --state busy` | Blue spinning dot appears | US-5 |
| Needs attention | Run `aterm-cli status set --state needs_attention` | Orange dot appears | US-6 |
| Auto-refresh | Save file in repo | Badges update within ~3s | US-7 |
| Non-worktree git | Open Space in regular git clone (no worktree), wait for OSC 7 | Branch name shown after pane reports working directory | US-8 |
| Multi-repo | Split pane, cd to different repo | Two status lines appear | US-9 |

### 13.6 Edge Case & Error Path Tests

| Edge Case | Test Description | FR Reference |
|-----------|-----------------|-------------|
| git not installed | Mock git binary missing, verify silent failure | FR-024a |
| gh not installed | gh not in PATH, verify no PR indicator | FR-054 |
| gh not authenticated | gh returns auth error, verify no PR indicator | FR-054 |
| Very large repo | git status takes >5s (mock), verify previous status retained | FR-064 |
| gh timeout | gh takes >10s (mock), verify no PR indicator | NFR-006 |
| No changes | Clean repo, verify no badges and no popover | FR-034, FR-044 |
| 100+ changed files | Repo with many changes, verify `diffStatus` caps `changedFiles` array at 100 entries while `GitDiffSummary` totals reflect full count. Verify popover caps display at 30 with footer. | FR-043 |
| Detached HEAD | Checkout a commit hash, verify abbreviated SHA shown | FR-025 |
| Pane in non-git dir | Pane cd's to /tmp, verify no git info on that pane | FR-024 |
| All panes leave repo | All panes cd out of a pinned repo, verify repo unpinned | FR-020.3 |
| Space close cleanup | Close Space, verify all watchers stopped and cache evicted | FR-066, FR-056.6 |
| Concurrent refreshes | Rapid FSEvents during 2s window, verify single git query | NFR-003 |
| Rapid branch switches | Two FSEvents fire in quick succession with different branches, verify first task's results are discarded via in-flight cancellation | NFR-003 |
| Non-worktree Space initial state | Non-worktree Space shows no git status immediately after creation, until pane reports working directory | FR-022 |
| Restored session with stale paths | Restored panes have working directories that are no longer git repos, verify silent nil return | FR-024a |
| Duplicate PR fetch | Two FSEvents trigger PR fetch for the same branch/repo, verify only one `gh pr view` call via `pending` deduplication | FR-056 |
| Empty Space (no panes) | Should not crash, no status rendered | - |

### 13.7 Performance & Load Tests

| Test | Threshold | PRD Metric |
|------|-----------|------------|
| IPC state change to sidebar update | <100ms | NFR-004 |
| Git status refresh after file change | <3s (2s debounce + <1s query) | Success Metric #5 |
| Main thread blocking | 0 hangs >16ms from git/gh subprocess | NFR-001 |
| FSEvents overhead with 10+ watchers | <1% CPU idle | NFR-002 |

---

## 14. Technical Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| `git status` is slow on very large repos (monorepos, 100K+ files) | Git status badges stale or delayed beyond 3s target | Medium | 5-second timeout (FR-064). Previous status retained. Future: use `git status` with pathspec filter for only the working directory subtree. |
| FSEvents coalescing latency may vary by macOS version | Status updates may be slightly faster or slower than 2s | Low | The 2s latency is a hint, not a guarantee. The system may deliver events earlier. This is acceptable. |
| `gh` CLI may not be installed or authenticated | PR status silently unavailable | Medium (expected for many users) | Silent failure is the design. No impact on other features. |
| CoreServices FSEvents C API requires careful memory management | Potential for leaks or crashes if stream not properly invalidated | Medium | Wrap FSEvents lifecycle in a Swift class with `deinit` that calls `FSEventStreamStop` + `FSEventStreamInvalidate` + `FSEventStreamRelease`. Test with Instruments leak checker. |
| Stale result ordering from concurrent refreshes | Old git status result overwrites a newer one if tasks complete out-of-order | Medium | `SpaceGitContext` tracks `inFlightTasks: [GitRepoID: Task<Void, Never>]`. Each new refresh cancels the prior task for that repo. Cancelled tasks check `Task.isCancelled` before writing results, discarding stale data. |
| Rainbow gradient on 8pt circle may be visually unclear at small size | Busy dot looks like a solid color blob | Low | Test at Retina resolution. If gradient is not visible at 8pt, increase dot size to 10pt or use `AngularGradient` with higher contrast stops. |
| `git rev-parse` may behave differently in bare repos or submodules | Unexpected nil returns or wrong repo detection | Low | `--ignore-submodules` excludes submodule status. Bare repos are not working directories, so panes should not be cd'd into them. Add defensive nil checks. |
| Multiple concurrent `git status` calls for same repo (e.g., two watchers fire simultaneously) | Wasted subprocess resources | Low | `SpaceGitContext` tracks `inFlightTasks` per `GitRepoID`. A new refresh cancels and replaces the existing task. `PRStatusCache` uses `pending` set to deduplicate concurrent `gh pr view` calls for the same branch/repo. |

---

## 15. Open Technical Questions

| Question | Context | Impact if Unresolved |
|----------|---------|---------------------|
| ~~Should `rainbowColors` be moved from `RainbowGlowBorder.swift` to a shared location?~~ | **Resolved.** Remove the `private` keyword from `let rainbowColors` in `RainbowGlowBorder.swift` (making it internal). No file move needed. | N/A -- resolved. |
| Should `GitStatusService` reuse `WorktreeService.runGit` or have its own subprocess runner? | Both services shell out to git using identical Process patterns. `WorktreeService.runGit` is private. | Minor code duplication. Options: (a) extract shared helper, (b) make `WorktreeService.runGit` internal, (c) duplicate in `GitStatusService`. Recommendation: extract a shared `GitProcess.run` helper. |
| How to resolve `gh` binary path cross-platform? | `gh` may be at `/usr/local/bin/gh`, `/opt/homebrew/bin/gh`, or elsewhere. `WorktreeService` uses `/usr/bin/git` directly. | If `gh` path is wrong, PR status silently fails (acceptable). Recommendation: use `/usr/bin/env` to resolve `gh` via `PATH`, or `Process` with `launchPath = "/usr/bin/env"` and `arguments = ["gh", ...]`. |
| ~~Should `SpaceGitContext` be created eagerly or lazily on `SpaceModel`?~~ | **Resolved.** `SpaceGitContext` is always created in `SpaceModel.init`, but repo detection is lazy for non-worktree Spaces (deferred until first pane reports a real working directory) and eager for worktree-backed Spaces (where `worktreePath` is known). | N/A -- resolved. |
| What happens when a restored session has panes with stale working directories? | On app restart, `SessionRestorer` recreates panes with persisted working directories. These directories may no longer be valid git repos (e.g., worktree was removed). | `SpaceGitContext` repo detection returns nil for non-existent directories. Silent failure. No impact. |
