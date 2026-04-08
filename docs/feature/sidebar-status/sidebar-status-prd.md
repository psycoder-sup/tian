# PRD: Sidebar Git & Claude Session Status

**Author:** psycoder
**Date:** 2026-04-08
**Version:** 1.3
**Status:** Approved

**Figma Reference:** [aterm - Terminal Emulator, node 178-102](https://www.figma.com/design/3y7iDarBkAZ8iXsFJykrd9/aterm---Terminal-Emulator?node-id=178-102)

---

## 1. Overview

This feature adds a rich status line to each Space row in the sidebar, combining two complementary information streams: **Claude Code session status** (per-pane colored dots) and **git repository status** (branch name, file change counts, and PR state). Together they transform the sidebar from a navigation-only surface into a live project dashboard that answers three questions at a glance: "What is Claude doing?", "What branch am I on?", and "What has changed?"

The status line is the second line of the existing `SidebarSpaceRowView` VStack, replacing the current single-use status label. A Space may contain panes spread across multiple repositories (or some panes not in any git repo at all). In this case, the status line renders **one row per distinct git repo**, with each row showing the Claude dots for panes in that repo, followed by that repo's branch name, PR status, and git badges. Panes not inside any git repository have their Claude dots grouped on a separate line (or on the first repo line if only one repo is present).

When no Claude session exists, the separator dot and Claude dots are omitted from each line. When no pane in the Space is inside a git repository, only the Claude dots (if any) appear. The feature introduces no new IPC commands -- Claude session state continues to use the extended `status.set` command from the Claude Session Status PRD (v1.3, Approved). Git status is read locally by aterm and does not flow through IPC.

---

## 2. Problem Statement

**User Pain Point:** The sidebar's Space row currently shows only the space name, an active/inactive dot, a worktree branch icon, and a tab count badge. The developer cannot see which git branch a Space is on, whether there are uncommitted changes, or what state their Claude Code sessions are in without switching to that Space and inspecting the terminal output. This is especially painful when running 3-5 parallel worktree Spaces: the developer must mentally track which branch is where, whether any Space has dirty files they forgot to commit, and whether any Claude Code session is blocked on a permission prompt in a backgrounded pane.

**Current Workaround:** The developer either (a) switches between Spaces to run `git status` and check Claude output, interrupting their current work, (b) relies on free-form `status.set --label` text to surface partial information, or (c) keeps a mental map of branch-to-Space assignments that quickly becomes stale.

**Business Opportunity:** aterm's Space-as-worktree model is designed for parallel branch development. Surfacing git status and Claude session state directly in the sidebar makes this model self-documenting. The developer never needs to leave their current Space to know the state of all other Spaces. This closes the information gap that makes parallel worktree workflows feel chaotic and positions aterm's sidebar as an active project status board rather than a passive navigation list.

---

## 3. User Stories

| # | As a... | I want to... | So that... |
|---|---------|--------------|------------|
| 1 | developer | see the git branch name on each Space row in the sidebar | I can tell which branch each Space is on without switching to it |
| 2 | developer | see compact file change counts (Modified/Added/Deleted) on each Space row | I know which Spaces have uncommitted work without running `git status` |
| 3 | developer | hover over the change count badge to see the full list of changed files | I can quickly assess what changed without leaving my current Space |
| 4 | developer | see the GitHub PR status (open/draft/merged) for the current branch | I know whether I've already opened a PR and what state it's in |
| 5 | developer | see per-session colored dots for each active Claude Code session in a Space | I can monitor multiple concurrent Claude sessions at a glance |
| 6 | developer | see an orange dot immediately when any Claude session needs a permission approval | I notice blockers in backgrounded panes without manually checking each one |
| 7 | developer | see all of this information update automatically when I make git changes or Claude sessions transition | the sidebar stays current without manual refresh |
| 8 | developer | see the branch name for Spaces inside a git repo even if they are not worktree-backed | I know the branch for every Space that lives in a git-controlled directory, not only worktree Spaces |
| 9 | developer | see separate status lines when a Space has panes in different git repos | I can track git status for each repo independently without confusion |

---

## 4. Functional Requirements

### 4.1 Status Line Layout

**FR-001:** The Space row's status area (below the Space name in `SidebarSpaceRowView`'s VStack) must render when at least one of the following is true: (a) any pane in the Space has a non-nil, non-inactive Claude session state, (b) any pane's resolved working directory is inside a git repository, or (c) a free-form status label exists (existing behavior).

