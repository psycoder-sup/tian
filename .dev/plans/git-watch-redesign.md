# Git-watch redesign — implementation plan

Implements **ADR 0005** (A + B + C). Read the ADR first: `docs/pm/decisions/0005-app-global-git-monitor.json`.

**Goal:** kill the daily-drive lag from the git-watch layer — ~12k git spawns / 3 days, 96/min "Not a git repo" storm, dead-worktree error churn, 899 uncapped `gh pr view` — by moving watching to an app-global repo-keyed `GitMonitor`, splitting the trigger signal, and gating the expensive working-tree watcher on visible-or-busy.

**Verify success by re-running the log greps** (`grep app_cpu`, `Not a git repo` per-min bursts, `[git] ERROR` count, `gh pr view` count) after each phase and confirming they drop.

---

## Current shape (what we're replacing)

- `SessionGitContext` — one per `Session` (`Session.swift:201`). Owns per-session: `watchers`, `remotePollers`, `prCache` (60s TTL), `refreshScheduler` (250ms / maxConcurrent 2), `repoStatuses`, `statusByWorktreeRoot`.
- `GitRepoWatcher` — one recursive file-level FSEventStream over the whole working tree (2s latency), fires `refreshScheduler.schedule(repoID)`.
- `refreshRepo` / `refreshWorktreeStatus` — shell `currentBranch` + `diffStatus`, and on PR-cache miss spawn `launchPRFetchIfNeeded` → `gh pr view` (OUTSIDE the scheduler cap).
- `detectAndRefresh` / `paneWorkingDirectoryChanged` — raw `Task { detectRepo }` per OSC 7 cwd event (OUTSIDE the scheduler, no cache).
- `GitStatusService.runGit` — `Process()` on `DispatchQueue.global(qos: .userInitiated)`, no global cap.

Reused as-is: `RefreshScheduler` + `AsyncSemaphore` (`Utilities/RefreshScheduler.swift`), `PRStatusCache` (make it a single shared instance), `WindowVisibilityState` (`isVisible`) + `sessionIsVisible` env, `ClaudeSessionState.resumesWork` (busy/active).

---

## Phase 0 — quick mitigations (ship immediately, survive the refactor)

Low-risk, high-relief, no architecture change. Land first.

- `GitStatusService.runGit` (both call sites ~L1096, L1257): QoS `.userInitiated` → `.utility`.
- `PRStatusCache.ttl`: 60 → 300s.
- (Optional stop-gap, superseded by Phase 4) tear down watcher + drop repo state when `detectRepo`/refresh sees the dir no longer exists — cuts the dead-worktree error churn before GitMonitor GC lands.

**Files:** `Core/GitStatusService.swift`, `Core/PRStatusCache.swift`, `Session/SessionGitContext.swift`.
**Verify:** `[git] ERROR` count drops; no behavior change to badges.

---

## Phase 1 — `GitMonitor` skeleton + global concurrency + subscription (A, foundation)

New app-global owner. Not yet wired to sessions — unit-tested standalone.

