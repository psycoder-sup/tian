# PRD: Space Sections (Claude + Terminal)

**Author:** psycoder
**Date:** 2026-04-23
**Version:** 1.1
**Status:** Review

**Tech Stack:** Swift + SwiftUI, Ghostty embedding API (`ghostty_app_t`/`ghostty_surface_t`), macOS 26+
**Related PRDs:** `docs/feature/tian/tian-prd.md` (parent), `docs/feature/claude-session-status/claude-session-status-prd.md`

---

## Version History

| Version | Date | Author | Notes |
|---------|------|--------|-------|
| 1.0 | 2026-04-23 | psycoder | Initial draft |
| 1.1 | 2026-04-23 | psycoder | Devil's-advocate revision: FR-07 cascade safety, FR-12/FR-13 always-preserve hide model, FR-08 retry behavior, FR-14/NG4 divider vocabulary, FR-16 pixel minimums, FR-19 cross-section navigation rule, FR-09/FR-20 shortcut defaults, one-shot migration in place of wipe |

---

## 1. Overview

This feature replaces the inside of a Space with two purpose-specific sections: a **Claude section** (always present, hosts Claude Code panes) and a **Terminal section** (optional, hosts shell panes). Each section has its own independent tab bar and split tree. The Terminal section can be docked to the right of, or below, the Claude section, with a draggable divider between them. The change formalizes the way the developer already uses tian — Claude on one side, ad-hoc shells on the other — and removes friction from setting that layout up by hand each time.

---

## 2. Problem Statement

**User Pain Point:** The developer's daily workflow is: a long-lived Claude Code session in one pane, plus one or more short-lived shells nearby for `git`, `cd`, log tailing, and quick commands. Today this requires manually splitting panes inside a tab and remembering which pane is "the Claude one" vs a shell. The two roles share the same tab bar, so closing the wrong tab can kill the Claude session, and there's no enforced separation between "Claude lives here" and "shells live here." When Claude exits, the pane sits there showing a dead prompt instead of getting out of the way.

**Current Workaround:** Manually split the pane, run `claude` in one half and a shell in the other, mentally track which is which. Avoid the tab bar for Claude (because tabs apply to the whole tab, not the pane). Re-set this layout in every new Space.

**Business Opportunity:** This is a personal tool. Success means the layout the user already wants is the default, instead of being something they re-create by hand each time. Reducing per-Space setup friction directly increases time spent in flow.

---

## 3. Goals & Non-Goals

### Goals

- **G1:** Every Space has a Claude section by default, with at least one Claude pane running on creation.
- **G2:** A Terminal section can be opened on demand and docked either to the right of or below the Claude section, per Space, toggleable in the UI.
- **G3:** Each section owns an independent tab bar and split tree; tab/split/close actions on one section never affect the other.
- **G4:** Claude panes auto-close when `claude` exits (any exit code), keeping the section free of dead panes.
- **G5:** The Terminal section's visibility, position (right/bottom), tab/pane layout, and split ratio survive app quit/relaunch.
- **G6:** Closing the last Claude pane never silently kills running Terminal shells; the Space stays alive in a degraded "no Claude" state until the user explicitly closes it (or until Terminal is also empty).

### Non-Goals (v1)

- **NG1:** Long-term maintenance of the legacy persistence schema. v1 ships a one-shot migration (existing tabs become the Terminal section, a fresh Claude section is added on top); after that first migration the legacy schema is no longer read.
- **NG2:** A third section type (e.g., a logs panel, a notes panel). Only Claude and Terminal sections exist.
- **NG3:** Configurable Claude command. v1 always launches the `claude` binary found on `$PATH`.
- **NG4:** Diagonal or repositionable section dividers. The divider is vertical when Terminal is right-docked and horizontal when Terminal is bottom-docked; no other arrangements.
- **NG5:** Moving panes between the two sections (e.g., promoting a Claude pane into the Terminal section). Each pane stays in the section where it was created. Wrong-section splits must be closed and re-created.
- **NG6:** A floating/detached Terminal section (popout window). Both sections live in the same window.
- **NG7:** Per-section default working directory (separate from the Space default). Both sections inherit the existing working-directory resolution chain.
- **NG8:** Restart-on-exit behavior for Claude (no auto-respawn).
- **NG9:** Telemetry on section usage.
- **NG10:** Per-orientation split ratios. The split ratio is a single per-Space value; toggling dock position reuses the same numeric ratio (see FR-16).