**FR-002:** The status area supports **multiple status lines** -- one per distinct git repository detected across all panes in the Space. Each status line's layout, from left to right, is:
1. Claude session dots for panes in that specific repo (sorted by priority, highest-priority leftmost)
2. Branch name (truncated with ellipsis if too long), spaced ~5pt after the last dot
3. PR status indicator
4. Flexible spacer
5. Git status badges (compact count format, e.g., "3M 1A 1D")

**FR-002a:** When a Space has panes in multiple distinct git repositories, the status area must render one status line per repo. Each line shows only the Claude dots for panes in that repo, that repo's branch name, that repo's PR status, and that repo's git badges.

**FR-002b:** Panes that are not inside any git repository must still display Claude dots (if they have active sessions). These dots are grouped on a separate "no-repo" line if at least one other repo line exists; if there is exactly one repo line and non-repo panes exist, the non-repo Claude dots are prepended to that single repo line (before the repo-specific dots, separated from them by a 4pt gap).

**FR-002c:** Status lines are ordered: the Space's pinned git context repo (see FR-020) first, then additional repos in alphabetical order by repo root path, then the "no-repo" line (if separate).

**FR-003:** When no Claude session dots exist for a given repo line (all panes in that repo have nil or inactive state), item 1 is omitted for that line. The line begins with the branch name.

**FR-004:** When no pane in the Space is inside any git repository, only Claude dots appear (if any), on a single line. No branch, PR, or badge information is shown.

**FR-005:** When neither Claude dots nor git info exist but a free-form status label is present, the status line displays only the label text (preserving current behavior).

### 4.2 Claude Session Dots

> Note: These requirements are derived from the approved Claude Session Status PRD (v1.3). They are reproduced here for completeness and to define how the dots integrate with the new status line layout.

**FR-010:** Each pane in a Space that has a non-nil, non-inactive Claude session state must produce one colored dot (~8pt circle) on the status line corresponding to that pane's git repo (or the no-repo line).

**FR-011:** Dots must be sorted by priority (highest-priority leftmost):

| Priority | State | Color | Hex |
|----------|-------|-------|-----|
| 1 (highest) | `needs_attention` | Orange | #FF9F0A |
| 2 | `busy` | Blue | #3282F6 |
| 3 | `active` | Green | #34C759 |
| 4 | `idle` | Gray | #8E8E93 |
| 5 (lowest) | `inactive` | -- | Not shown |

**FR-012:** Dots must be spaced ~3pt apart.

**FR-013:** The `busy` state dot must display a mesh rainbow gradient with a spinning animation (~1.5s rotation, `.rotationEffect` + `.animation(.linear.repeatForever)`). The spinning animation is always active, regardless of the system "Reduce Motion" accessibility setting.

**FR-014:** Panes with no Claude session (nil state) or ended sessions (`inactive`) do not produce a dot.

**FR-015:** Dots must update reactively when any pane's session state changes via IPC. No polling.

**FR-016:** State transitions are driven by Claude Code hooks via the extended `status.set --state` IPC command as defined in the Claude Session Status PRD:

| Hook | State |
|------|-------|
| `SessionStart` | `active` |
| `UserPromptSubmit` | `busy` |
| `Stop` | `idle` |
| `Notification` (`idle_prompt`) | `idle` |
| `Notification` (`permission_prompt`) | `needs_attention` |
| `SessionEnd` | `inactive` |

