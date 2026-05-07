# PRD: Inspect Panel — Files / Diff / Branch Tabs (v2)

**Date:** 2026-05-07
**Status:** Approved
**Version:** 0.2
**Supersedes:** v1 header (FR-04 single-pill "Files" header from
`2026-05-04-inspect-panel-file-tree-prd.md`).

---

## 1. Why

The v1 inspect panel ships a single tab — **Files** — with a placeholder
segmented control whose Diff and Graph entries are deliberately hidden
(v1 PRD §8 open question). The user already has access to *what files
have changed* through the file tree's M/A/D badges, but to inspect the
**actual line changes** they leave tian for a terminal `git diff` or an
editor's diff view, and to understand **how the current branch relates
to its surroundings** they run `git log --graph` in a pane. Both of
these tasks belong inside the inspect panel — same window, same active
space, same chrome.

This PRD lifts the deferred Diff and Branch tabs out of v1's open
questions and into a real feature, matching the v2 design preview
(`Inspect Panel.html`, `tian-inspect-v2.jsx`).

## 2. Goals & Non-Goals

**Goals**

- A three-position tab switcher — **Files**, **Diff**, **Branch** — at
  the top of the inspect panel, replacing v1's single "Files" pill.
- A per-tab info strip directly below the switcher that renders
  contextual metadata for the active tab (replaces v1's `FR-11`
  subheader inside the file browser).
- A **Diff** tab that renders the active space's working-tree diff vs.
  `HEAD`, grouped by file, with per-file headers, hunk headers, and
  unified +/- line gutters — visually matching the design's
  `GitDiffView`.
- A **Branch** tab that renders a commit graph for the active space's
  repo: the current branch and its near neighbours, with lanes, parent
  edges, HEAD/branch tags, and per-commit author/time/message —
  visually matching the design's `BranchGraph`.
- Tab switching is instant, local to the workspace window, and does
  not refetch git data the panel already has.
- The **Files** tab keeps every behavior from the v1 PRD; this PRD only
  re-homes its FR-11 subheader content into the new info strip.
- **Framing:** Diff and Branch are *quick-check* views — useful for
  confirming the scope of a change or the shape of nearby branch
  history before a commit. They are explicitly **not** a replacement
  for a full diff client or `git diff` in a terminal pane; the 5 000-
  line per-file cap (FR-T15) and 50-commit graph cap (FR-T20) reflect
  this scope, not technical shortcuts.

**Non-Goals**

- No file-content view, no diff-line authoring (no stage/unstage, no
  edit-from-diff, no "view full file" button).
- No commit detail drill-down, no graph zooming, no branch checkout
  from the graph, no rebase / merge / cherry-pick actions.
- No remote operations (no `git fetch`, no `gh pr` calls beyond what
  v1 already performs for the sidebar PR badge).
- No comparing arbitrary refs in either tab (Diff is always
  `worktree vs HEAD`; Branch is always rooted at `HEAD`).
- No persistence of the active tab across launches — the panel always
  opens on **Files** (v1 behavior). Persisting the last-active tab is
  deferred.
- No keyboard shortcuts for switching tabs in this revision (the v1
  PRD's panel-toggle shortcut question is also still deferred).

## 3. User Stories

1. As a tian user mid-edit, I want to flip from the file tree to the
   actual diff in one click so I can review my own changes without
   leaving the window.
2. As a tian user about to commit, I want to see hunk-by-hunk every
   working-tree change against `HEAD` for the active space so I can
   confirm nothing surprising is about to land. *(The Diff tab shows
   `git diff HEAD` — staged and unstaged changes folded together. It
   does **not** distinguish the staging boundary; that's deferred —
   see Open Questions.)*
3. As a tian user merging or rebasing, I want a quick visual on where
   my branch sits relative to `main` (and any sibling feature branches)
   without typing `git log --graph --oneline --decorate`.
4. As a tian user, I want the panel to remember which tab I was on
   while I'm in the same workspace window, so context-switching to and
   from the file tree feels free.

## 4. Functional Requirements

### Tab switcher (replaces v1 FR-04)

- **FR-T01:** The inspect panel header is split into two stacked rows:
  a 38 px **tab row** and a 26 px **info strip**. Total fixed chrome
  above the scrollable body is 64 px. v1's chrome was 48 px (header
  only); v1's 24 px FR-11 subheader rendered inside the body, not as
  fixed chrome. Net effect: v2 consumes 16 px more fixed chrome on the
  Files tab than v1 in exchange for unified context across all three
  tabs and removal of the in-body subheader (FR-T09). Background tones
  and the 0.5 px bottom border match the design values —
  `rgba(8, 11, 18, 0.4)` for the tab row, `rgba(8, 11, 18, 0.3)` for
  the info strip.
