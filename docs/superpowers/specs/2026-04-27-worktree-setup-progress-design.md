# Worktree setup progress — design

**Date:** 2026-04-27
**Branch:** `enhancement/setup`
**Status:** Design approved, awaiting written-spec review

## Problem

When `[[setup]]` commands from `.tian/config.toml` run during worktree-Space creation, the user gets almost no feedback:

1. **No progress visibility.** The only signals are a tiny `ProgressView()` spinner in the sidebar workspace header and a `SetupCancelButton` capsule in the bottom-right. Neither indicates which command is running, how far along we are, or whether anything has failed. All command output goes to `tian.log` only.
2. **Cross-workspace spinner bug.** `WorktreeOrchestrator.isCreating: Bool` is window-scoped, but the sidebar passes it to *every* workspace header in that window. Creating a worktree in workspace A makes workspaces B, C, … all show the spinner.
3. **App-wide lag during setup.** `runShellCommand` runs on the main actor: `Process.run()`, `readDataToEndOfFile()` on both pipes, and the orchestrator's `@MainActor` annotation all conspire to block the UI thread. Worse, pipes have a ~16-64 KB OS buffer; commands like `bun install` overflow it, the child process blocks on write, and `terminationHandler` never fires until the timeout task kills the process.

## Goal

Give the user a per-Space, per-workspace progress indicator while setup runs (counter + current command), and remove the lag by moving shell-command execution off the main thread. Reassurance, not debuggability — output stays in logs.

## Non-goals

- Streaming stdout/stderr to the UI.
- Halting setup on first failure (current "log warning, continue" semantics are intentional).
- A progress notifier for the `[[archive]]` flow (worktree removal). Different lifecycle, different surfaces; can be added later.
- Cleaning up the same blocking-pipe pattern in `GitStatusService`, `BranchListService`, `WorktreeService`. Those run short bounded-output git commands; they don't deadlock or noticeably stall main.
- Changing the shell flags used for setup commands (`-l -c …`). Out of scope and risky.

## Section 1: Model

Replace `WorktreeOrchestrator.isCreating: Bool` with a structured value:

```swift
struct SetupProgress: Equatable {
    let workspaceID: UUID         // workspace that owns the new Space
    let spaceID: UUID             // the Space being set up
    let totalCommands: Int        // count of [[setup]] commands
    var currentIndex: Int         // 0-based; -1 before first command starts
    var currentCommand: String?   // the command string currently running
    var lastFailedIndex: Int?     // most recent non-zero exit, if any
}

var setupProgress: SetupProgress?  // nil ⇔ no setup in flight
```

Lifecycle:

- Initialised to `SetupProgress(currentIndex: -1, currentCommand: nil, lastFailedIndex: nil, …)` *after* the new `SpaceModel` exists, immediately before `runShellCommands(label: "setup", …)`.
- Before each command: `currentIndex` advances and `currentCommand` is set to the command string.
- After each command: if `terminationStatus != 0`, `lastFailedIndex = currentIndex`.
- Cleared to `nil` when the loop exits (success, all-failed, or cancelled). Layout application (Step 13 of the existing creation flow) happens *after* `setupProgress` clears and is not part of the setup-progress lifecycle.
- The `[[archive]]` flow does **not** populate `setupProgress`.

Concurrency:

- One in-flight setup per orchestrator (matches today's behaviour). The orchestrator is per-window, so two windows can each be running their own setup independently.
- `CreateSpaceView` and IPC entry points already serialize through `createWorktreeSpace`. No additional guarding is required for the model.

Failure behaviour:

- Keep "log warning, continue with next command" semantics.
- `lastFailedIndex` enables a small `✗` glyph in the UI after the failed step number.
- No alert, no halt.

## Section 2: UI placement

The two surfaces that show progress are scoped explicitly:

### A. Sidebar Space row

While `setupProgress?.spaceID == space.id`, the Space's row in the sidebar renders a setup-progress style instead of the normal Space row:

```
⏳  feature/foo  ·  3/8  bun install
```

- Single line, no extra row height.
- Step counter (`currentIndex + 1`/`totalCommands`) and the current command, truncated with ellipsis if it exceeds row width.
- If `lastFailedIndex == currentIndex` (the step that just completed failed), a `✗` glyph follows the step counter.
- The row is non-interactive while in progress: no rename, no drag, no disclosure menu, no context menu actions that would alter the Space. It stays selectable so the user can focus the Space's terminal.
- When `setupProgress` clears, the row reverts to its normal rendering immediately.

### B. Bottom-right capsule (`SetupProgressCapsule`)

Replaces the current `SetupCancelButton` view. Same overlay position as today (bottom-right of `WorkspaceWindowContent`).

```
[ Setup 3/8 · bun install        ✕ ]
```

- Visible iff `worktreeOrchestrator.setupProgress != nil` for the window's orchestrator.
- Same counter / command label / failure glyph as the sidebar row.
- Embeds the existing cancel action (`worktreeOrchestrator.cancelCommands()`).
- Hides as soon as `setupProgress` is `nil`. Brief 3 s fade-out if `lastFailedIndex` is non-nil at the moment it clears, then disappears.

### Removals

- `ProgressView()` block in `SidebarWorkspaceHeaderView` and its `isCreatingWorktree: Bool` parameter.
- `isCreatingWorktree:` argument propagated through `SidebarExpandedContentView` to the workspace header.
- `SetupCancelButton.swift` view (replaced by `SetupProgressCapsule`).

## Section 3: Performance / actor isolation

Three changes to the shell-command execution path in `WorktreeOrchestrator`:

### 3.1 Move execution off the main actor

Extract the per-command logic into a `nonisolated` helper — either a private nonisolated function on the orchestrator or a small `SetupCommandRunner` helper type. The helper owns the `Process`, the two `Pipe`s, and the timeout task. The main actor must never block on I/O during command execution.

Between commands, the runner hops back via `await MainActor.run { … }` to update `setupProgress` (advance index, set current command, record failure). These hops are narrow — mutating the struct, nothing else.

### 3.2 Incremental pipe drain

Replace `readDataToEndOfFile()` with `readabilityHandler` callbacks on each pipe's `fileHandleForReading`. Each handler appends drained bytes to an in-memory `Data` buffer.

- Per-stream cap of **256 KB**. Once exceeded, further reads are discarded and a `… (truncated)` sentinel is appended.
- Handlers are nilled on process termination to release the pipes.
- Final logging of stdout/stderr happens after the runner observes the termination handler and reads out the accumulated buffers.

Eliminates pipe-full deadlock for chatty commands.

### 3.3 Cancellation handle

Replace the orchestrator's stored `currentCommandProcess: Process?` with a small `SetupCommandHandle` value the runner publishes back to the main actor while the command runs:

```swift
private struct SetupCommandHandle {
    let process: Process
}

@MainActor private var cancellableHandle: SetupCommandHandle?
```

`cancelCommands()` reads `cancellableHandle?.process.terminate()`. Set just before `process.run()`, cleared on the runner's termination path. The orchestrator continues to drive `commandsCancelled` for the loop-level early-exit check.

### 3.4 What does *not* change

- `installCtrlCMonitor` / `removeCtrlCMonitor` — unchanged. Local `NSEvent` monitor on the key window for Ctrl+C.
- Shell invocation: `[shellPath, "-l", "-c", command]` with the worktree as cwd. Unchanged.
- `WorktreeService.copyFiles`, `ensureGitignore`, `createWorktree`, etc. — unchanged.
- Layout application (`applyLayout`) — unchanged.

## Section 4: Failure handling

- Continue past failures (current behaviour).
- Set `lastFailedIndex = currentIndex` on non-zero exit.
- UI: `✗` glyph after the step counter on the sidebar row and the capsule.
- If `lastFailedIndex` is non-nil at the moment `setupProgress` clears, the capsule lingers ~3 s before disappearing so the failure indication is observable. Sidebar row reverts immediately.
- All command stdout/stderr/exit codes log to `tian.log` via the existing `Log.worktree` channel. Unchanged.
- No alerts, no modal failure surface.

## Section 5: Testing

Tests live in `tianTests/`. The harness already exercises `WorktreeOrchestrator` end-to-end via `WorktreeOrchestratorTests`.

### 5.1 Model lifecycle

Add cases observing `setupProgress` transitions on a configurable test config with a small `[[setup]]` (e.g. three `echo` commands):

- `setupProgress` is `nil` before creation.
- Becomes non-nil after the Space exists and before the first command runs.
- `currentIndex` advances per command; `currentCommand` matches.
- Returns to `nil` after the last command exits.
- Carries the correct `workspaceID` and `spaceID`.

### 5.2 Failure surfacing

Setup config containing one passing and one failing command (e.g. `false`). Assert:

- The loop completes both commands.
- `setupProgress.lastFailedIndex` reflects the failed index at the moment immediately before the loop ends.
- Final state is `nil` after completion (capsule fade-out is UI-only and not asserted in model tests).

### 5.3 Pipe-overflow no-deadlock

Setup config with a single command that emits more than the 256 KB cap (e.g. `yes | head -c 300000`). Assert:

- The command exits within a generous bound (well below the timeout).
- The orchestrator does not block; subsequent assertions can proceed promptly after `await`.
- The accumulated stdout buffer logged to `tian.log` ends with the truncation sentinel.

### 5.4 Cancellation mid-command

Setup config with a long-sleeping command (e.g. `sleep 30`). Trigger `cancelCommands()` once `setupProgress.currentCommand` becomes non-nil. Assert:

- The Process is terminated promptly.
- `setupProgress` clears.
- `commandsCancelled` is `true`.

### 5.5 View-level

A focused view test (or snapshot test if the harness already supports them) verifies:

- `SidebarWorkspaceHeaderView` renders without a spinner regardless of orchestrator state.
- The target Space row renders setup progress only when its `spaceID` matches `setupProgress?.spaceID`.
- Other workspaces' rows in the same window are unaffected.
- `SetupProgressCapsule` is present iff `setupProgress != nil` on the window's orchestrator.

## Out of scope (recap)

- Streaming command output to the UI.
- Halt-on-failure or alert-on-failure UX.
- `[[archive]]` flow notifier.
- Generalising the off-main pipe pattern across `GitStatusService`, `BranchListService`, `WorktreeService`.
- Changes to shell flags or environment.

## Files affected (anticipated)

- `tian/Worktree/WorktreeOrchestrator.swift` — model change, runner extraction, isolation changes.
- `tian/View/Worktree/SetupCancelButton.swift` — replaced by `SetupProgressCapsule.swift`.
- `tian/View/Workspace/WorkspaceWindowContent.swift` — capsule wiring, animation key updates.
- `tian/View/Sidebar/SidebarExpandedContentView.swift` — drop `isCreatingWorktree` propagation.
- `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift` — drop spinner and parameter.
- `tian/View/Sidebar/SidebarSpaceRowView.swift` — render setup-progress style when `setupProgress?.spaceID == space.id`.
- `tianTests/WorktreeOrchestratorTests.swift` — new cases for the lifecycle, failure, overflow, cancel scenarios.
- New view test or snapshot file for the capsule + sidebar row, location matching project convention.

`xcodegen generate` is required after adding/removing files. New files: `SetupProgressCapsule.swift` (and possibly `SetupCommandRunner.swift` if extracted to its own file).