### 4.3 Git Repository Resolution & Working Directory Pinning

**FR-020:** Each Space maintains a **pinned git context** -- a set of one or more git repositories associated with its panes. The pinned context is determined as follows:
1. **Initial detection fallback chain:** `worktreePath` (if set on the Space) -> Space `defaultWorkingDirectory` -> workspace `defaultWorkingDirectory` -> active pane's OSC 7 working directory -> first pane's working directory.
2. **Pin on first detection:** When a pane's working directory first resolves to a git repo, that repo is added to the Space's pinned git context.
3. **Sticky behavior:** A pinned repo stays in the context even if the active pane `cd`s to a non-git directory. A repo is only unpinned if ALL panes that were in that repo are closed or have moved to a different repo (no pane references it anymore).
4. **Pane-to-repo reassignment:** When a pane `cd`s from repo A to repo B (detected via OSC 7 working directory change), the pane's repo association updates to repo B. This may add repo B to the pinned context (if not already present) and may unpin repo A (if no other pane references it). The pane's Claude dot moves to repo B's status line. This is the only case where a pane's repo association changes after initial detection.
5. **worktreePath priority:** The Space's `worktreePath` (if set) always takes priority as the primary git context. Its repo is always listed first in the status area.
6. **Multiple repos:** If panes in a Space span multiple distinct git repositories, all detected repos are included in the pinned context, and each gets its own status line (per FR-002a).

**FR-021:** Git repository and branch resolution must use `git rev-parse` as the **primary method**:
1. Run `git rev-parse --git-dir` from the pane's working directory to get the git directory path. If this command fails (exit code 128), the directory is not inside a git repo — stop.
2. Run `git rev-parse --git-common-dir` to get the shared repo root. This handles both regular repos and worktrees transparently.
3. The **watch path** for FSEvents is derived from the results: for regular repos (`--git-dir` returns `.git`), watch `.git/`. For worktrees (`--git-dir` returns a linked path like `../.git/worktrees/<name>`), watch both the linked gitdir AND `<common-dir>/refs/` to catch branch updates from other worktrees.
4. Two panes are considered "in the same repo" when they resolve to the same `--git-common-dir`.

> **Background (not implementation steps):** Under the hood, `git rev-parse --git-dir` returns `.git` for regular repos and the linked gitdir path for worktrees. The `.git` entry in a worktree checkout is a file containing `gitdir: <path>`, but aterm does not need to parse this manually — `git rev-parse` handles it.

**FR-022:** Branch name must be shown for ALL Spaces whose resolved working directory is inside a git repository, not only worktree-backed Spaces. A Space with `worktreePath == nil` but whose working directory happens to be in a git repo must still show its branch.

**FR-023:** Branch name must be displayed in the sidebar's secondary text style (10pt, `.secondary` foreground) and truncated with trailing ellipsis if it exceeds the available width.

**FR-024:** If no pane's resolved working directory is inside a git repository, no branch name or git status is shown for that Space.

**FR-024a:** If `git` is not installed or any `git` command fails (non-zero exit code, timeout, or crash), the affected repo's status must fail silently — no error indicators in the sidebar, no branch name, no badges. This mirrors the silent-failure behavior of `gh` in FR-054. The failure must be logged at debug level (NFR-007).

### 4.4 Branch Name Display

**FR-025:** When HEAD is a symbolic ref (e.g., `ref: refs/heads/main`), display the short branch name (e.g., `main`). When HEAD is a detached commit, display the abbreviated SHA (first 7 characters).

### 4.5 Git Diff Summary (Status Badges)

**FR-030:** Git file change status must be determined by running `git status --porcelain=v1 --ignore-submodules` (or equivalent parsing) scoped to each detected repository's working directory. Submodule changes are excluded.

**FR-031:** Changes must be summarized as compact count badges on the corresponding repo's status line, using the format `NM NA ND` where N is the count and M/A/D are modification types. Only non-zero counts are shown. Examples:
- 3 modified, 1 added, 1 deleted: `3M 1A 1D`
- 2 modified only: `2M`
- No changes: no badges shown