- **FR-T02:** The tab row contains a single capsule-style segmented
  control on the left with three options in this order: **Files**,
  **Diff**, **Branch**. Active option uses the design's glass gradient
  fill (`linear-gradient(180deg, rgba(255,255,255,0.10),
  rgba(255,255,255,0.04))` + `inset 0 1px 0 rgba(255,255,255,0.12)`);
  inactive options are transparent with muted text.
- **FR-T03:** The right side of the tab row hosts the existing inspect-
  panel toggle (the "hide panel" rectangle-with-divider icon that was
  promoted to the floating window-edge rail in v1). The floating
  `InspectPanelRail` overlay continues to handle the *re-open* case
  when the panel is hidden — the in-row button only handles the
  *hide* case while the panel is open.
- **FR-T04:** Clicking a tab activates that tab; the selection is local
  to the workspace window and does not persist across launches
  (FR-T11). Switching tabs does not unload sibling tab state, so
  scroll position and any in-tab selection survive a round trip.
- **FR-T05:** The default tab on first render and after every relaunch
  is **Files** (v1 parity).

### Info strip (replaces v1 FR-11)

- **FR-T06 (Files tab info):** The info strip shows
  `{spaceName} · {context-suffix}` where `{context-suffix}` is the
  WorktreeKind label from v1 FR-05a (`worktree`, `repo`, `local`, or
  hidden in the no-directory state). This duplicates the content v1
  rendered in the file-browser subheader (FR-11) and renders it once,
  in the info strip, regardless of which tab is active.
- **FR-T07 (Diff tab info):** The info strip shows
  `{N} files`, `+{additions}`, `−{deletions}` chips reflecting the
  totals from the data feeding the Diff tab body (FR-T15). When the
  diff is empty the strip shows `No changes`.
- **FR-T08 (Branch tab info):** The info strip shows
  `{branchName} · graph` (or `{shortSha} · graph` if HEAD is
  detached). When the active space is not in a git repo the Branch
  tab is unavailable — see FR-T19.
- **FR-T09:** The 24 px file-tree subheader from v1 (FR-11) is removed.
  Its content is now carried by the info strip (FR-T06). The file
  tree body starts immediately after the info strip.

### Diff tab body

- **FR-T10:** The Diff tab renders the working-tree-vs-HEAD diff for
  the active space's git repo, grouped by file. Files that are
  untracked-and-not-ignored are included as fully-added files (every
  line shows as a `+` line). Files matched by `.gitignore` are not
  included.
- **FR-T10a (binary / oversized file gate):** Before invoking
  `git diff --no-index /dev/null <path>` for an untracked file, the
  service checks the file size via `FileManager.attributesOfItem`. If
  the size exceeds **512 KB**, the diff for that file is replaced with
  a single placeholder line `Binary or large file — N bytes` and no
  subprocess is spawned. The same placeholder is used for any tracked
  file that `git diff` reports as binary (`Binary files differ`
  marker). This guards against runaway subprocess cost and stdout
  blowup on checked-in lockfiles, media, or compiled artifacts that
  slipped past `.gitignore`.
- **FR-T11:** Each file group is collapsible. The group header is
  ~28 px tall and contains: a chevron, a status-color dot
  (modified=blue, added=green, deleted=red), the file's repo-relative
  path, the uppercase status word, and the per-file `+{adds}` /
  `−{dels}` counts on the right. Clicking the header toggles
  collapse; collapse state is local to the workspace window and
  resets on launch.
- **FR-T12:** Each hunk inside a file group renders the hunk header
  line (e.g. `@@ -12,9 +12,14 @@`) at 10.5 px monospace in the
  design's blue-tinted bar, followed by the unified diff lines.
- **FR-T13:** Each diff line is a four-column grid:
  `[old line #][new line #][marker][text]`. Marker is `+` for adds,
  `−` for deletes, blank for context. Background tints match the
  design (`rgba(34,197,94,0.08)` for adds, `rgba(239,68,68,0.09)` for
  deletes, transparent for context). Long lines wrap with
  `whiteSpace: pre-wrap`.