- **New `Core/GitMonitor.swift`** — `@MainActor @Observable final class GitMonitor`. App-scoped singleton (inject via environment / `GhosttyApp`-adjacent, mirror how other app singletons are held). Keyed by `GitRepoID`.
  - Owns: `watchers`, `remotePollers`/`remotePollTicks`, one shared `PRStatusCache`, one `RefreshScheduler<GitRepoID>` (maxConcurrent can rise to ~3–4 now it's truly global), `repoStatuses`, `statusByWorktreeRoot`, `branchGraphDirty`.
  - Two concurrency lanes: `gitLocalSemaphore` (AsyncSemaphore, ~3–4) and `ghNetworkSemaphore` (~2). Route `runGit`-backed calls through git-local, `fetchPRStatus` through gh-network. Either GitMonitor wraps the service calls, or `GitStatusService` gains an injected limiter.
  - Subscription API + refcount:
    - `subscribe(repoID:worktreeRoot:) -> SubscriptionToken`
    - `unsubscribe(_ token)`
    - first subscriber for a repoID → start refs watcher (Phase 2) + slow PR poll; last unsubscribe → stop watchers/pollers, cancel in-flight tasks, drop caches, GC.
  - Read API for the view/adapter: `status(forWorktreeRoot:)`, `status(forRepo:)`, `branchGraphDirty(forRepo:)`.
- **Move `PRStatusCache`** ownership here (single instance); TTL already 300s from Phase 0; add network-failure backoff (exponential, capped) so a `gh` timeout doesn't immediately re-fire.

**Files:** new `Core/GitMonitor.swift`; light edits to `Core/PRStatusCache.swift`, `Core/GitStatusService.swift` (limiter injection); app wiring (`Core/GhosttyApp.swift` or `TianApp`).
**Tests:** new `tianTests/GitMonitorTests.swift` — subscribe/unsubscribe refcount, GC at zero, concurrency-lane caps, cache sharing across two subscribers of one repo.

---

## Phase 2 — split the signal: refs watcher vs working-tree watcher (B)

- **`Core/GitRepoWatcher.swift`** — add a scope. Either a `WatchScope { case refs, workingTree }` param or two static path resolvers:
  - `resolveRefsWatchPaths(for:)` → `.git/HEAD`, `.git/refs`, `.git/packed-refs`; for worktrees add `commonDir/refs` + worktree `gitDir`. Low-churn.
  - `resolveWorkingTreeWatchPaths(for:)` → the working tree (existing `resolveWatchPaths` minus refs). High-churn.
  - Reuse existing `pathsAffectPRState` / `pathsAffectBranchGraph` classifiers.
- **In `GitMonitor`:**
  - Refs watcher: always-on per subscribed repo. Drives branch refresh, `branchGraphDirty`, and PR-cache eviction on push/fetch (`pathsAffectPRState`).
  - Working-tree watcher: created/destroyed by the Phase-3 gate. Drives ONLY diff/dirty refresh.
  - PR fetch: remove from the working-tree refresh path. Fire on refs-driven eviction + slow `PollingRefresher` (300s) + on gate-open. Backoff on failure.
  - Split `refreshRepo` into `refreshBranchAndRefs(repoID)` (cheap, refs-triggered) and `refreshWorkingTree(repoID)` (diff, gate-triggered).

**Files:** `Core/GitRepoWatcher.swift`, `Core/GitMonitor.swift`.
**Tests:** extend `tianTests/GitRepoWatcherTests.swift` — refs-scope vs worktree-scope path resolution; assert working-tree events don't trigger PR fetch.

---

## Phase 3 — visible-or-busy gating of the working-tree watcher (C)

- **`GitMonitor` gate:** per repoID, `shouldWatchWorkingTree = any subscriber is (windowVisible && sessionIsVisible) || claudeState.resumesWork`.
  - Track per-subscriber activity: `setSubscriberActivity(token, visible: Bool, busy: Bool)`.
  - On any change recompute the repo gate: open (was closed) → start working-tree watcher + one eager `refreshWorkingTree`; close (was open) → stop the FSEventStream entirely (frees the callback churn, not just the shell-out).
- **Signal wiring (feed the monitor):**
  - Visible: `WindowVisibilityState.isVisible` (window occlusion) AND `sessionIsVisible` (active session in workspace). Session/view observes both and pushes to its subscription token.
  - Busy: session's Claude pane `ClaudeSessionState` — push `resumesWork` on state change (already flows through `PaneStatusManager`).

**Files:** `Core/GitMonitor.swift`, `Session/Session.swift` / `Session/SessionGitContext.swift` (push activity), a small observer where `WindowVisibilityState` + `sessionIsVisible` are known (`View/Session/*` or `WorkspaceWindowContent`).
**Tests:** `GitMonitorTests` — gate opens on visible, opens on busy-while-hidden, closes only when neither; eager refresh on open; watcher stopped on close.

---

## Phase 4 — `SessionGitContext` → thin adapter + detection cache

- **Strip** `watchers`, `remotePollers`, `prCache`, `refreshScheduler`, `repoStatuses`, `statusByWorktreeRoot` from `SessionGitContext`. It keeps: `paneDirectories`, `paneRepoAssignments`, `paneWorktreeRoot`, detection triggers, and subscription tokens per active worktreeRoot.
  - `paneWorkingDirectoryChanged` / `detectAndRefresh` → detect (cached), then `GitMonitor.subscribe/unsubscribe` as panes move; feed activity.
  - Sidebar reads proxy to `GitMonitor.status(...)` — **preserve the `repoStatuses` / `statusByWorktreeRoot` read-shape** so `View/Sidebar/*` is untouched (adapter exposes the same computed properties).
- **Detection cache** (in `GitMonitor` or a small `DetectionCache`): `path -> RepoLocation?` with a negative-result TTL; `detectRepo` runs debounced through the git-local semaphore. Kills the "Not a git repo" storm (re-detect only on cache miss / explicit invalidation).
- **GC dead worktrees** falls out of refcounting — remove any Phase-0 stop-gap.

**Files:** `Session/SessionGitContext.swift` (large shrink), `Core/GitMonitor.swift`, maybe new `Core/DetectionCache.swift`; verify `View/Sidebar/*` compiles unchanged.
**Tests:** update `tianTests/SessionGitContextTests.swift` to the adapter shape; new detection-cache tests (negative TTL, invalidation).

---

## Phase 5 — verify + tune

- Add a `perf`/`git` log counter: git-spawn count + gate open/close transitions.
- Re-run the diagnostic greps; confirm: `Not a git repo` bursts gone, `[git] ERROR` ~0, `gh pr view` count way down, no `app_cpu` hot samples during builds.
- Tune `gitLocalSemaphore` / `ghNetworkSemaphore` limits, PR TTL, debounce.
- Live-verify per memory `live-verify-via-debug-app`: build `tian-debug.app`, open two sessions in the same repo (confirm ONE watcher via `activeWatcherCount`-equivalent on the monitor), background one while Claude runs (busy keeps diff live), background+idle one (diff goes stale, branch/PR stay live).

---

## Orchestration notes

Phases are sequential (each builds on the prior); `SessionGitContext` + `GitMonitor` are touched in 1/3/4, so they are NOT file-disjoint across phases — run phases as ordered waves, parallelize only WITHIN a phase where files are disjoint (e.g. Phase 2 `GitRepoWatcher` vs Phase 1's cache edits are independent). Do Phase 0 as its own tiny first wave for immediate relief.

Per project memory: don't run `tianUITests`; a lone `WorktreeOrchestrator`/`GitStatusService` failure under parallel load is flaky — re-run in isolation. A fresh worktree needs `tian/Vendor` + `.ghostty-src` symlinked from main before it can build.
