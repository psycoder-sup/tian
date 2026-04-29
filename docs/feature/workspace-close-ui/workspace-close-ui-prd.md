# PRD: Worktree Space Close Progress UI

**Author:** psycoder
**Date:** 2026-04-29
**Version:** 1.1
**Status:** Approved

---

## 1. Overview

Worktree Spaces today show a rich progress UI during creation: a mini progress row in the sidebar, a floating bottom-right capsule with step counter, command label, and cancel button, and live archive script output streaming inside the active pane. This same surface is missing on the inverse operation — closing a worktree-backed Space and tearing down its environment via the `[[archive]]` commands defined in `.tian/config.toml`. Today, archive commands run silently inside `WorktreeOrchestrator.removeWorktreeSpace`, the user has no visibility into which step is running, and there is no way to cancel a long-running teardown.

This feature mirrors the creation progress UI for the close/remove flow: the sidebar row remains visible with a mini progress indicator, the floating capsule shows step counter and command label with a cancel button, and archive command output streams inside the visible pane. If any archive command fails or the user cancels, the cleanup pipeline halts, the worktree on disk is preserved, and the failure is surfaced via the same `didFailRun` glyph used by creation. Only after all archive commands succeed does tian run `git worktree remove` and prune empty parent directories. Even when no archive commands are configured, a brief "Removing worktree..." capsule renders so the user always gets visual confirmation that removal is in flight.

---

## 2. Problem Statement

**User Pain Point:** When the developer closes a worktree-backed Space with archive commands configured (e.g., `docker compose down`, `npm run db:teardown`, `pkill watchman`), tian runs those commands silently with no UI. The developer cannot tell which step is running, cannot cancel a hung command, and cannot see error output if a command fails. If the entire teardown takes 30+ seconds (e.g., container shutdown, port release, lockfile cleanup) the sidebar appears frozen — the Space row sits there until removal completes or `git worktree remove` errors out. The asymmetry with the creation flow (which has a polished progress capsule, sidebar progress row, and cancel button) feels unfinished and breaks the user's trust that tian knows what it's doing during teardown.

**Current Workaround:** The developer either (a) accepts the silent wait and assumes nothing has gone wrong, (b) tails `~/Library/Logs/tian/tian.log` in a separate pane to confirm progress, or (c) avoids defining archive commands at all and runs teardown manually before triggering close — defeating the whole point of `[[archive]]` automation.

**Business Opportunity:** The Worktree Spaces feature already invested in a progress UI design that is well-understood and trusted by the user (sidebar mini row + floating capsule with cancel button). Reusing that surface for close/remove completes the worktree lifecycle: every long-running stage of the worktree's life — creation setup, removal teardown — has consistent, observable, cancellable progress. This makes archive commands as first-class as setup commands and removes the last asymmetry in the worktree workflow.

---

## 3. User Stories

| # | As a... | I want to... | So that... |
|---|---------|--------------|------------|
| 1 | developer | see step-by-step progress while archive commands run on Space close | I know what tian is doing during teardown and can spot which step is slow |
| 2 | developer | see archive command output in the visible pane (just like setup) | I can debug a failing teardown command without leaving the Space |
| 3 | developer | cancel an in-flight archive cleanup with one click or Ctrl+C | I am not stuck waiting for a hung teardown command |
| 4 | developer | have the worktree preserved if archive fails or I cancel | I do not lose work or end up with an inconsistent state because a teardown step did not complete |
| 5 | developer | retry the close after fixing the archive script | I can iterate on my teardown logic without manually re-creating the worktree |
| 6 | developer | see a brief "Removing..." indicator even when no archive commands are configured | I always have visual confirmation that close is in progress, even on the fast path |

---

## 4. Functional Requirements

### 4.1 Trigger and Confirmation

**FR-001:** The close progress UI is triggered only by the "Remove Worktree & Close" path of `WorktreeCloseDialog`. The "Cancel" button dismisses the dialog with no side effects. The "Close Only" path is modified per FR-003. The existing three-button confirmation dialog layout itself is unchanged.