- **FR-T14:** The Diff tab is virtualized at the file-group level if
  the diff exceeds 500 changed lines — large diffs must keep
  scrolling at 60 fps inside the existing 240–480 px-wide panel.
- **FR-T15:** The Diff body is fed by a new `GitStatusService` method
  (working name `GitStatusService.unifiedDiff(directory:)`) that
  returns a typed structure equivalent to:
  ```
  struct GitFileDiff: Sendable {
      let path: String
      let status: GitFileStatus
      let additions: Int
      let deletions: Int
      let hunks: [GitDiffHunk]
  }
  struct GitDiffHunk: Sendable {
      let header: String
      let lines: [GitDiffLine]
  }
  struct GitDiffLine: Sendable {
      enum Kind: Sendable { case context, added, deleted }
      let kind: Kind
      let oldLineNumber: Int?
      let newLineNumber: Int?
      let text: String
  }
  ```
  Implementation calls `git diff --no-color --no-ext-diff
  --unified=3 HEAD` (plus `--patch` over `git status --porcelain`
  output for untracked files), parses the hunk headers and `+`/`-`/
  ` ` line prefixes, and caps each file at 5 000 lines (excess lines
  show a muted `… N more lines` placeholder; the user can not expand
  them in this revision).
- **FR-T16 (Diff loading):** While the first diff fetch for a space
  is in flight, the Diff body shows the same `Loading…` placeholder
  used by v1 FR-32. Subsequent refreshes do not show the
  placeholder; the previous diff stays visible until the new one
  lands.
- **FR-T16a (initial-scan × tab interaction):** During the initial
  file-tree scan for a space (the v1 `isInitialScanInFlight` window —
  `worktreeKind` not yet resolved), the Diff and Branch tab pills are
  rendered visually muted and are **non-interactive** — clicks are
  ignored — regardless of which tab the user was previously on. The
  Files tab continues to drive the panel during this window using the
  existing v1 loading-state copy (FR-32 / FR-34). Once the scan
  resolves, the Diff and Branch tabs become interactive in their
  natural state (no-repo copy from FR-T19, or live data). This closes
  the race where a user clicks Diff before `worktreeKind` is known.
- **FR-T17 (Diff empty):** When the diff is empty the body shows
  `No changes against HEAD.` centered in the same muted style as
  v1 empty states.
- **FR-T18 (Diff refresh):** The Diff tab refreshes within 1 s of the
  same triggers v1 uses for FR-27 (working-directory change, git
  status change, active-space switch), with two implementation
  constraints layered on top:
  1. **Trailing debounce, ≥500 ms.** The Diff refresh runs on its
     **own** trailing-debounce window, distinct from the 250 ms window
     used for FR-27. `git diff HEAD` is materially more expensive than
     `git status --porcelain` and must not piggy-back on the file-tree
     scan's cadence.
  2. **Single in-flight call per space; cancel-on-new.** A new
     `unifiedDiff(directory:)` call cancels the previous one for the
     same space using the same `Task.cancel()` /
     `withTaskCancellationHandler` pattern `GitStatusService.runGit`
     already employs (`SpaceGitContext.refreshRepo`). Refresh storms
     during `npm run build` / Vite HMR / similar FSEvents floods must
     never produce an unbounded queue of `git diff` subprocesses.

  Refreshes preserve which file groups the user has collapsed, when
  the file is still present in the new diff.
- **FR-T19 (No-repo handling):** When the active space is not in a git
  repo (v1 FR-22 `local` state), the Diff and Branch tabs are still
  selectable but show centered copy `Not in a git repository.` Their
  info strip omits the per-tab metadata.

### Branch tab body

- **FR-T20:** The Branch tab renders a commit graph for the repo of
  the active space, rooted at HEAD and walking back up to **50
  commits** along first-parent of the local branches present at the
  time of the fetch. Lanes correspond to distinct branch tips; HEAD's
  lane is rendered first.
- **FR-T20a (lane cap):** At most **6 lanes** are rendered with their
  own gutter column. If the repo has more than 6 distinct branch
  tips inside the 50-commit window, the surplus tips are folded into
  a single dimmed "other" lane drawn at the far-right gutter
  position; commits whose home lane is collapsed still appear as
  rows but their gutter node sits in the "other" lane and is colored
  with a neutral grey. The info strip's branch summary appends a
  `+N more` count when collapse is in effect. Lane priority for
  inclusion (highest → lowest): HEAD's lane, lanes shared by HEAD's
  visible ancestors, the active space's tracked remote branch (if
  set), branches with the most commits inside the 50-commit window.
  Ties broken alphabetically.
