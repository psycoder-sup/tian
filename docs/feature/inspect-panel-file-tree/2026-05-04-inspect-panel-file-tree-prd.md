# PRD: Inspect Panel — File Tree (v1)

**Date:** 2026-05-04
**Status:** Approved
**Version:** 1.2

---

## 1. Why

When working inside a tian space, the user can see *which* files have changed (the
sidebar's `GitFileListPopover` shows a flat list of changed paths) but not *where
those files live in the project*. To understand the structure of the active
worktree they currently switch to a separate file manager or run `ls` / `tree` in
a terminal pane — breaking flow inside tian. The inspect panel adds an always-
available, per-window view of the active space's working directory as a real
file tree, with M/A/D status markers overlaid in place. A single glance answers
both "what's in this project" and "what have I touched on this branch".

## 2. Goals & Non-Goals

**Goals**
- Per-workspace-window inspect panel that lists the active space's working-
  directory file tree, with the visual chrome described in the supplied design.
- Each file/directory row carries the M/A/D status from `git status` so the user
  sees pending changes in tree context without leaving tian.
- Toggle behavior matches the existing terminal panel pattern: a Close (×)
  button hides the panel, a thin right-edge "inspect" rail brings it back; both
  the visibility flag and the panel width persist across launches.
- Visual fidelity to the **Files** tab of `tian-inspect.jsx` in the design
  bundle (header height, segmented control style, tree row metrics, status
  strip).

**Non-Goals**
- Diff and Graph sub-tabs from the design (deferred to follow-up PRDs).
- Opening, previewing, editing, renaming, deleting, creating, or dragging files
  from the tree (clicks only update the selection highlight in v1).
- Search / filter / glob input inside the tree.
- Showing per-file line-count deltas (`+N / −M`) in the tree.
- Multi-root workspaces — the tree always shows the *active* space's single
  working directory, not a union of every space.
- Showing files that are excluded by `.gitignore` (they remain hidden).
- Cross-window state sync — each workspace window has independent panel state.

## 3. User Stories

1. As a tian user mid-session, I want to glance at the right side of my window
   and see my project's file tree so I know where I am without opening Finder.
2. As a tian user reviewing my own work, I want each modified or new file to
   carry a visible M/A badge in the tree so I can spot changes without running
   `git status`.
3. As a tian user with limited horizontal screen space, I want to hide the
   inspect panel and bring it back with one click so it doesn't permanently
   compete with my terminal area.

## 4. Functional Requirements

### Layout & chrome
- **FR-01:** A new inspect panel is rendered as the rightmost column of every
  workspace window, to the right of the Claude/terminal area.
- **FR-02:** The panel is 240–480 px wide, resizable by dragging its left edge.
  Default width is 320 px.
- **FR-03:** Panel header is 48 px tall (matching the existing Claude tab bar
  and terminal tab bar), background `rgba(8, 11, 18, 0.55)`, with a 0.5 px
  bottom border `rgba(255,255,255,0.05)`.
- **FR-04:** The header contains a segmented "view switcher" pill on the left
  with a single visible option labelled **Files**, pre-selected and styled per
  the design's active state. Diff and Graph entries are not rendered in v1.
- **FR-05:** To the right of the segmented control the header shows a space
  context label: `{space-name} · {context-suffix}` in the design's monospace
  11 px style, where `{space-name}` is the **currently-active** space (the
  label updates whenever the user switches spaces) and `{context-suffix}`
  is derived from the typed worktree-kind enum exposed by FR-05a.
- **FR-05a:** A typed `WorktreeKind` value is exposed to the panel for the
  active space's working directory. It has exactly four cases:
  `linkedWorktree` (rendered as `worktree`), `mainCheckout` (rendered as
  `repo`), `notARepo` (rendered as `local`), and `noWorkingDirectory`
  (the panel shows the empty state from FR-18 instead of a context label).
  This classification is computed once per active-directory change from
  the same source-of-truth used by `GitStatusService.detectRepo`, not
  re-derived ad-hoc by the panel view.
- **FR-06:** A close (×) button sits at the right edge of the header inside the
  same pill-shaped control container used by the existing terminal tab bar.
  Clicking it hides the panel.
- **FR-07:** When the panel is hidden, a thin vertical rail (~22 px wide) is
  rendered along the right edge of the workspace window, with the word
  `inspect` rotated 90°. Clicking the rail re-opens the panel.
- **FR-08:** The body region scrolls vertically; horizontal overflow on long
  filenames is truncated with an ellipsis.
- **FR-09:** A 20 px status strip is pinned to the bottom of the panel,
  rendering `files · {space-name}` left-aligned and `inspect` right-aligned in
  the design's 9.5 px monospace style. `{space-name}` is the currently-active
  space and updates on space switches. *(The literal `files` segment is a v1
  stub — when the Diff and Graph tabs land it will vary by active tab per
  the design source.)*

### File tree content
- **FR-10:** The tree's root is pinned to the active space's configured
  working directory at the *space level* (with the workspace's default
  working directory as the only allowed fallback). The panel does **not**
  follow per-pane cwd changes, OSC 7 updates, or any pane-level fallback —
  panes navigating around inside the worktree never move the tree root.
  If neither the space nor the workspace has a configured working
  directory, the panel renders the "No working directory" empty state
  (FR-18); it does **not** silently fall back to `$HOME`.
- **FR-11:** A subheader row above the tree shows a folder icon + the space
  name (left) and the same `{context-suffix}` from FR-05 right-aligned, in
  10 px uppercase letter-spaced style, with a 0.5 px bottom divider.
- **FR-12:** Each row in the tree is 24 px tall, monospace 11.5 px, and
  contains: indentation (10 px + 12 px per depth level), a chevron for
  directories, a tinted file/folder icon, the entry name, and an optional
  status badge.
- **FR-13:** Directory rows are collapsed by default. Clicking the row toggles
  expansion. Expansion state lives only for the lifetime of the workspace
  window; closing the window resets it.
- **FR-14:** File entries display the design's per-extension icon tint: `.ts /
  .tsx` blue, `.js / .jsx` yellow, `.md` slate, `.json` amber, `.sh` green,
  `.env` violet, anything else slate.
- **FR-15:** The tree shows every file that is either tracked by git or
  untracked-but-not-ignored. Files matched by `.gitignore` are not shown.
- **FR-15a:** The git-status data source feeding the panel must include
  untracked-and-not-ignored files (i.e. the equivalent of
  `git status --porcelain=v1 --untracked-files=normal`). Tracked-only
  diff data is insufficient — without untracked entries, FR-15 and FR-20
  cannot be satisfied. If the existing `GitStatusService.diffStatus`
  call does not return untracked files, a new service method or a flag
  must be added to provide them.
- **FR-16:** Hidden dotfiles (e.g. `.env`) **are** shown when not gitignored.
- **FR-17:** Symlinks are shown as files with the design's default file icon;
  their targets are not followed.
- **FR-18:** When the active space has no resolvable working directory
  (none configured and no fallbacks succeed), the panel body shows the
  centered empty state copy: `No working directory for this space.`
- **FR-18a:** When the working directory exists and is readable but
  contains zero entries the tree would show (i.e. an empty directory, or
  a directory whose every entry is gitignored), the panel body shows the
  centered empty state copy: `Nothing to show.` This state is distinct
  from FR-18 (no directory at all) and from FR-32 (still loading).

### Status badges
- **FR-19:** Each row whose path matches a `GitChangedFile` for the space's
  repo carries a single uppercase status badge to the right of the name:
  `M` (#f59e0b), `A` (#6ee19a), `D` (#ff9a9a), `R` (#60a5fa).
- **FR-19a:** Path matching: `GitChangedFile.path` values are interpreted
  as relative to the git working-tree root that the panel is currently
  rooted at (FR-10). For both regular repos and linked worktrees this
  working-tree root is the same path used to seed the file scan, so a
  single base path is canonical for both the tree's filesystem walk and
  the badge lookup. Paths are compared as canonical strings; symlinks are
  not resolved prior to comparison.
- **FR-19b:** Renames: a renamed entry produces an `R` badge on the **new**
  path only. The old path, if it still appears in the working tree (e.g.
  a partially-staged rename), is shown with a `D` badge; if the old path
  has already been removed from the working tree it does not appear in
  the tree at all.
- **FR-20:** Untracked-and-not-ignored files carry an `A` badge (green), so
  freshly-created files become visible without staging.
- **FR-21:** Directory rows do **not** carry a status badge in v1 even when
  they contain changes. (Roll-up summary deferred to a follow-up.)
- **FR-22:** When the active space's working directory is not inside a git
  repo, no badges are rendered and the subheader's `{context-suffix}` is
  `local`.

### Selection & hover
- **FR-23:** Clicking a file row sets it as the selected row. Selection is
  visual only (no file is opened). The previously-selected row, if any, is
  deselected.
- **FR-24:** The selected row is rendered with background
  `rgba(96,165,250,0.12)` and foreground `rgba(240,244,252,0.98)`.
- **FR-25:** Hovering a non-selected row paints background
  `rgba(255,255,255,0.025)`; hover does not affect selection.
- **FR-26:** Selection survives expand/collapse of any ancestor; if the
  selected file disappears (removed on disk, or now gitignored), selection
  clears.

### Refresh & active-space changes
- **FR-27:** The tree refreshes within 1 s of any of the following: the active
  space's working directory contents change on disk, the active space's git
  status changes, the user switches the active space, the active space is
  recreated (e.g. worktree teardown + recreate).
- **FR-28:** Refreshes preserve scroll position and the set of currently-
  expanded directories whenever the directories still exist post-refresh.
- **FR-28a:** When the user switches the active space, any in-flight scan
  for the previously-active space is cancelled (not merely ignored), and
  a fresh scan is started for the newly-active space. Stale results from
  a cancelled scan must never reach the rendered tree. The panel scans
  only the currently-active space at any given time — concurrent scans
  for multiple spaces are explicitly disallowed.

### Persistence
- **FR-29:** Panel visibility (shown/hidden) is persisted in the workspace's
  session state and restored on next launch of that workspace window.
- **FR-30:** Panel width is persisted in the workspace's session state and
  restored on next launch (clamped to the 240–480 px range from FR-02).
- **FR-31:** Selection and expansion state are **not** persisted across
  launches in v1.

### States
- **FR-32 (loading):** While the first scan of a working directory is in
  progress, the body shows a faint centered `Loading…` placeholder in the
  same monospace style as tree rows.
- **FR-33 (large directory):** Working directories with up to 10 000 visible
  entries scroll at 60 fps after the initial scan completes. Larger trees
  must remain interactive (no UI freeze >250 ms during scroll/expand) but
  do not have a perf guarantee in v1. *Implementation constraint: meeting
  the 60 fps target at the 10 000-entry ceiling requires virtualized row
  rendering (e.g. SwiftUI `LazyVStack` or an equivalent windowing strategy)
  — a non-virtualized list does not satisfy this requirement.*
- **FR-34 (initial scan timeout):** If the initial scan does not complete
  within 5 s, the body shows `Still loading…` and continues to populate
  incrementally as results arrive.
- **FR-35 (permission error):** If a directory cannot be read because of an
  OS permission error, that directory's row shows a muted `(no access)`
  suffix and renders no children; expansion is a no-op.

### Accessibility
- **FR-36:** Each row exposes an accessibility label of the form
  `{file or directory name}, {status word}` where `{status word}` uses the
  human-readable `GitFileStatus.accessibilityLabel` strings (`Modified`,
  `Added`, etc.) when a badge is present, otherwise omitted.
- **FR-37:** The close (×) button has the accessibility label
  `Hide inspect panel`; the right-edge rail has `Show inspect panel`.

## 5. UX & Flow

**Happy path:**
1. User opens or restores a workspace window → inspect panel renders on the
   right at the persisted width and visibility.
2. User looks at the tree → sees the space's file structure, with M/A badges
   on changed files.
3. User clicks a directory → it expands; nested files appear.
4. User clicks a file → row highlights; nothing else happens.
5. User clicks the × → panel collapses to the rail on the right edge.
6. User clicks the rail → panel re-opens at the same width and last
   selection.

**Alternate states:**
- **Empty (no working dir):** centered copy `No working directory for this
  space.` (FR-18).
- **Empty (dir exists but contains no non-ignored files):** centered copy
  `Nothing to show.` (FR-18a).
- **Loading:** centered `Loading…` placeholder while initial scan runs
  (FR-32).
- **Initial-scan slow:** swaps to `Still loading…` after 5 s (FR-34).
- **No-repo:** tree renders normally, no M/A/D badges, subheader suffix
  `local` (FR-22).
- **Permission error inside tree:** that directory's row shows
  `(no access)` and is non-expandable (FR-35).

**Mockups:** `tian-inspect.jsx` in the supplied design bundle (Files-tab
branch only); `Main Page with Inspect.html` for placement and surrounding
chrome. Reuses tian's existing 0.5 px border / monospace font / dock-pill
control vocabulary — do not introduce new design tokens.

## 6. Permissions, Privacy

**Permissions:** Reads files inside the active space's working directory
using the same access tian already has via the user's session (no new
sandbox entitlements required).
**Data:** All reads are local. Nothing is transmitted off-device. No new
data is persisted beyond the visibility flag and panel width in the
workspace's existing session state file.

*Analytics intentionally not specified for v1 — see Open Questions for
follow-up if instrumentation is added later.*

## 7. Release

- Feature flag: no — the panel ships on-by-default and can be hidden per
  workspace via the × button.
- Rollout: ship to all on the next macOS 26 build.
- Session state: a new schema version is required. The session-state
  migrator must bump its version and provide defaults for any existing
  `WorkspaceState` records that lack the new inspect-panel fields, so
  pre-v1 workspaces open with the panel visible at the default width.
  Defaults: `inspectPanelVisible = true`, `inspectPanelWidth = 320`.

## 8. Open Questions

- [ ] Should the segmented control render disabled `Diff` and `Graph` pills
      (as a visible roadmap signal) instead of being hidden in v1? Currently
      drafted as hidden (FR-04); revisit when the Diff PRD lands.
- [ ] Keyboard shortcut for toggling the panel (parity with the sidebar's
      `⌥⌘B`-style binding) — deferred until Diff/Graph land so the shortcut
      can target the panel as a whole rather than just Files.
- [ ] Roll-up status on directory rows (e.g. a small `M` on a folder if any
      descendant is modified) — deferred; FR-21 keeps directories badge-less
      in v1.
- [ ] Behaviour on very large repos (>50 k tracked files): do we virtualize
      rows, lazy-load directory contents, or both? FR-33 sets a 10 k entry
      ceiling for the v1 perf guarantee; >10 k is best-effort.
- [ ] Whether expansion state should persist across launches. FR-31 says no
      for v1; revisit if user feedback says re-expanding deeply-nested paths
      every launch is annoying.
- [ ] Telemetry: v1 ships without analytics (per author decision on
      2026-05-04). If post-launch we want to validate engagement, the
      candidate events are `inspect_panel.toggled` and
      `inspect_panel.row_interacted (action: expand|collapse|select)`; the
      candidate engagement metric is the share of panel-visible windows
      with ≥1 row interaction per session.

## Version History

- **1.0** — 2026-05-04 — Initial draft.
- **1.1** — 2026-05-04 — Devils-advocate review revisions: pinned tree
  root to space-level resolution (FR-10) with no `$HOME` fall-through;
  added explicit git-path-to-tree-path matching rule (FR-19a); dropped
  v1 success metric and analytics events per author decision; added a
  session-state migration requirement to Section 7.
- **1.2** — 2026-05-04 — Applied remaining critic items: typed
  `WorktreeKind` enum (FR-05a); explicit untracked-source requirement
  (FR-15a); rename old/new path semantics (FR-19b); active-space scan
  cancellation rule (FR-28a); promoted "Nothing to show" empty state to
  FR-18a; added virtualization implementation constraint to FR-33;
  clarified FR-05/FR-09 wording to "currently-active space"; flagged
  FR-09 status-strip `files` literal as a v1 stub.