**FR-032:** The change types to track are:
| Code | Label | Meaning |
|------|-------|---------|
| M | Modified | File modified (tracked) |
| A | Added | New untracked file or staged addition |
| D | Deleted | File deleted |
| R | Renamed | File renamed |
| U | Unmerged | Merge conflict |

All five types are shown in both the status line badges and the hover popover.

**FR-033:** Badges must use a small, muted text style (9pt, monospaced, with subtle background pill similar to the existing tab count badge).

**FR-034:** When there are zero changes (clean working tree), no badges are shown. The spacer between branch name and badges collapses.

### 4.6 Git Diff Hover Popover

**FR-040:** Hovering over the git status badges must show a popover containing the full list of changed files with their modification types.

**FR-041:** Each row in the popover must show: (a) a single-letter status indicator (M/A/D/R/U) with a color matching its type, and (b) the file path relative to the repo root.

**FR-042:** The popover must be dismissed when the mouse leaves the badge area or the popover itself.

**FR-043:** The popover must show a maximum of 30 files. If more than 30 files are changed, a footer row must display "and N more files..." with the remaining count.

**FR-044:** If the working tree is clean (no changes), the popover must not appear (there are no badges to hover over).

### 4.7 GitHub PR Status

**FR-050:** For each repo status line whose branch has an associated GitHub pull request, the line must display a PR status indicator to the right of the branch name and to the left of the spacer.

**FR-051:** PR status must be fetched using the `gh` CLI tool (`gh pr view --json state,url,isDraft`). This limits v1 to GitHub-hosted repositories where `gh` is installed and authenticated.

**FR-052:** PR status must display as a small icon or label indicating the PR state:

| PR State | Display |
|----------|---------|
| Open | Green circle icon or "PR" label in green |
| Draft | Gray circle icon or "PR" label in gray |
| Merged | Purple circle icon or "PR" label in purple |
| Closed (not merged) | Red circle icon or "PR" label in red |
| No PR | Nothing shown |

**FR-053:** The PR status indicator must be tappable/clickable to open the PR URL in the default browser.

**FR-054:** If `gh` is not installed, not authenticated, or the remote is not GitHub, no PR status is shown. This must fail silently (no error indicators in the sidebar).

**FR-055:** PR status must be fetched on initial load and refreshed according to the caching policy defined in FR-056. PR status queries must not block the main thread.

### 4.8 PR Status Caching

**FR-056:** `gh pr view` results must be cached per branch with a **60-second TTL**:
1. After a successful `gh pr view` call, the result (PR state, URL, isDraft) is stored in a per-branch cache keyed by `(repo_root, branch_name)`.
2. Subsequent requests for the same branch within the 60-second window must return the cached result without invoking `gh`.
3. When the TTL expires, the next request triggers a fresh `gh pr view` call and refreshes the cache entry.
4. FSEvents-triggered refreshes during the TTL window must reuse the cached PR result. Only the branch name (from HEAD) and diff badges (from `git status`) are re-queried on FSEvents; PR status uses the cache until TTL expiry.
5. When the branch name changes (e.g., user checks out a different branch), the cache for the old branch is not invalidated but the new branch triggers a fresh query immediately (cache miss).
6. Cache entries are evicted when the Space is closed.

### 4.9 Git Status Refresh & FSEvents Lifecycle

**FR-060:** Git status (branch name, diff summary) must refresh automatically using FSEvents file system monitoring.

**FR-061:** FSEvents callbacks must be debounced with a ~2-second delay to avoid excessive `git status` calls during rapid file changes (e.g., during a build or large refactor).

**FR-062:** Git status must also refresh when a Space becomes active (user switches to it).

**FR-063:** Git status must refresh when a new pane is added to the Space that resolves to a git repo not yet in the pinned context (triggering addition of a new repo line).