---

## 4. User Stories

| # | As a... | I want to... | So that... |
|---|---------|--------------|------------|
| 1 | developer | open a new Space and immediately have Claude running | I don't have to type `claude` and wait every time I context-switch |
| 2 | developer | open a Terminal section next to Claude | I can run `git status`, `ls`, or tail a log without losing my Claude pane |
| 3 | developer | dock the Terminal section to the right or to the bottom | I can match the layout to what I'm doing (wide diff = right; long log = bottom) |
| 4 | developer | open multiple tabs of Claude in the same Space | I can have one Claude session per concern (feature work, code review, debugging) without leaving the Space |
| 5 | developer | split the Claude section into multiple Claude panes | I can run two Claude sessions side by side (e.g., one writing code, one reviewing) |
| 6 | developer | exit Claude with `/exit` and have the pane disappear | the section stays clean and I don't have to manually close empty panes |
| 7 | developer | hide the Terminal section when I don't need it | Claude has the full window for reading long output |
| 8 | developer | reopen the Terminal section and find my last layout exactly | I don't have to rebuild my shell tabs each time I toggle visibility |
| 9 | developer | drag the divider between sections | I can rebalance space without going through a menu or config file |
| 10 | developer | quit and relaunch tian | the section visibility, dock position, ratio, tabs, and panes come back exactly as I left them |
| 11 | developer | close my last Claude pane without losing my running shell jobs | a runaway `/exit` doesn't nuke the SSH session or build I have running in the Terminal section |
| 12 | developer | use the same keyboard shortcuts for tab/split/close in both sections | I don't need to memorize two sets of bindings |
| 13 | developer | navigate directionally (`focus right`, `focus down`) across the section divider | the divider feels like part of the same layout, not a wall |

---

## 5. Functional Requirements

### Section Model

**FR-01:** Every Space contains exactly one Claude section. The Claude section cannot be removed.

**FR-02:** Every Space optionally contains one Terminal section. The Terminal section starts hidden when a Space is first created.

**FR-03:** When a Space is created, its Claude section opens with one tab containing one pane that immediately spawns the `claude` binary from `$PATH`.

**FR-04:** Each section owns an independent ordered list of tabs and, within each tab, an independent split tree of panes. Tab/split/focus state in one section never references the other.

### Claude Section Behavior

**FR-05:** Every pane created in the Claude section spawns the `claude` binary on launch. Users cannot run an arbitrary shell or command in a Claude pane.

**FR-06:** When the `claude` process in a Claude pane exits successfully — for any exit code, on `/exit`, or on graceful shutdown — the pane closes immediately. No exit-code overlay is shown. (Launch failures are handled differently — see FR-08.)

**FR-07:** When the last pane in the last Claude tab closes, the Space does **not** close. Instead, the Claude section enters an "empty" state showing a placeholder with a "New Claude pane" button (and the same shortcut for new tab/pane works). The Space closes only when (a) the user explicitly closes it (via Cmd+W on the empty Claude state, or via the Space context menu), OR (b) the Terminal section is also empty (no panes), at which point the cascading-close rule from the parent PRD's FR-05 fires.

**FR-08:** If the `claude` binary cannot be found on `$PATH` or fails to launch (e.g., permission error, missing dependency), the affected pane stays open displaying the error message ("Could not launch `claude`: ...") and a "Retry" button. The pane remains open until the user retries successfully or closes the pane manually. Launch failure does **not** trigger any cascading close (no tab close, no section close, no Space close).

### Terminal Section Behavior

**FR-09:** The Terminal section is opened by clicking a "Show Terminal" button in the Claude section's toolbar. The button is also accessible via a keyboard shortcut (default: `` Ctrl+` ``, matching VS Code's terminal toggle convention; configurable per the parent PRD's FR-27).