- **FR-T21:** Each commit row is 38 px tall and contains: short SHA
  (7 chars), commit subject, optional HEAD/branch chip(s) (e.g.
  `feature-auth`, `origin/main`), optional tag chip (e.g. `★ v0.4.1`),
  and a one-line meta footer `author · relative time` plus `merge`
  if the commit has >1 parent.
- **FR-T22:** Lane gutter (left of the row) renders an SVG with
  vertical lane rails and curved parent edges using the design's per-
  lane colors. The current commit (HEAD) gets a 1 px ring around its
  node. Merge commits render as hollow nodes; other commits as filled
  nodes.
- **FR-T23:** A 32 px lane legend at the top of the tab body lists
  each visible lane with a colored dot and the branch label, in lane
  order.
- **FR-T24:** Clicking a row is a no-op in this revision (visual
  highlight only). Hover states match the file tree's hover treatment
  (`rgba(255,255,255,0.025)` background).
- **FR-T25:** The Branch body is fed by a new `GitStatusService`
  method (working name `GitStatusService.commitGraph(directory:)`)
  that returns a typed structure equivalent to:
  ```
  struct GitCommitGraph: Sendable {
      let lanes: [GitLane]      // ordered, HEAD's lane first
      let commits: [GitCommit]  // newest → oldest
  }
  struct GitLane: Sendable {
      let id: String            // branch ref name
      let label: String
      let color: Color          // resolved from a fixed palette by lane index
  }
  struct GitCommit: Sendable {
      let sha: String           // 40-char
      let shortSha: String      // 7-char
      let laneIndex: Int
      let parentShas: [String]
      let author: String
      let when: Date
      let subject: String
      let isMerge: Bool
      let headRefs: [String]    // branch and remote-tracking refs at this commit
      let tag: String?          // exact tag at this commit, if any
  }
  ```
  Implementation issues exactly **three** subprocess calls per
  refresh — never one-per-commit:
  1. `git log --max-count=50 --date-order
     --pretty=format:'%H%x09%h%x09%P%x09%an%x09%at%x09%s'
     --decorate=short` for the commit list.
  2. `git for-each-ref refs/heads refs/remotes
     --format='%(refname:short) %(objectname)'` for lane resolution.
  3. `git tag -l --format='%(objectname:short) %(refname:short)'` for
     all tags in the repo, parsed once into a `[String: String]`
     short-sha → tag map. The per-commit `tag` field is then a
     dictionary lookup, not a subprocess. (Per-commit
     `git tag --points-at <sha>` is **not** acceptable — it produces
     up to 50 extra subprocess invocations and blows the
     ~300 ms render budget in §5.)
- **FR-T26 (Branch loading):** While the first graph fetch for a space
  is in flight, the Branch body shows the same `Loading…` placeholder.
- **FR-T27 (Branch empty / no-repo):** When HEAD is the only commit
  and there are no other branch tips, the body still renders that
  single commit. When the space is not in a git repo, the no-repo
  copy from FR-T19 wins.
- **FR-T28 (Branch refresh):** The Branch tab refreshes only when the
  active space's repo's HEAD or local-ref set changes. Working-
  directory mutations alone do **not** trigger a Branch refetch
  (avoids re-rendering the graph on every save).
- **FR-T28a (Branch-graph watch predicate):** The differential signal
  feeding FR-T28 does **not** exist in the current codebase and must
  be added. `GitRepoWatcher` already exposes a
  `pathsAffectPRState(_:canonicalCommonDir:) -> Bool` predicate that
  filters FSEvents batches for `refs/remotes/*` / `packed-refs`
  changes; this PRD requires a **parallel** predicate
  `pathsAffectBranchGraph(_ paths: [String], canonicalCommonDir:
  String) -> Bool` that returns `true` whenever any path in the batch
  is under `commonDir/refs/heads/` or equals `commonDir/HEAD` or
  `commonDir/packed-refs`. `SpaceGitContext` invokes this predicate
  in the same FSEvents callback that already gates `prCache.evict`,
  and uses its result to flip a per-repo `branchGraphDirty` flag the
  Branch tab reads when it becomes visible (or when already visible,
  to schedule a refresh on the same `RefreshScheduler` debounce
  bucket). Branch-graph fetches must never run as a side-effect of
  working-tree FSEvents alone.