**FR-002:** The CLI `tian-cli worktree remove` command (FR-019 of the Worktree Spaces PRD) must drive the same close progress UI as the in-app confirmation dialog. From the user's point of view, the sidebar progress row and floating capsule appear identically regardless of whether removal was triggered from the GUI, a keyboard shortcut, or the CLI.

**FR-003:** When the user selects "Close Only" in `WorktreeCloseDialog` AND the Space's repo has at least one `[[archive]]` command configured in `.tian/config.toml`, tian must present a secondary confirmation: *"This Space has archive commands that will not run. Skip teardown and close the Space?"* with buttons `[Skip Teardown]` and `[Cancel]`. If the user picks Skip Teardown, the Space closes without running archive and without removing the worktree on disk. If the user picks Cancel, the secondary confirmation is dismissed and the Space remains open. When the Space's repo has no `[[archive]]` commands, the secondary confirmation is suppressed and "Close Only" behaves as today (close the Space without removing the worktree).

### 4.1.1 Phase Model and View Wiring (Required Code Changes)

The existing creation progress UI was built around the word "Setup". The close flow needs to drive the same surface with different labels ("Cleanup n/N", "Removing..."). The PRD requires the following minimal additions to existing components — no new components are introduced, but the listed existing components require small modifications:

**FR-004:** The `SetupProgress` model must gain a `phase` enum (or equivalent string field) with values `setup`, `cleanup`, and `removing`. The orchestrator sets `phase` when initializing progress for a flow. `phase` is the single source of truth for the user-visible label prefix.

**FR-005:** The `SetupProgressCapsule` view's hardcoded `"Setup \(progress.stepText)"` rendering must be replaced with a phase-driven label: `"Cleanup n/N"` for `cleanup`, `"Setup n/N"` for `setup`, and `"Removing..."` for `removing` (no step counter). The capsule must conditionally hide the cancel button when `phase == .removing` (FR-022).

**FR-006:** The `setupProgressRow()` helper in `SidebarSpaceRowView` must render the phase-driven prefix in front of `progress.stepText` ("Setup", "Cleanup", or "Removing...") using the same phase enum as the capsule.

**FR-007:** The `runShellCommands` method in `WorktreeOrchestrator` currently guards `setupProgress` updates with `if label == "setup"`. This guard must be lifted (or generalized to update `setupProgress` whenever it is non-nil regardless of label) so that archive commands also drive the progress model. Without this change, every progress requirement in this PRD is inert.

### 4.2 Sidebar Progress Row

**FR-010:** While archive commands are running for a Space, that Space's row in the sidebar must render the same mini progress indicator used by creation: a small `ProgressView` next to the Space name, the Space name itself, a "Cleanup n/N" step counter, and the failure glyph if `didFailRun` is true. This mirrors the `setupProgressRow()` rendering in `SidebarSpaceRowView` for creation.

**FR-011:** The label on the sidebar row during removal must read **"Cleanup n/N"** (not "Setup n/N"), where `n` is the 1-based index of the currently running archive command and `N` is the total number of archive commands. This makes the row's purpose unambiguous when both creation and removal can occur in the same session.

**FR-012:** When no archive commands are configured (empty `archiveCommands` array, or no `.tian/config.toml`), the sidebar row must show the mini progress indicator with the label **"Removing..."** for the duration of `git worktree remove` + directory pruning. No step counter is shown in this case (there are no discrete steps).

**FR-013:** On archive success, the sidebar row's progress indicator and label disappear at the same moment the Space itself is removed from the sidebar (after `git worktree remove` and pruning complete). There is no separate "done" state on the row — the row simply ceases to exist.

**FR-014:** On archive failure or user cancellation (FR-040), the orchestrator must nil out `setupProgress` immediately. The 3-second failure linger is held by `displayedProgress` in `WorkspaceWindowContent` (the existing creation-flow pattern) and applies to the **capsule only**. The sidebar row reverts to the Space's normal display at the moment `setupProgress` becomes nil. This prevents an inconsistency where the capsule and sidebar row have desynchronized failure states. Acknowledging the trade-off: the sidebar row does not linger on the failure glyph, but the capsule's prominent bottom-right linger remains the primary failure feedback. The Space remains open and the worktree on disk is preserved.