**FR-064:** If `git status` takes longer than 5 seconds (e.g., very large repo), the previous status must remain displayed. The slow query must not block the sidebar or main thread.

#### FSEvents Lifecycle Management

**FR-065:** An FSEvents stream must be **created** when a Space's working directory is first resolved to a git repo -- either on Space creation (if the Space's default or workspace default working directory is inside a git repo) or when a pane's OSC 7 first reports a git-backed directory.

**FR-066:** An FSEvents stream must be **torn down** when the Space is closed, following the existing `onEmpty` cascade lifecycle (`PaneViewModel` -> `TabModel` -> `SpaceModel` -> `SpaceCollection` -> `Workspace`).

**FR-067:** If the pinned git context changes (e.g., a new repo is detected or all panes leave a previously pinned repo), the FSEvents stream for the affected repo must be stopped and, if a new repo replaces it, a new stream started for the new `.git` path.

**FR-068:** **All Spaces** with a detected git repo must have an active FSEvents watcher, not only the active/visible Space. FSEvents is lightweight enough to support 10+ concurrent streams. The ~2-second debounce (FR-061) prevents excessive queries across all watchers.

**FR-069:** The FSEvents **watch path** depends on the repository type:
- **Regular repos** (`.git` is a directory): watch the `.git/` directory.
- **Worktrees** (`.git` is a file pointing to a linked gitdir): watch both the worktree's linked gitdir path (resolved via `git rev-parse --git-dir`) AND the main repo's `.git/refs/` directory (resolved via `git rev-parse --git-common-dir`, appending `/refs/`). This ensures branch updates from other worktrees are detected.

---

## 5. Non-Functional Requirements

**NFR-001:** Git status queries (`git status --porcelain`, `git rev-parse`, `gh pr view`) must run on a background thread/actor. They must never block the main thread or cause sidebar UI jank.

**NFR-002:** FSEvents watching must be lightweight. Each detected git repo per Space requires one FSEvents stream (or two for worktrees per FR-069). Streams must be stopped when a Space is closed.

**NFR-003:** The debounce window (~2s) must prevent more than one `git status` invocation per repo per 2-second window, even if FSEvents fires dozens of times during that window.

**NFR-004:** Claude session state transitions via IPC must be reflected in the sidebar within 100ms (carried over from Claude Session Status PRD NFR-001).

**NFR-005:** The `busy` dot animation must use SwiftUI framework-level animation (`.rotationEffect` + `.animation(.linear.repeatForever)`) and must not cause excessive CPU/GPU usage.

**NFR-006:** PR status queries via `gh` must have a timeout of 10 seconds. If the query times out, no PR status is shown for that branch (silent failure).

**NFR-007:** State transitions and git status refreshes must be logged at debug level via the existing `Logger` utility for integration debugging.

**NFR-008:** The entire status area (potentially multiple status lines) must not cause the Space row to grow beyond a reasonable maximum height. Each status line must have consistent height regardless of content. If a Space has more than 3 repo lines, the additional lines should be accessible via hover expansion or truncated with a "+N more" indicator (edge case; unlikely in practice).

---

## 6. UX & Design

### Status Line Visual Specification

The status area sits below the Space name in `SidebarSpaceRowView`'s VStack, below the Space name and inline rename field. It uses the same horizontal padding (12pt) as the first line.

#### Single-repo Space (common case)

```
+----------------------------------------------------------+
|  * Space Name                                    2 tabs  |  <- Line 1 (existing)
|  OBG feature/auth-refactor  PR            3M 1A 1D      |  <- Line 2 (status line)
+----------------------------------------------------------+
     ^    ^                      ^           ^
     |    branch name            PR status   git badges
     claude dots (orange, blue, gray)
```

#### Multi-repo Space (panes in 2 different repos)