### Tab state container

- **FR-T28b (data-model sketch):** Tab-local state that must survive a
  tab round-trip (FR-T04) lives **above** the SwiftUI view layer, not
  in `@State` inside the per-tab body view. Either (a) extend
  `InspectPanelState` with the additional fields, or (b) introduce a
  sibling `@MainActor @Observable InspectTabState` owned by the
  workspace alongside `InspectPanelState`. Either container owns at
  minimum:

  ```swift
  enum InspectTab: String, Codable { case files, diff, branch }

  @MainActor @Observable
  final class InspectTabState {
      var activeTab: InspectTab = .files       // FR-T29
      var diffCollapse: [String: Bool] = [:]   // path → collapsed
      // Branch tab carries no per-row state in this revision.
  }
  ```

  Scroll position per tab is owned by the SwiftUI body using
  `ScrollViewReader` with named anchors (`"diff-top"`,
  `"branch-top"`) — restoring on `.onAppear` after a tab switch is
  acceptable. A naive `TabView` + `@State` scroll offset does **not**
  satisfy FR-T04; the implementation must hoist the relevant state
  above the per-tab view.

### Persistence & state

- **FR-T29:** The active tab **is** persisted across workspace
  launches in the workspace's existing session state. On restore the
  panel opens to the persisted tab (defaulting to Files for any
  workspace whose state pre-dates this PRD). Active tab is also
  preserved across panel hide/show within the same launch.
- **FR-T30:** Per-file Diff collapse state is **not** persisted across
  launches. It **is** preserved across tab switches and panel hide/
  show within the same launch.
- **FR-T31:** Persistence of `inspectPanelVisible` and
  `inspectPanelWidth` from v1 (FR-29 / FR-30) is unchanged. **A
  session-state schema bump is required** to add the persisted
  `activeTab` field (FR-T29); see §7. The session-state migrator must
  default missing `activeTab` values to `files` on read.

### Status strip

- **FR-T35 (status strip per active tab):** v1 FR-09 defines a 20 px
  status strip pinned to the bottom of the panel with hardcoded
  `files · {spaceName}` on the left. v1 itself flagged this as a
  deferred-to-v2 stub. With three tabs in play, the left segment
  becomes:
  - `files · {spaceName}` when the Files tab is active
  - `diff · {spaceName}` when the Diff tab is active
  - `branch · {spaceName}` when the Branch tab is active

  The right segment (`inspect`, muted) and overall typography (9.5 px
  monospace, 0.5 px top divider) are unchanged. `InspectPanelStatusStrip`
  must accept the active tab as input rather than hardcoding the
  literal `files`.

### Accessibility

- **FR-T32:** The tab control uses SwiftUI accessibility primitives
  (not web ARIA): the tab container carries
  `.accessibilityElement(children: .contain)`. Each tab button
  carries `.accessibilityLabel` of `"Files"`, `"Diff"`, or `"Branch"`
  and `.accessibilityAddTraits(.isSelected)` when it is the active
  tab. (The original draft used `tablist` / `aria-selected`, which
  do not translate directly to SwiftUI; the spec is normalized to
  what AppKit-backed SwiftUI accessibility actually exposes.)
- **FR-T33:** The Diff tab's per-file group headers expose
  `{path}, {status word}, {N} additions, {M} deletions` as their
  accessibility label, matching the v1 file-row pattern.
- **FR-T34:** The Branch tab's commit rows expose
  `{shortSha}, {subject}, by {author}, {relative time}` as their
  accessibility label; merge commits append `, merge`.

## 5. UX & Flow

**Happy path:**

1. User opens or restores a workspace window → inspect panel renders
   on the right at the persisted width and visibility, on the **Files**
   tab.
2. User clicks **Diff** → the body crossfades (instant) to the diff
   view; the info strip swaps to `{N} files +{add} −{del}`.
3. User collapses two file groups they don't care about → the
   remaining groups stay visible; collapse persists for the rest of
   the session.
4. User clicks **Branch** → graph renders within ~300 ms; HEAD's
   commit has a ring; sibling lanes are dimmed but visible.
5. User flips back to **Files** → file tree is exactly where they
   left it (scroll, expansion, selection all preserved).

**Alternate states:**

- **No git repo:** Diff and Branch tabs render centered
  `Not in a git repository.`; info strip drops the per-tab
  metadata. Files tab continues to work (v1 FR-22).