### 4.3 Floating Capsule

**FR-020:** While archive commands or `git worktree remove` are running, a floating capsule must appear at the bottom-right of the workspace window, identical in styling and position to the creation capsule (`SetupProgressCapsule`). The capsule must contain:
1. A spinner or progress glyph (when running) / failure glyph (when failed)
2. The step text (e.g., "Cleanup 2/3" or "Removing...")
3. The current command label (truncated with ellipsis), e.g., `npm run db:teardown`
4. A cancel button (xmark.circle.fill) — see FR-040

**FR-021:** When archive commands exist, the step text in the capsule must read **"Cleanup n/N"** matching FR-011.

**FR-022:** When no archive commands exist, the capsule must read **"Removing..."** with no command label and no cancel button. This brief state covers the duration of `git worktree remove` + directory pruning. Cancel is not offered here because the operation is past the point of safe reversal once `git worktree remove` has begun.

**FR-023:** The capsule must show the failure glyph and linger for 3 seconds (matching the creation flow's `didFailRun` behavior in `WorkspaceWindowContent`) when an archive command fails or the user cancels, then dismiss.

**FR-024:** Only one close-progress capsule is shown at a time per workspace window. If a second worktree Space close is triggered while a first is in progress, the second close must be queued (sequential) — see FR-061.

### 4.4 In-Pane Archive Output

**FR-030:** Archive commands must run inside the visible pane of the Space being closed, typed into the pane's terminal after shell readiness is detected (OSC 7 or fallback delay), exactly as setup commands run during creation. The user sees command output stream in real time and the commands appear in shell history.

**FR-031:** The "visible pane" for archive execution is the currently-focused pane within the Space. If the Space has multiple panes (split tree), archive runs in whichever pane has focus when the close confirmation is given. A focused pane is always present in practice — the close action (menu item, keyboard shortcut, or CLI invocation) requires a Space context, and the Space's `PaneViewModel` always has a non-nil `focusedPaneID`. If for any reason `focusedPaneID` is nil, tian must fall back to the deepest first child of the split tree (matching `PaneViewModel.fromState` focus resolution and the creation flow's `FR-032`).

**FR-032:** During archive execution, the Space remains active and its panes remain interactive — the user can scroll, copy text, switch panes, and observe output. The Space is **not** dimmed, modally blocked, or otherwise visually distinguished beyond the sidebar progress row and the floating capsule.

**FR-033:** Archive commands run sequentially. Each command waits for shell readiness before being typed (matching FR-028 of the Worktree Spaces PRD). tian does not detect exit codes from interactively-typed commands directly — instead, success is inferred from the absence of a kill signal and the absence of a user cancel. The `lastFailedIndex` mechanism in `SetupProgress` is used only for explicit failure signals (e.g., `runShellCommands` exit code reporting; see FR-050).

### 4.5 Cancellation

**FR-040:** During archive execution, the user must be able to cancel via two mechanisms, identical to creation:
1. The cancel button (xmark.circle.fill) in the floating capsule
2. Ctrl+C inside any pane of the Space

Either mechanism sends SIGTERM to the currently running command (via the existing `KillGuard` cancellation token in `WorktreeOrchestrator`) and skips all remaining archive commands.

**FR-041:** Cancellation halts the cleanup pipeline before `git worktree remove` runs. The worktree on disk is **preserved**, the Space remains open, and the sidebar row + capsule show the failure glyph (FR-014, FR-023). The user can re-trigger close from the same Space after addressing whatever caused them to cancel.

**FR-042:** Cancellation is not offered during `git worktree remove` itself (the no-archive case in FR-022, and the post-archive case after all archive commands succeed). Once archive has succeeded and tian begins the irreversible filesystem operations, the cancel button is hidden.

### 4.6 Failure Handling

**FR-050:** If any archive command exits with a non-zero status (detected via `runShellCommands` exit code reporting in `WorktreeOrchestrator`), the cleanup pipeline must halt immediately. The behavior matches FR-041: skip remaining archive commands, do **not** run `git worktree remove`, preserve the worktree on disk, keep the Space open, show the failure glyph for 3 seconds.