```
+----------------------------------------------------------+
|  * Space Name                                    3 tabs  |  <- Line 1 (existing)
|  OB feature/auth-refactor  PR             3M 1A 1D      |  <- Repo 1 (pinned context)
|  G  main                                  2M             |  <- Repo 2
+----------------------------------------------------------+
     ^    ^                                  ^
     |    branch name per repo               git badges per repo
     claude dots grouped by repo
```

In the above example: 2 panes are in repo 1 (one with orange/needs_attention, one with blue/busy), 1 pane is in repo 2 (green/active). Each repo gets its own line with its own branch, PR status, and git badges.

#### Multi-repo with non-repo panes

```
+----------------------------------------------------------+
|  * Space Name                                    4 tabs  |  <- Line 1 (existing)
|  OB feature/auth-refactor  PR             3M 1A 1D      |  <- Repo 1 (pinned context)
|  G                                                       |  <- No-repo pane (Claude dot only)
+----------------------------------------------------------+
```

When only one repo line exists and there are also non-repo panes with active Claude sessions, the non-repo dots are prepended to the single repo line:

```
+----------------------------------------------------------+
|  * Space Name                                    3 tabs  |  <- Line 1 (existing)
|  G  OB feature/auth-refactor  PR          3M 1A 1D      |  <- Single repo + non-repo dot
+----------------------------------------------------------+
     ^  ^
     |  repo-specific dots
     non-repo dot (4pt gap before repo dots)
```

**Claude dots:** ~8pt circles, spaced 3pt apart, sorted by priority. The `busy` dot uses a mesh rainbow gradient with a spinning rotation animation (~1.5s per revolution), always active.

**Branch name:** 10pt system font, `.secondary` foreground color, truncated with ellipsis.

**PR status:** Small indicator (icon or 9pt label), color-coded by state, positioned after branch name.

**Git badges:** 9pt monospaced font, muted foreground, each badge in a subtle pill background (matching the tab count badge style: `RoundedRectangle(cornerRadius: 4)` with `Color.white.opacity(0.06)` fill). Multiple badges separated by 4pt spacing.

### Hover Popover (Git File List)

The popover appears anchored below the git status badges when hovered. It has a dark background consistent with the sidebar's glassmorphism treatment. In a multi-repo Space, hovering the badges on a specific repo line shows only that repo's file list.

```
+-----------------------------+
|  M  src/auth/middleware.ts   |
|  M  src/auth/tokens.ts       |
|  M  src/auth/types.ts        |
|  A  src/auth/refresh.ts      |
|  D  src/auth/legacy.ts       |
|  and 12 more files...        |
+-----------------------------+
```

File status letters use color coding: M = yellow/amber, A = green, D = red, R = blue, U = orange.

### Empty States

| Condition | Status Area Behavior |
|-----------|---------------------|
| No Claude sessions, no pane in any git repo, no label | Status area not rendered. Row looks like current behavior. |
| Claude sessions active, no pane in any git repo | Single line with Claude dots only. |
| No Claude sessions, single git repo, clean tree | Single line: branch name only (no badges). |
| No Claude sessions, single git repo, dirty tree | Single line: branch name + badges. |
| Claude sessions + single git repo + dirty tree | Single line: dots + branch + PR + badges. |
| Multiple git repos, no Claude sessions | Multiple lines: one per repo, each with branch name + badges. |
| Multiple git repos, Claude sessions across repos | Multiple lines: each with per-repo dots + branch + PR + badges. |
| Single git repo + non-repo panes with Claude sessions | Single line: non-repo dots (4pt gap) repo dots + branch + PR + badges. |
| Multiple git repos + non-repo panes with Claude sessions | Multiple lines for repos + separate no-repo line with Claude dots. |
| `gh` not installed or not GitHub remote | PR indicator simply absent. No error state. |

### Accessibility

**FR-070:** The status area must contribute to the Space row's accessibility value. When multiple repo lines exist, each repo's status is announced sequentially. Example: "feature/auth-refactor branch, 3 modified 1 added, pull request open, 2 Claude sessions 1 needs attention. main branch, 2 modified, 1 Claude session active."