- **No working directory:** all three tabs are unselectable — the
  panel renders v1's `No working directory for this space.` empty
  state across the entire body. Tab pills remain visible but are
  visually muted and non-interactive.
- **Diff loading:** centered `Loading…` (FR-T16).
- **Diff empty:** centered `No changes against HEAD.` (FR-T17).
- **Branch loading:** centered `Loading…` (FR-T26).

**Mockups:** `Inspect Panel.html` (isolated panel) and
`tian-inspect-v2.jsx` from the supplied design bundle.

## 6. Permissions, Privacy

**Permissions:** Reuses tian's existing access to the active space's
working directory; no new sandbox entitlements required. Adds two
read-only `git` invocations (`git diff`, `git log`) per refresh — the
same subprocess pattern v1 uses for `git status`.

**Data:** All reads are local. Nothing is transmitted off-device. No
new state is persisted to disk.

## 7. Release

- **Feature flag:** none. Ships on-by-default; replaces v1's single-
  pill header verbatim.
- **Rollout:** ships to all on the next macOS 26 build.
- **Session state:** schema bump required to add the persisted
  `inspectActiveTab: String?` field on `WorkspaceState` (FR-T29 /
  FR-T31). Migrator default for pre-v2 records: `activeTab = files`.
  Diff collapse map and branch fetch cache remain in-memory.

## 8. Open Questions

- [ ] **Surfacing the staging boundary in the Diff tab.** FR-T10's
      `git diff HEAD` folds staged and unstaged changes together —
      user story 2 is now factually accurate but a user reviewing
      pre-commit may still want to see *which* changes are staged.
      Candidate fix: source `git diff --cached HEAD` separately and
      tag each hunk (or each line) with its staging origin. Deferred
      until we see whether users complain in practice.
- [ ] Should clicking a Diff file-group header *also* select the
      corresponding row in the Files tab (so flipping back highlights
      the file)? Currently FR-T11 is collapse-only.
- [ ] Should the Branch tab walk further back than 50 commits, or
      offer a "Show more" affordance at the bottom? FR-T20 caps at 50
      and FR-T20a caps lanes at 6; revisit if users routinely scroll
      to either cap.
- [ ] Lane-priority ordering inside FR-T20a's 6-lane budget —
      currently "HEAD's lane → ancestors → tracked remote → most-
      commits". Open whether to expose user-pinned lanes (e.g. always
      show `main` even if it falls outside the priority window).
- [ ] Keyboard shortcuts for tab switching (e.g. `⌥⌘1 / 2 / 3`).
      Deferred to align with the v1 panel-toggle shortcut question.
- [ ] Diff line-wrapping vs. horizontal scroll for very long lines —
      FR-T13 currently mandates wrap; some users may prefer scroll.

## Version History

- **0.1** — 2026-05-06 — Initial draft from v2 design preview
  (`KNp6ePtfshenWJNndrhaMw` handoff bundle: `Inspect Panel.html`,
  `tian-inspect-v2.jsx`, chats 5 / 7 / 8). Introduces the three-way
  tab switcher, retires v1 FR-04 (single Files pill) and v1 FR-11
  (in-tree subheader), and specifies the new
  `GitStatusService.unifiedDiff` / `commitGraph` data sources.
- **0.2** — 2026-05-07 — Devil's-advocate revisions (all 13 items
  accepted by author). Blockers: FR-T10a binary/oversized-file gate;
  FR-T28a `pathsAffectBranchGraph` watch predicate spec; FR-T18
  ≥500 ms debounce + cancel-in-flight rule. Major fixes: FR-T20a
  lane cap with "other" lane; FR-T25 reduced to three subprocess
  calls (no per-SHA `git tag --points-at`); user story 2 corrected
  to match `git diff HEAD` semantics with staging-boundary deferred
  to Open Questions; FR-T16a initial-scan × tab-click race spec;
  FR-T35 status-strip-per-active-tab; FR-T28b tab-state data-model
  sketch. Minor: FR-T29 inverted to *persist* active tab (with §7
  schema bump); §1 Goals adds quick-check framing; FR-T01 chrome
  accounting reframed honestly (+16 px on Files in exchange for
  unified per-tab context); FR-T32 ARIA → SwiftUI accessibility
  primitives. PRD relocated to canonical
  `docs/feature/inspect-panel-tabs/` directory.