**FR-051:** The failed archive command's index must be recorded in `setupProgress.lastFailedIndex` so the failure glyph appears at the correct step position in the sidebar progress row and capsule (matching the creation flow's `didFailRun` rendering).

**FR-052:** All archive failures (cancellation included) must be logged via the existing `Logger` utility under the `worktree` category. Log entries must include the Space ID, branch name, worktree path, the failed command, and the exit code (or "cancelled" for cancellation). This enables post-hoc debugging.

**FR-053:** If `git worktree remove` itself fails after archive succeeds (e.g., uncommitted changes, locked file), the existing error flow continues to apply: `WorktreeError.uncommittedChanges` triggers `WorktreeForceRemoveDialog`, and other `git worktree remove` errors are surfaced verbatim per FR-217 of the Worktree Spaces PRD. Before presenting any of these error dialogs, the orchestrator must set `setupProgress = nil` synchronously (on the `MainActor`) so the progress capsule and sidebar row dismiss before the modal alert appears. This prevents a visible overlap between the capsule's "Removing..." state and the modal alert.

**FR-054:** If directory pruning (FR-030 of the Worktree Spaces PRD) fails for any reason after `git worktree remove` succeeds, the failure must be logged at warning level but must **not** roll back the removal or surface a user-facing error. The Space is already gone; pruning is a hygiene operation only.

### 4.7 Reentrancy and Concurrency

**FR-060:** The user must not be able to trigger close on the same Space twice while a close is in progress. Once `WorktreeCloseDialog` is confirmed for a Space, the close menu item, keyboard shortcut, and CLI removal request for that Space must be no-ops (or return a "close already in progress" error from the CLI) until the close pipeline terminates (success, failure, or cancellation). Note that `SidebarSpaceRowMutationGate` already removes the "Close Space" context menu item entirely while `setupProgress != nil` — this behavior is inherited and intentional. During archive, the only cancel affordances are the capsule cancel button and Ctrl+C; the context menu is hidden, not greyed.

**FR-061:** Concurrent close requests are rejected via an explicit in-flight guard, not queued. `WorktreeOrchestrator` must expose an `isCloseInFlight: Bool` (or equivalent) that is set to `true` at the start of `removeWorktreeSpace` and cleared in a `defer` block (covering success, failure, and cancellation). While `isCloseInFlight == true`:
- A second close request for the same Space is a no-op (FR-060).
- A second close request for a *different* Space returns an error: GUI selection of "Remove Worktree & Close" displays an inline error ("Another worktree is being closed. Try again in a moment."); the CLI returns a non-zero exit with the same message.

This avoids the data-race risk of overlapping `commandsCancelled` resets and the complexity of a pending-close queue. Sequential queueing is explicitly out of scope (Section 8). Only one close-progress capsule is shown at a time per workspace window (FR-024) and this is enforced naturally by the in-flight guard.

**FR-062:** If the user closes the entire workspace (window close) while an archive is mid-flight, tian must invoke `worktreeOrchestrator.cancelCommands()` from `WorkspaceWindowController.windowShouldClose` (and from the corresponding `NSApp.terminate` path) before allowing the window to close. Cancellation is fire-and-forget SIGTERM via the existing `KillGuard` cancellation token — the window-close path does not block awaiting the kill to take effect. The worktree on disk is preserved (no `git worktree remove` runs). On next launch, the worktree-backed Space is restored as a normal worktree Space with its `worktreePath` intact (existing session-restore behavior).

### 4.8 Persistence

**FR-070:** No new persistent state is introduced by this feature. All progress state (`SetupProgress` for the close flow) is in-memory only and is discarded on app quit. The Space's `worktreePath` and existence in the session state are unchanged whether or not a close was attempted.

---

## 5. Non-Functional Requirements