**FR-071:** The hover popover for git file list must be accessible via VoiceOver. The popover content must be announced when focused.

**FR-072:** The `busy` dot spinning animation is always active, regardless of the system Reduce Motion setting. The dot is small (~8pt) and the motion is subtle enough to not cause discomfort.

---

## 7. Scope

### In-Scope for v1

- Claude session dots (per-pane, priority-sorted, color-coded, animated busy state)
- Multi-repo support: one status line per distinct git repo when panes span multiple repos
- Git repository and working directory pinning (sticky context, not flickering on `cd`)
- Worktree-aware git directory resolution (via `git rev-parse --git-dir` / `--git-common-dir`)
- Git branch name on all git-backed Spaces (worktree and non-worktree)
- Git diff summary as compact count badges (M/A/D)
- Hover popover for full file list with modification types (M/A/D/R/U)
- GitHub PR status via `gh` CLI (open/draft/merged/closed) with 60-second TTL cache
- FSEvents-based refresh with ~2s debounce, full lifecycle management (start/stop/restart)
- FSEvents watching on worktree linked gitdir + main repo refs
- Accessibility labels for status line content (multi-line aware)

### Out-of-Scope / Future

- **Non-GitHub forges** (GitLab, Bitbucket, etc.) -- v1 is GitHub-only via `gh` CLI
- **Detailed PR info** (review status, CI checks, comment count) -- v1 shows only state
- **Git stash count** -- potentially useful but not in v1
- **Ahead/behind count** relative to upstream -- useful but adds complexity; deferred
- **Auto-focus on `needs_attention`** -- switching to a pane when Claude needs a permission prompt is a future enhancement
- **Workspace-level git aggregation** -- v1 shows git status per-Space only, not rolled up to the Workspace header
- **Inline git actions** (commit, push, pull from sidebar) -- sidebar is read-only for git in v1
- **Configurable refresh interval** -- hardcoded ~2s debounce for v1
- **Persisting Claude session state across app restarts** -- session state is ephemeral
- **Timeout/staleness detection** for Claude busy state

---

## 8. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Status line renders correctly for git-backed Spaces | 100% of Spaces inside a git repo show branch name | Manual QA across worktree and non-worktree Spaces |
| Multi-repo Spaces show separate status lines | Spaces with panes in 2+ repos show one line per repo | Manual QA with multi-repo Space |
| Working directory pinning prevents flickering | Sidebar branch name does not change when active pane `cd`s out of repo | Manual QA: cd to non-git dir and verify sidebar is stable |
| Claude dots reflect session state within 100ms | <100ms from IPC receipt to sidebar update | Instrument with debug logging timestamps |
| Git status refresh latency after file change | <3s from file save to badge update (2s debounce + query) | Manual testing with FSEvents debug logging |
| No main-thread blocking from git queries | 0 main-thread hangs >16ms caused by git/gh subprocess calls | Xcode Instruments Time Profiler |
| Hover popover displays full file list | Popover shown on hover with correct file list for repos with 1-100+ changes | Manual QA |
| PR status shown for branches with open PRs | PR indicator appears when `gh pr view` returns data | Manual QA with test repo |
| PR cache reduces gh CLI calls | Repeated FSEvents within 60s do not trigger additional `gh pr view` calls | Debug logging: count gh invocations per 60s window |
| Busy dot always spins | Busy dot mesh rainbow animation is active regardless of Reduce Motion | Manual verification |
| FSEvents streams cleaned up on Space close | No orphaned FSEvents streams after closing Spaces | Debug logging + Instruments leak check |

---

## 9. Dependencies