**FR-10:** When the Terminal section opens for the first time in a Space, it is created with one tab containing one pane that spawns the user's default shell in the Space's resolved working directory (per the parent PRD's working-directory resolution chain).

**FR-11:** Every pane created in the Terminal section spawns the user's default shell. Terminal-section panes follow the existing shell-exit rules (FR-25 in the parent PRD: exit code 0 closes the pane; non-zero keeps the pane open with an exit-code message).

**FR-12:** When the last pane in the last Terminal tab closes (whether by `Cmd+W`, shell exit, or other means), the Terminal section auto-hides. Its tab/pane layout state from prior sessions is preserved (see FR-13) — the auto-hide only removes the empty section from view; it does not discard layout because there is no layout left to discard. The next "Show Terminal" creates a fresh single pane in a new tab.

**FR-13:** Hiding the Terminal section by any path (clicking "Hide Terminal", pressing the toggle shortcut, or — when at least one pane existed at hide-time — closing the section's window region) preserves the full tab/pane layout, including each pane's working directory and tab order. Reopening restores it exactly. **Shell processes in hidden Terminal panes continue running in the background**; their output continues to accumulate in their scrollback. To start fresh, the user invokes a "Reset Terminal section" action (in the Terminal section header menu) which closes all Terminal panes and returns the section to its first-open state.

### Section Layout & Position

**FR-14:** The Terminal section can be docked to the **right** of the Claude section (vertical divider — the divider line runs top-to-bottom; the user drags left/right to resize) or to the **bottom** of the Claude section (horizontal divider — the divider line runs left-to-right; the user drags up/down to resize). Default for new Spaces: right.

**FR-15:** The dock position is a per-Space setting and persists across app restarts. Users toggle position via a button in the Terminal section's header (e.g., "Move to bottom" / "Move to right"). Toggling the position must not close any panes or interrupt running processes.

**FR-16:** When the Terminal section is visible, the divider is draggable. The Claude section receives 70% of the available axis and the Terminal section receives 30% by default. The split ratio is a single per-Space value reused across both dock orientations (NG10). Drag is clamped by absolute pixel minimums, not percentages:

- **Claude section minimum:** 320 pixels along the resize axis. Drag refuses to make Claude smaller than this (hard stop).
- **Terminal section minimum:** 160 pixels along the resize axis. Dragging the divider past this minimum (toward making Terminal smaller) auto-hides the Terminal section (per FR-13: layout is preserved).

The chosen ratio persists across app restarts.

**FR-17:** When the Terminal section is hidden, the Claude section fills 100% of the Space content area.

### Focus & Keyboard Behavior

**FR-18:** Keyboard focus lives on a specific pane, not on a section. All existing pane/tab/split keyboard shortcuts (next tab, previous tab, split horizontal, split vertical, close pane, directional pane focus) act on whichever pane currently has keyboard focus — they do not depend on which section the pane belongs to.

**FR-19:** Directional pane navigation (up/down/left/right, per the parent PRD's FR-10) crosses the section divider using the existing layout-frame nearest-center match algorithm already used for intra-section navigation. Specifically:

- For each direction (up/down/left/right), the target is the pane whose layout frame's center is closest to the source pane's layout frame center along the perpendicular axis, among panes that lie on the requested side of the source.
- The algorithm treats panes from both sections as a single flat set of layout frames; the section divider is not a barrier.
- If no pane lies on the requested side (e.g., "focus right" from the rightmost Terminal pane in a right-docked layout), the focus action is a no-op.
- This rule is symmetric: "focus left" from a Terminal pane (right-docked) finds the Claude pane whose vertical span best overlaps the source; "focus up" from a Terminal pane (bottom-docked) finds the Claude pane whose horizontal span best overlaps the source.

**FR-20:** A keyboard shortcut (default: `Cmd+Shift+`` ` ``; configurable) cycles focus between sections. The first time the user invokes it from a pane in section A, focus moves to the first pane in the first tab of section B. After the user has focused panes in both sections, the shortcut alternates between the most-recently-focused pane in each section. If the target section has no panes (e.g., Terminal is hidden), the shortcut is a no-op.

**FR-21:** A new pane created via "split" inherits its section from the source pane. Splitting a Claude pane creates a Claude pane (running `claude`); splitting a Terminal pane creates a Terminal pane (running shell).

### Drag-and-Drop

**FR-22:** Tab drag-and-drop reordering works within each section's tab bar. Tabs cannot be dragged between sections (consistent with NG5).

### Persistence and Migration

**FR-23:** On app quit, each Space serializes its Claude section (tabs, split trees, working directories) and its Terminal section state (visibility, dock position, single split ratio, tabs, split trees, working directories) — including hidden Terminal layouts that have preserved state.

**FR-24:** On app launch, restored Spaces come back with their Claude section running fresh `claude` processes in each pane (no command/conversation replay) and, if applicable, their Terminal section restored to the saved visibility, dock position, ratio, and tab/pane layout. Each restored Terminal pane spawns a fresh shell in its saved working directory.

**FR-25:** On the first launch of the version that introduces this feature, the app performs a one-shot migration of any persisted state from prior versions:

- For each Space, all existing tabs/panes become the Terminal section (preserving tab order, split trees, working directories, and last-active tab/pane).
- A fresh Claude section is added with one tab and one pane that spawns `claude`.
- The migrated Terminal section is **hidden by default**, with its dock position set to the per-Space default (right) and its split ratio set to the default (0.7 Claude / 0.3 Terminal).
- After successful migration, the new schema is written to disk; the legacy schema fields are not re-read on subsequent launches (NG1).
- If migration fails (corrupted state, schema mismatch beyond recovery), the app falls back to a fresh launch (one Workspace, one Space, one Claude tab, one Claude pane) and surfaces a one-time notice with the path to the legacy file for manual inspection.

### Visual Design

**FR-26:** The Claude and Terminal sections are visually distinguishable at a glance. At minimum, each section has its own tab bar (rendered above its content area) with a section label or icon (e.g., a Claude logo for the Claude tab bar, a terminal `>_` icon for the Terminal tab bar) so the user can immediately tell which tab bar belongs to which section.

**FR-27:** The section divider is visually distinct from the divider between panes within a section (e.g., slightly thicker or a different color), so the user can tell where pane resize ends and section resize begins.

**FR-28:** The "Show Terminal" button in the Claude section toolbar is replaced by a "Hide Terminal" button when the Terminal section is visible. The icon swaps to indicate state.

**FR-29 (Loading state):** When a Claude or shell pane spawns, the pane shows a spinner overlay that auto-clears within 200ms in the typical case. If spawn takes longer than 1.5 seconds, the spinner is supplemented with a one-line status text (e.g., "Starting Claude…", "Starting shell…"). On cold-launch restore, the app spawns at most 3 Claude processes simultaneously; remaining Claude panes wait in a "Queued" state (visible spinner + "Queued" label) until a slot frees.

---

## 6. UX & Design

### Information Architecture

```
Window (macOS native)
└── Workspace
    └── Space
        ├── [Claude section toolbar: Show/Hide Terminal | Position toggle (when shown)]
        ├── Claude section (always visible)
        │   ├── Claude tab bar
        │   └── Claude split tree (0+ panes, all running `claude`; 0 panes = empty placeholder per FR-07)
        ├── Section divider (draggable, only when Terminal section is visible)
        └── Terminal section (optional, right- or bottom-docked)
            ├── Terminal tab bar (with section header menu including "Reset Terminal section")
            └── Terminal split tree (1+ panes when visible; 0 panes triggers auto-hide)
```

Right-docked layout (default):

```
+-------------------------------------------+
| [≡][Show Terminal]                        |  Claude toolbar
+----------------------------+--------------+
| [Claude tabs]              | [Term tabs]  |
+----------------------------+--------------+
|                            |              |
|   Claude panes (70%)       | Term (30%)   |
|                            |              |
+----------------------------+--------------+
                             ^
                       draggable divider
                       (vertical line, drag left/right)
```

Bottom-docked layout:

```
+-------------------------------------------+
| [≡][Hide Terminal][Move to right]         |
+-------------------------------------------+
| [Claude tabs]                             |
+-------------------------------------------+
|                                           |
|   Claude panes (70%)                      |
|                                           |
+-------------------------------------------+  <-- draggable divider
| [Terminal tabs]                           |     (horizontal line, drag up/down)
+-------------------------------------------+
|   Terminal panes (30%)                    |
+-------------------------------------------+
```

### User Flow: Create a New Space

```
Precondition: Workspace exists.

Happy Path:
1. User presses Cmd+T (or equivalent "new space" shortcut)
2. App creates a new Space
3. Claude section opens with one tab containing one pane
4. The pane immediately spawns `claude` in the Space's working directory
5. Terminal section is hidden; "Show Terminal" button visible in Claude toolbar
6. Focus is on the Claude pane

Alternate Flows:
- User cancels space-name input -> No space created
- `claude` binary not found -> Pane stays open showing error + Retry button (FR-08); Space stays open

Loading States:
- Spinner (clears <200ms typical); "Starting Claude…" text after 1.5s (FR-29)
```

### User Flow: Open Terminal Section for the First Time

```
Precondition: Active Space with Claude section only.

Happy Path:
1. User clicks "Show Terminal" in the Claude section toolbar (or presses Ctrl+`)
2. App splits the Space content area: 70% Claude / 30% Terminal (right-docked by default)
3. Terminal section appears with one tab, one pane running the user's default shell
4. Working directory of the new shell = Space's resolved working directory
5. "Show Terminal" button becomes "Hide Terminal"; "Move to bottom" button appears in Terminal header
6. Focus moves to the new Terminal pane

Alternate Flows:
- Shell fails to spawn -> Pane shows error per parent PRD FR-25

Loading States:
- Spinner (clears <200ms typical); "Starting shell…" text after 1.5s (FR-29)
```

### User Flow: Switch Terminal Position

```
Precondition: Terminal section is visible (right-docked).

Happy Path:
1. User clicks "Move to bottom" in the Terminal section header
2. App animates the Terminal section from right-docked to bottom-docked
3. Same per-Space ratio (e.g., 0.7) is reused for the new orientation (NG10)
4. Pixel minimums are re-validated; if the new layout would put either section below its minimum, the ratio snaps to the nearest valid value
5. No panes close; no shell or `claude` process is interrupted
6. "Move to bottom" button toggles to "Move to right"

Alternate Flows:
- User toggles back -> Same animation in reverse
```

### User Flow: Claude Exits in a Pane

```
Precondition: Claude pane is focused, user types `/exit` (or Claude exits cleanly).

Happy Path:
1. `claude` process exits
2. App closes the pane immediately (no exit-code overlay)
3. If the pane was the only pane in its tab -> tab closes
4. If the tab was the only Claude tab and there are other Claude tabs/panes -> focus moves to the most recently focused remaining Claude pane
5. If it was the absolute last Claude pane in the Space:
   a. Claude section enters "empty" state with placeholder + "New Claude pane" button (FR-07)
   b. Space stays open; Terminal section (if any) is unaffected; running shells continue
   c. Space closes only when user explicitly closes it (Cmd+W on empty Claude state) OR Terminal also has no panes (parent PRD FR-05 then fires)

Error States:
- N/A — Claude exits, pane closes. Errors during exit are not surfaced.
```

### User Flow: Last Terminal Pane Closes

```
Precondition: Terminal section is visible with one tab, one pane.

Happy Path:
1. User closes the last Terminal pane (Cmd+W or shell exit code 0)
2. Per FR-12, the Terminal section auto-hides
3. Claude section expands to fill 100% of the content area
4. "Hide Terminal" button reverts to "Show Terminal"
5. Focus moves to the most recently focused Claude pane
6. Next "Show Terminal" creates a fresh single Terminal pane (the section had no preserved layout to restore)

Note: This is distinct from the user explicitly hiding a populated Terminal section (FR-13), which preserves layout for restoration.
```

### User Flow: Hide and Reopen Terminal Section (Layout Preserved)

```
Precondition: Terminal section is visible with 2 tabs and a split, all running shells/jobs.

Happy Path:
1. User clicks "Hide Terminal" or presses Ctrl+`
2. Terminal section disappears; Claude section expands to 100%
3. Per FR-13, the tab/pane layout, working directories, and shell processes are preserved (shells continue running in the background)
4. User later clicks "Show Terminal" or presses Ctrl+`
5. Terminal section reappears at the saved dock position and ratio
6. All tabs, panes, and shell sessions are exactly as left
7. Focus returns to the most recently focused Terminal pane

Alternate Flows:
- User wants a fresh start -> "Reset Terminal section" from header menu closes all panes and returns to first-open state (FR-13)
```

### User Flow: App Quit and Restore (with Terminal Section Visible)

```
Precondition: Space has Claude section (2 tabs, one tab split into 2 panes) and Terminal section visible (bottom-docked, 1 tab, 1 pane).

Happy Path:
1. User quits the app
2. Confirmation dialog appears if any pane has a foreground process (per parent PRD FR-22) — covers both sections
3. App serializes: Claude tabs/panes/working dirs + Terminal section visibility=true, position=bottom, ratio=0.7, tabs/panes/working dirs
4. App sends SIGHUP to all PTY sessions and exits
5. User relaunches
6. Space restores: Claude section with 2 tabs (one split into 2 panes), each pane spawns fresh `claude` (subject to FR-29 spawn rate limit)
7. Terminal section appears at the bottom with the saved ratio, 1 tab, 1 pane spawning fresh shell in saved cwd
8. Focus restores to the last-active pane (across both sections)

Alternate Flows:
- Saved working directory no longer exists -> That pane opens in $HOME with a one-time notice (per parent PRD FR-24's spirit)
- Persisted state corrupted beyond recovery -> Fresh launch per FR-25's fallback
```

### User Flow: First Launch After Upgrade (Migration)

```
Precondition: User has prior persisted state (Workspaces with Spaces with tabs and panes running shells).

Happy Path:
1. User launches the new version
2. App reads legacy schema, runs one-shot migration per FR-25:
   - Each Space's existing tabs become its Terminal section (hidden, right-docked default, ratio 0.7)
   - Each Space gets a fresh Claude section with one tab/pane spawning `claude`
3. App writes new schema; legacy file is left in place but not re-read
4. User sees a one-time notice: "tian was upgraded. Your existing terminals are preserved in each Space's Terminal section (Ctrl+\` to show)."
5. User clicks Ctrl+\` and finds their familiar tabs/panes (with fresh shell processes in the saved cwds)

Alternate Flows:
- Migration fails -> Fresh-launch fallback per FR-25; one-time notice points to legacy file location
```

### Empty / Error / Loading States

- **Empty Claude section:** Placeholder with "New Claude pane" button + shortcut hint. Space stays open (FR-07).
- **Empty Terminal section (visible):** Cannot occur — closing the last Terminal pane auto-hides the section (FR-12).
- **Claude binary missing:** Pane stays open with error message + Retry button (FR-08). Does not cascade.
- **Shell binary missing in Terminal pane:** Existing behavior per parent PRD FR-25 (pane stays open with exit code).
- **Loading:** Spinner per FR-29; status text after 1.5s; spawn rate-limited to 3 simultaneous Claude processes during cold-launch restore.

### Wireframes / Mockups

Design concept reference: `https://api.anthropic.com/v1/design/h/_FyEBs3KULfJb9ybe-sbDA?open_file=Main+Page.html`

Note: at the time of authoring, the link returned an unreadable response from the design service. The visual treatment (colors, exact iconography, divider thickness, toolbar styling) is unresolved and tracked as open question 10.1.

### Platform-Specific Behavior

| Behavior | macOS |
|----------|-------|
| Section divider | NSSplitView-backed (or SwiftUI equivalent) draggable divider with snap-to-default-ratio at 70/30 |
| Section toggle button | SwiftUI toolbar button in Claude section header; standard SF Symbol icon |
| Position toggle | SwiftUI toolbar button in Terminal section header; SF Symbol arrow indicating dock direction |
| `Ctrl+`` ` `` shortcut | Registered via existing key binding registry |
| Animation | Standard SwiftUI section show/hide and reposition animations (~200ms) |

---

## 7. Permissions & Privacy

**Device Permissions:** None beyond what tian already requires (parent PRD Section 7).

**Data Collected / Stored / Shared:**
- Per-Space settings stored locally in the existing `~/Library/Application Support/tian/` persistence file (extended schema): Terminal section visibility, dock position, split ratio, hidden-but-preserved layout state.
- Working directories of Terminal panes (already stored for Claude/shell panes today).
- No external transmission.

**Compliance:** Not applicable.

---

## 8. Analytics & Instrumentation

No external analytics in v1 (consistent with parent PRD non-goal NG2).

**Internal observability (debug log only):**

| Signal | Purpose |
|--------|---------|
| Claude pane spawn latency | Confirm Claude launches feel instant |
| Claude pane unexpected exit count (per Space, per session) | Catch regressions where Claude exits with no user action |
| Claude launch-failure count | Catch PATH/permission regressions; correlate with Retry usage |
| Terminal section show/hide events | Confirm persistence and toggle work correctly |
| Section divider drag events with start/end ratios | Confirm drag behavior; sanity-check default ratio |
| Auto-hide-via-drag-past-minimum events | Confirm FR-16 minimum behavior is desired in practice |
| Empty-Claude-section dwell time | If users sit in the empty-Claude state for long stretches, the placeholder UI may need work |
| Migration success/failure on first launch (one-time) | Confirm the one-shot migration in FR-25 works on the user's actual data |

---

## 9. Success Metrics

Personal-tool, qualitative metrics:

| Metric | Target |
|--------|--------|
| Default-state usefulness | 100% of new Spaces are immediately usable for Claude work without user setup |
| Claude exit cleanliness | 0 dead Claude panes after `/exit` across 20 sessions (every exit cleanly closes the pane) |
| Cascade safety | 0 incidents of running Terminal shells being killed by a Claude `/exit` (FR-07 holds in practice) |
| Section divider drag | No janky frames during divider drag at 60fps |
| Section toggle latency | "Show Terminal" → first usable shell prompt within 200ms |
| Migration | First launch after upgrade produces a usable Space with all prior tabs preserved in the Terminal section |
| Daily driver | Developer no longer manually splits panes or types `claude` after creating a Space |

(The earlier "100% restore across 20 restarts" target was dropped because the listed instrumentation does not measure section visibility/dock/ratio restoration as a separate signal; the qualitative "Daily driver" target captures the same intent.)

---

## 10. Open Questions

| # | Question | Owner | Due Date |
|---|----------|-------|----------|
| 10.1 | Visual design specifics (divider thickness, exact icons, toolbar styling, section-label treatment) — design concept link returned unreadable content. Need a readable spec or screenshots. | psycoder | Before implementation |
| 10.2 | When restoring a Space, the focused-pane index may belong to either section. Should we always restore focus to the last-focused pane regardless of section, or default to the Claude section if the Terminal section was hidden at quit? | psycoder | Before implementation |
| 10.3 | FR-13 keeps shell processes alive in hidden Terminal panes. If memory/CPU usage from background shells becomes a problem in practice, should hiding suspend shells (and resume on show)? Defer until evidence appears. | psycoder | Post-v1 if needed |

(Resolved during v1.1 revision: prior 10.1 — Claude launch failure now stays open with Retry per FR-08; prior 10.2 — single shared per-Space ratio per NG10 and FR-16; prior 10.4 — defaults `Ctrl+`` ` `` toggle / `Cmd+Shift+`` ` `` cycle per FR-09 and FR-20.)

---

## 11. Appendix

### Relationship to Existing Hierarchy

The existing 4-level hierarchy (Workspace → Space → Tab → Pane) is preserved. This feature inserts an intermediate "Section" concept inside a Space:

- Before: `Space → [TabModel] → SplitTree → Pane`
- After: `Space → { ClaudeSection: [TabModel] → SplitTree → Pane, TerminalSection?: [TabModel] → SplitTree → Pane }`

The existing `SpaceModel`, `TabModel`, `PaneViewModel`, and `SplitTree` value semantics are reused; sections are containers for two parallel `[TabModel]` lists rather than a new pane primitive. The migration in FR-25 trades on this structural reuse — the legacy `Space.tabs` field is rewired into `Space.terminalSection.tabs`.

### Comparison to Comparable UIs

| Tool | Equivalent pattern |
|------|---------------------|
| VS Code | Editor area + Integrated Terminal (right or bottom dock); `Ctrl+`` ` `` to toggle |
| iTerm2 | "Status bar" + "Composer" panels, dockable |
| Cursor | Editor area + AI sidebar + integrated terminal |
| tmux | Pane splits inside a window (no role-typed sections) |

This feature is most analogous to VS Code's editor + terminal split, with Claude playing the role of the editor and the user's shells playing the role of the terminal. The default `Ctrl+`` ` `` shortcut is borrowed directly.

### Design Concept

Original design concept link (provided by user): `https://api.anthropic.com/v1/design/h/_FyEBs3KULfJb9ybe-sbDA?open_file=Main+Page.html`

This link was inaccessible at the time of authoring (gzipped binary returned). The PRD therefore captures the user's described intent; visual specifics live in open question 10.1.