**NFR-001:** Sidebar progress row updates and capsule updates during archive execution must be reflected within 100ms of the underlying `setupProgress` snapshot mutation (matching the creation flow's reactivity).

**NFR-002:** Archive command execution must not block the main thread. All shell process spawning, reading, and signal handling must run on background actors/queues, identical to the creation flow's `runShellCommands` pathway.

**NFR-003:** No new UI components must be introduced for the close flow. The progress surface must reuse the existing `SetupProgress` model, `SetupProgressCapsule` view, and `SidebarSpaceRowView.setupProgressRow()` rendering. The minimal modifications to those existing components — phase enum on the model (FR-004), phase-driven label on the capsule (FR-005), phase-driven prefix on the sidebar row (FR-006), conditional cancel button (FR-005, FR-022), and lifted label guard on the orchestrator (FR-007) — are spec'd as part of this feature, not separate work.

**NFR-004:** When 5+ worktree Spaces are open simultaneously and one is being closed, the in-progress close must not cause perceptible UI lag (>16ms frame drops) in the other Spaces' sidebar rows or panes.

**NFR-005:** If `runShellCommands` for archive hangs (no progress, no exit), the existing per-command timeout from `.tian/config.toml` `setup_timeout` (default 300 seconds) must apply identically to archive commands. On timeout, the command is killed and the failure path (FR-050) runs.

---

## 6. UX & Flow

### 6.1 Happy Path: Close Worktree Space with Archive Commands

```
Precondition: User has a worktree-backed Space open. The Space's repo has
              .tian/config.toml with [[archive]] commands defined
              (e.g., docker compose down; npm run db:teardown).

1. User opens the sidebar context menu on the Space row and selects
   "Close Space" (or invokes the equivalent keyboard shortcut /
   tian-cli worktree remove <space-id>).
2. tian shows WorktreeCloseDialog (NSAlert) with three buttons:
   [Remove Worktree & Close] [Close Only] [Cancel]
3. User clicks "Remove Worktree & Close".
4. tian initializes setupProgress for the close pipeline:
   currentIndex=0, totalCommands=N (number of archive commands),
   currentCommand=first archive command label.
5. The sidebar row for that Space replaces its normal status display
   with the mini progress indicator + "Cleanup 1/N" + command label.
6. The floating capsule appears at bottom-right of the workspace window
   with "Cleanup 1/N", the command label, and a cancel button.
7. tian waits for shell readiness in the visible pane (OSC 7 or fallback).
8. tian types the first archive command into the visible pane.
   Output streams in real time.
9. After the command completes (shell readiness signal returns),
   setupProgress advances: currentIndex=1 (0-based), currentCommand=second command.
   stepText renders "2/N", so sidebar row and capsule update to "Cleanup 2/N".
10. Steps 7-9 repeat until all N archive commands have run successfully.
11. Capsule transitions to "Removing..." (no command label, no cancel).
    Sidebar row updates to "Removing...".
12. tian runs: git worktree remove <worktree-path>
13. tian prunes empty parent directories up to worktree_dir root.
14. tian removes the Space from the SpaceCollection.
15. Sidebar row disappears; capsule dismisses immediately.
```

### 6.2 Happy Path: Close Worktree Space with No Archive Commands

```
Precondition: User has a worktree-backed Space whose repo has no
              .tian/config.toml or has an empty [[archive]] section.

1-3. Same as 6.1 (open menu, confirm dialog, click Remove).
4.   Sidebar row shows mini progress + "Removing..." (no step counter).
5.   Capsule appears with "Removing..." (no cancel button).
6.   tian runs: git worktree remove <worktree-path>
7.   tian prunes empty parent directories.
8.   tian removes the Space from the SpaceCollection.
9.   Sidebar row disappears; capsule dismisses.
```

### 6.3 Cancel Path: User Cancels During Archive

```
Precondition: User is in step 8 of the happy path (an archive command
              is running).

1. User clicks the cancel button in the floating capsule (or presses
   Ctrl+C in any pane of the Space).
2. tian sends SIGTERM to the currently running shell command via
   the existing cancellationToken / KillGuard.
3. tian sets setupProgress.lastFailedIndex to the cancelled command's
   index.
4. tian skips all remaining archive commands.
5. tian does NOT run git worktree remove. Worktree on disk preserved.
6. Sidebar row shows the failure glyph for 3 seconds, then reverts to
   the Space's normal sidebar row.
7. Capsule shows the failure glyph for 3 seconds, then dismisses.
8. The Space remains open and active. The user can re-trigger close
   from the same Space's context menu.
```

### 6.4 Failure Path: Archive Command Returns Non-Zero Exit

```
Precondition: An archive command (e.g., npm run db:teardown) exits
              with a non-zero status.

1. runShellCommands reports the failure via setupProgress.lastFailedIndex.
2. tian halts the cleanup pipeline. Remaining archive commands skipped.
3. tian does NOT run git worktree remove. Worktree on disk preserved.
4. Sidebar row shows the failure glyph for 3 seconds, then reverts.
5. Capsule shows the failure glyph for 3 seconds, then dismisses.
6. Failure logged via Logger with branch name, worktree path,
   failed command, and exit code.
7. The Space remains open. The user can fix the archive script
   (or the underlying environment problem) and re-trigger close.
```

### 6.5 Failure Path: Uncommitted Changes Block git worktree remove

```
Precondition: All archive commands succeeded but git worktree remove
              fails with uncommitted-changes error.

1. Archive flow completes successfully (steps 1-10 of 6.1).
2. Capsule transitions to "Removing..." (per 6.1 step 11).
3. git worktree remove returns the existing
   WorktreeError.uncommittedChanges.
4. The progress capsule dismisses immediately (FR-053).
5. The existing WorktreeForceRemoveDialog appears with options:
   [Force Remove] [Cancel]
6. If user clicks Force Remove: git worktree remove --force runs,
   pruning runs, Space is removed, sidebar row disappears.
7. If user clicks Cancel: the worktree on disk is preserved, the
   Space remains open. (Note: archive commands have already run
   and may have torn down resources — this is an acknowledged
   trade-off, not a regression of existing behavior.)
```

### 6.6 Empty / Loading / Edge States

| State | Behavior |
|-------|----------|
| Space is not worktree-backed (`worktreePath == nil`) | This feature does not apply. Closing a non-worktree Space is unchanged — no progress UI. |
| Space is worktree-backed but `.tian/config.toml` is missing or has no `[[archive]]` | Skip archive commands. Show "Removing..." in sidebar row + capsule (FR-012, FR-022). |
| Same Space close triggered twice | Second trigger is a no-op (FR-060). The "Close Space" context menu item is hidden during archive (FR-060) — only capsule cancel and Ctrl+C are available. |
| Different Space close triggered while one is in flight | Second close is rejected with an inline error / non-zero CLI exit (FR-061). User retries after the first close finishes. |
| "Close Only" selected with archive commands configured | Secondary confirmation appears: "Skip teardown?" (FR-003). |
| App quit during archive | Graceful cancel; worktree preserved; Space restored on relaunch (FR-062). |
| Archive script hangs longer than `setup_timeout` | Command killed; failure path (FR-050) runs. |
| `git worktree remove` succeeds but pruning fails | Logged at warning level; no user-facing error (FR-054). |

### 6.7 Visual Specification (Reuse-Only)

This feature reuses the existing creation progress UI components (`SetupProgressCapsule`, `setupProgressRow()` in `SidebarSpaceRowView`) without visual changes. The only differences are the string labels:

- Step counter prefix: **"Cleanup"** instead of **"Setup"**
- No-command-list state: **"Removing..."** label

No new icons, colors, padding, or layout patterns are introduced. The `didFailRun` glyph, the spinner, the cancel button, and the linger duration all match creation byte-for-byte.

---

## 7. Design Considerations

### Reuse over Replication

The progress UI surface (sidebar row + floating capsule + cancel) is already implemented for creation. This feature is primarily a wiring exercise: the close pipeline must drive the same `setupProgress` state and the same view bindings that creation does. Differentiating creation vs close is a label concern only — the underlying model and views are agnostic to direction.

### Naming: "Cleanup" vs "Archive" vs "Teardown"

The user-visible label uses **"Cleanup"** rather than "Archive" because:
- "Archive" is the config key name (`[[archive]]`) and is jargon for the user.
- "Teardown" is also accurate but slightly more technical.
- "Cleanup" pairs naturally with "Setup" (the creation label), giving the user a symmetric mental model: Setup builds it, Cleanup tears it down.

Internal code may continue to use `archiveCommands` / `runArchiveCommands` etc. — this is a UI-string concern only.

### In-Pane Archive Execution: User's Live Pane vs. Blank Pane

A meaningful asymmetry exists between creation and close. In creation, the active pane is brand new — empty, purpose-built, no user state. In close, the active pane belongs to the user's existing work session and may contain a half-typed command, an active dev server, or a TUI application like nvim. Typing archive commands into this pane will interrupt whatever is in flight and inject commands into the user's shell history.

This is acceptable for v1 because the user has explicitly confirmed "Remove Worktree & Close" — at that moment they have signaled that the Space is being torn down and pane state is expendable. The alternative (running archive commands as headless subprocesses with output redirected to a hidden buffer or log) would lose the live-output debugging affordance that is the entire reason for showing progress in the first place. A user whose `npm run db:teardown` hangs needs to see the output to diagnose, not just a step counter.

If this trade-off proves painful in practice (e.g., users routinely lose nvim work to archive injection), v2 could add a secondary confirmation that says "Archive commands will run in the focused pane. Continue?" or auto-create a fresh pane for archive output. v1 ships without these.

### Why Halt on Archive Failure (vs Continue)

Archive commands often gate irreversible filesystem changes — e.g., a `docker compose down` should complete before the worktree directory is wiped. If `docker compose down` fails (e.g., a container is stuck), running `git worktree remove` anyway can leave orphaned containers, zombie processes, or open ports. Preserving the worktree on archive failure lets the user investigate and fix the root cause before retrying. This is the safer default; "force remove despite archive failure" is already accessible via the existing force-remove path if needed.

### Sequential Multi-Space Close

If the user multi-selects Spaces or closes the entire workspace, sequential execution avoids contention on shared resources (e.g., two archive scripts both calling `docker compose down` from different worktrees against the same compose project). Sequential is also simpler to reason about visually — only one capsule, one in-flight command at a time.

### Always Show "Removing..." (Even Without Archive Commands)

The user explicitly asked for this. The reason is consistency: every "Remove Worktree & Close" action shows visible feedback. Without it, fast removals (no archive commands, small worktree) would feel like the menu item silently did nothing for a half-second before the row disappeared, which can be ambiguous when the user is also navigating tabs/spaces and may not look at the sidebar at the exact moment of removal.

### Cancel Button Lifecycle

Cancel is offered during archive but **not** during `git worktree remove` itself. Once tian commits to the irreversible filesystem operation, partial cancellation would leave inconsistent state (worktree partially removed, refs partially cleaned up). This matches the creation flow's behavior where cancel skips remaining setup but the Space is already created and is not rolled back.

### Sidebar Row Re-Use

The `setupProgressRow()` helper in `SidebarSpaceRowView` is used as-is. The function reads the `setupProgress` value attached to the Space and renders the mini progress + label + failure glyph. The label string ("Setup" vs "Cleanup" vs "Removing...") must come from the orchestrator (passed into the progress model, or derived from a phase enum), not be hardcoded into the view. This is the only change to existing rendering code.

### Existing IPC Surface

No new IPC commands are introduced. The existing `worktree.remove` IPC command (per FR-021 of the Worktree Spaces PRD) drives the close progress UI identically whether triggered from CLI or GUI. The CLI's response semantics are unchanged — it still returns success/failure once the close pipeline terminates.

---

## 8. Out of Scope

- **Selectively skipping individual archive commands.** v1 runs all archive commands or none (via cancel).
- **Re-ordering archive commands at runtime.** Order is fixed by the config file.
- **Sequential queueing of concurrent close requests.** v1 rejects a second close while one is in-flight (FR-061). Queueing pending closes is deferred until usage shows it is needed.
- **Per-pane archive routing.** Archive runs in the focused pane only — there is no support for distributing archive steps across multiple panes.
- **Archive progress for non-worktree Space close.** Regular Spaces (no `worktreePath`) close instantly with no progress UI; this feature is worktree-specific.
- **Multi-window aggregate progress.** If the user has two workspace windows and triggers close on one Space in each, each window shows its own capsule independently. There is no cross-window aggregation.
- **Archive command output capture for post-mortem.** Output is visible only in the live pane. No separate log file is written for archive output beyond what the existing tian log captures.
- **Retrying a failed archive command in place.** The user must re-trigger close from the menu — there is no "retry" button on the failure glyph.
- **Confirmation dialog redesign.** The existing `WorktreeCloseDialog` (NSAlert with 3 buttons) is unchanged.
- **Customizing the "Cleanup" label.** v1 hardcodes the user-facing label; no localization or override.
- **Force-skipping archive on close.** v1 has no equivalent of `--no-archive` for the close path. To skip archive, the user can either use "Close Only" (which leaves the worktree on disk) or remove the `[[archive]]` section from the config.

---

## 9. Success Metrics

Since tian is a personal tool (single developer, no telemetry), success is measured qualitatively:

- **Primary:** The developer routinely defines `[[archive]]` commands in `.tian/config.toml` because the close progress UI makes them safe and visible. Spaces with archive commands close as confidently as they were created.
- **Friction test:** From the moment the user clicks "Remove Worktree & Close", the sidebar progress row + capsule appear within 100ms. Step transitions are visible without lag.
- **Cancel reliability:** Pressing the cancel button or Ctrl+C halts the in-flight archive command within 1 second. The worktree on disk is preserved every time cancel is invoked.
- **Failure visibility:** If an archive command fails, the failure glyph appears on both the sidebar row and the capsule. The user can immediately read the error output in the pane.
- **No regressions:** The fast path (no archive commands) does not feel slower than today. The "Removing..." flash is visible but does not exceed ~1 second on a typical worktree.
- **Consistency:** The close progress UI is visually indistinguishable (other than labels) from the creation progress UI. No new components were introduced.

---

## 10. Open Questions

None known.

The following decisions were resolved during clarification:
- ~~OQ#1~~ Space stays visible during archive (mirror creation). Archive output streams in the active pane.
- ~~OQ#2~~ Archive failure / cancel halts the pipeline; worktree is preserved; Space stays open.
- ~~OQ#3~~ "Removing..." progress shows even when no archive commands are configured.

---

## 11. Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-04-29 | psycoder | Initial draft. Mirrors the worktree creation progress UI for the close/remove flow. Reuses `SetupProgress`, `SetupProgressCapsule`, and `SidebarSpaceRowView.setupProgressRow()`. Halts pipeline on archive failure / cancel; preserves worktree. Always renders "Removing..." even with no archive commands. |
| 1.1 | 2026-04-29 | psycoder | Post-review revision. **Spec accuracy:** added section 4.1.1 (FR-004 through FR-007) listing the required code changes — phase enum on `SetupProgress`, phase-driven labels on the capsule and sidebar row, conditional cancel button, and removal of the `label == "setup"` guard in `runShellCommands`. Softened NFR-003 to acknowledge these are part of the feature, not separate work. **FR-003 added:** "Close Only" with `[[archive]]` configured triggers secondary confirmation. **FR-014 revised:** sidebar/capsule linger synchronized via `displayedProgress` pattern. **FR-031 revised:** clarified focused-pane assumption with explicit fallback. **FR-053 revised:** synchronous `setupProgress = nil` before modal alert appears. **FR-060 revised:** documented that `SidebarSpaceRowMutationGate` hides the close menu during archive. **FR-061 revised:** explicit `isCloseInFlight` guard rejects concurrent closes (no queue). **FR-062 revised:** specified `windowShouldClose` + `cancelCommands` hook with fire-and-forget SIGTERM. Added Design Consideration on in-pane archive execution trade-offs. Added "sequential queueing" to Out of Scope. Updated edge-states table and fixed off-by-one in flow 6.1 step 9. |