| Dependency | Type | Status | Notes |
|------------|------|--------|-------|
| Claude Session Status PRD (v1.3) | Feature PRD | Approved | Defines `status.set --state` IPC extension, state machine, and hook configuration. This PRD depends on that work being implemented. |
| `PaneStatusManager` | Existing code | Implemented | Tracks per-pane status labels. Must be extended to also store session state (per Claude Session Status PRD). |
| `SidebarSpaceRowView` | Existing code | Implemented | The view being modified to add the status area. Currently shows status label from `PaneStatusManager.latestStatus(in:)`. |
| `IPCCommandHandler.handleStatusSet` | Existing code | Implemented | The IPC handler to be extended with `--state` parameter support. |
| `aterm-cli status set` | Existing CLI command | Implemented | The CLI command to be extended with `--state` flag. |
| `gh` CLI | External tool | User-installed | Required for PR status. Must be installed and authenticated by the developer. Not bundled with aterm. |
| `git` CLI | External tool | System-provided | Required for branch name, diff status, and repo resolution (`git rev-parse`). Available on all macOS systems with Xcode CLT. |
| FSEvents / `DispatchSource.makeFileSystemObjectSource` | System API | Available | macOS file system event monitoring for .git directory watching. |
| Claude Code hooks system | External | Available | Developer must install hook configuration in Claude Code settings. See Appendix A of Claude Session Status PRD. |

---

## 10. Open Questions

All open questions have been resolved:

| # | Question | Resolution |
|---|----------|------------|
| 1 | Should the branch name be linkable? | **No.** Branch name is static text. PR status is the only clickable element. |
| 2 | Should the hover popover support Esc dismissal? | **No.** Mouse-out only. |
| 3 | Max branch name length before truncation? | **Dynamic.** Based on available sidebar width, accounting for dots, PR indicator, and badges. |
| 4 | Include submodule changes? | **No.** Top-level repo only. Pass `--ignore-submodules` to `git status`. |
| 5 | Distinguish "no PR" vs "gh unavailable"? | **No.** Both show no indicator. |
| 6 | Should R and U appear in badge counts? | **Yes.** Renamed (R) and unmerged (U) files are included in both the status line badges and the hover popover. |

---

## 11. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-04-08 | Initial draft. Combines Claude session dots (from approved Claude Session Status PRD v1.3) with git branch name, diff summary badges, hover popover, and GitHub PR status into a unified sidebar status line. |
| 1.1 | 2026-04-08 | Revision after review (score 0.68). **Multi-repo support:** status area renders one line per distinct git repo when panes span multiple repos; Claude dots grouped by repo; non-repo panes handled. **PR caching:** 60s TTL cache for `gh pr view` results (FR-056); FSEvents refreshes reuse cache during TTL window. **FSEvents lifecycle:** explicit start/stop/restart/scope/watch-path requirements (FR-065 through FR-069). **Worktree git resolution:** algorithm using `git rev-parse --git-dir` and `--git-common-dir` (FR-021). **Working directory pinning:** sticky git context prevents flickering when panes cd out of repo (FR-020 rewritten). Resolved OQ#4 (PR caching) and OQ#8 (multi-repo Spaces). Renumbered remaining open questions. |
| 1.2 | 2026-04-08 | Clarification fixes after second review (score 0.85). **FR-021:** Clarified `git rev-parse` as primary method; manual `.git` parsing moved to background note. **FR-024a:** Added silent-failure spec for `git` unavailable/failing (mirrors `gh` behavior in FR-054). **FR-020.4:** Added pane-to-repo reassignment policy — pane moves repos on `cd`, Claude dot follows, old repo unpinned if no other pane references it. |
| 1.3 | 2026-04-08 | Section-by-section review and approval. **Separator dot removed** — Claude dots flow directly into branch name with ~5pt spacing. **Busy dot always spins** — no Reduce Motion exception (FR-013, FR-072). **R/U in badges** — renamed and unmerged files now shown in status line badges, not just hover popover (FR-032). **Submodules excluded** — `--ignore-submodules` flag added (FR-030). **All 6 open questions resolved:** branch name not clickable, popover mouse-out only, dynamic branch truncation, no submodules, no PR/gh distinction, R/U in badges. Status: Approved. |
