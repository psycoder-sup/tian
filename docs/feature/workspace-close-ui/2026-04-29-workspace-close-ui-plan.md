# Plan: Worktree Space Close Progress UI

**Date:** 2026-04-29
**Status:** Approved
**Based on:** docs/feature/workspace-close-ui/workspace-close-ui-prd.md

---

## 1. Approach

The PRD's central insight is that the close progress surface is the same UI that creation already uses — `SetupProgress` (model), `SetupProgressCapsule` (bottom-right view), `setupProgressRow()` (sidebar mini view), and `WorkspaceWindowContent.displayedProgress` (linger driver). The PRD also confirmed that this is *not* pure reuse: each of those four call sites has a hardcoded "Setup" assumption that must be parameterized by a `phase` enum on `SetupProgress`. That enum (`setup` | `cleanup` | `removing`) becomes the single source of truth for the user-visible label prefix.

The orchestrator's existing `removeWorktreeSpace` already runs `[[archive]]` commands via the same `runShellCommands` helper as `[[setup]]`, but a guard at line 347 (`label == "setup"`) silently throws away progress updates for archive. Lifting that guard is the *single change* that wires the archive flow into the existing UI plumbing — once the orchestrator initializes `setupProgress` with `phase = .cleanup` before the archive loop and clears it after, every UI surface picks up the change for free. The `phase = .removing` "no archive commands" state is a brief snapshot the orchestrator publishes around `git worktree remove` + pruning so the user always sees confirmation.

Concurrency is handled by an explicit `isCloseInFlight: Bool` flag on the orchestrator (set at the top of `removeWorktreeSpace`, cleared in `defer`). Concurrent close requests for *different* Spaces are rejected with a new `WorktreeError.closeInFlight` (CLI returns non-zero, GUI surfaces via the existing `presentError` path). Concurrent requests for the *same* Space are no-ops via the existing `SidebarSpaceRowMutationGate` which already hides the close menu when `setupProgress != nil`. No queue is introduced.

The "Close Only" footgun fix (FR-003) is implemented as a new `SkipTeardownConfirmationDialog` (parallel to the existing `WorktreeForceRemoveDialog` pattern), invoked from `SidebarExpandedContentView.closeSpace` only when the Space's repo has a non-empty `[[archive]]` section. The window-close hook (FR-062) is a single-line addition to `WorkspaceWindowController.windowShouldClose` calling `worktreeOrchestrator.cancelCommands()` — fire-and-forget so the window-close is not blocked.

Failure semantics: archive failure (any non-zero exit) and user cancel both halt the pipeline before `git worktree remove`. Currently `runShellCommands` continues past failures; this plan adds an early break when the orchestrator detects `lastFailedIndex != nil` *or* `commandsCancelled` and `removeWorktreeSpace` returns early without calling `removeWorktree`. The 3-second linger is preserved (the existing `displayedProgress.didFailRun` path in `WorkspaceWindowContent` already does the right thing for the capsule; the sidebar reverts immediately, which the PRD's revised FR-014 explicitly accepts).

---

## 2. File-by-file Changes

| File | Change | Notes |
|------|--------|-------|
| `tian/Worktree/SetupProgress.swift` | modify | Add `phase: Phase` field with enum cases `setup`, `cleanup`, `removing`. Add `removingPlaceholder(workspaceID:spaceID:)` static factory for the no-archive case. Update `starting(...)` to take `phase`. Add `labelPrefix: String` computed property. |
| `tian/View/Worktree/SetupProgressCapsule.swift` | modify | Replace hardcoded `"Setup \(stepText)"` with phase-driven rendering: `setup` → "Setup n/N + cmd"; `cleanup` → "Cleanup n/N + cmd"; `removing` → "Removing..." with no step counter, no command label, no cancel button. Hide the cancel button when `phase == .removing`. |
| `tian/View/Sidebar/SidebarSpaceRowView.swift` | modify | Replace bare `Text(progress.stepText)` in `setupProgressRow` with phase-driven rendering. For `.removing`, suppress step counter and command label, show only `progress.labelPrefix`. |
| `tian/Worktree/WorktreeOrchestrator.swift` | modify | (1) Add `isCloseInFlight: Bool` property. (2) Guard top of `removeWorktreeSpace` with `isCloseInFlight` check, throw `WorktreeError.closeInFlight` if true; set/defer-clear in correct order. (3) In `removeWorktreeSpace`: initialize `setupProgress = .starting(... phase: .cleanup, totalCommands: archiveCommands.count)` before the archive loop when archive is non-empty. After loop, transition to `.removingPlaceholder(...)` for `git worktree remove` + pruning. Set `setupProgress = nil` synchronously in a `defer` covering all exit paths AND immediately before throwing `WorktreeError.uncommittedChanges` so the capsule dismisses before the modal alert. (4) In `runShellCommands`: lift the `label == "setup"` guard so progress updates for any non-nil `setupProgress`. (5) Detect failure/cancellation after the loop and return early (skip `git worktree remove`) when `commandsCancelled || setupProgress?.didFailRun == true`. Update `setupProgress.lastFailedIndex` accordingly so the failure glyph fires. |
| `tian/Worktree/WorktreeError.swift` | modify | Add `closeInFlight` case with description: *"Another worktree close is in progress. Try again in a moment."* |
| `tian/View/Worktree/SkipTeardownConfirmationDialog.swift` | new | Parallel to `WorktreeForceRemoveDialog`. Two-button `NSAlert` ("Skip Teardown" destructive + "Cancel"). Invoked when user picks "Close Only" and archive commands are configured. |
| `tian/View/Sidebar/SidebarExpandedContentView.swift` | modify | (1) `closeSpace`: when response is `.closeOnly`, query archive-command count via `WorktreeService.archiveCommandCount(repoRoot:)` (new helper, see below). If > 0, show `SkipTeardownConfirmationDialog` before removing Space; otherwise proceed as today. (2) Surface `WorktreeError.closeInFlight` via `worktreeOrchestrator.presentError(error)` (no behavioral change — the existing `lastError` alert already handles this once the case is added). |
| `tian/Worktree/WorktreeService.swift` | modify | Add `archiveCommandCount(repoRoot:)` static helper that parses `.tian/config.toml` and returns `archiveCommands.count` (or 0 if no config / parse failure). Used by `SidebarExpandedContentView` for the FR-003 conditional. |
| `tian/WindowManagement/WorkspaceWindowController.swift` | modify | In `windowShouldClose`, call `worktreeOrchestrator.cancelCommands()` before the existing workspace-cleanup loop. Fire-and-forget — do not await; do not delay window close. |
| `tian-cli/CommandRouter.swift` | modify | When the `worktree.remove` IPC response includes the new `closeInFlight` failure code, surface a clear stderr message (no behavior change beyond message text). |
| `tian/Core/IPCCommandHandler.swift` | modify | In `handleWorktreeRemove`, map `WorktreeError.closeInFlight` to a distinct failure code (e.g., `code: 4`) so the CLI can detect it. |
| `tianTests/WorktreeOrchestratorTests.swift` | modify | Add tests for: archive progress publishes phase=.cleanup snapshots; archive failure halts pipeline and preserves worktree; user cancel during archive preserves worktree; no-archive case publishes phase=.removing briefly; `isCloseInFlight` rejects concurrent close on a different Space; `setupProgress` is nil when `WorktreeError.uncommittedChanges` is thrown. |
| `tianTests/SetupProgressTests.swift` | new (small) | Unit tests for `Phase` enum, `labelPrefix` computed property, and the `removingPlaceholder` factory. |

Files explicitly **not** changed:
- `tian/Worktree/WorktreeConfig.swift` / `WorktreeConfigParser.swift` — `archiveCommands` already parsed, no schema change.
- `tian/View/Workspace/WorkspaceWindowContent.swift` — the existing `displayedProgress` linger logic and `SetupProgressCapsule` invocation pick up the phase change without modification (the capsule reads `progress.phase` directly).
- `tian/View/Worktree/WorktreeCloseDialog.swift` — the existing 3-button dialog is unchanged. The "Close Only" secondary confirmation is a separate dialog.

---

## 3. Types & Interfaces

```swift
// File: tian/Worktree/SetupProgress.swift

import Foundation

struct SetupProgress: Equatable, Sendable {

    /// Which lifecycle stage owns this progress snapshot. Drives the
    /// user-visible label prefix on both the sidebar row and the capsule.
    enum Phase: Equatable, Sendable {
        /// Active during `[[setup]]` command execution at create time.
        case setup
        /// Active during `[[archive]]` command execution at close time.
        case cleanup
        /// Active during `git worktree remove` + directory pruning.
        /// No step counter, no current command, no cancel affordance.
        case removing
    }

    let workspaceID: UUID
    let spaceID: UUID
    let phase: Phase
    let totalCommands: Int
    /// 0-based index of the currently executing command. `-1` before the
    /// first command starts. Always `-1` when `phase == .removing`.
    var currentIndex: Int
    /// The command string currently running, or `nil` before the first
    /// command starts. Always `nil` when `phase == .removing`.
    var currentCommand: String?
    /// Index of the most recent command that exited non-zero, if any.
    var lastFailedIndex: Int?

    static func starting(
        workspaceID: UUID,
        spaceID: UUID,
        phase: Phase,
        totalCommands: Int
    ) -> SetupProgress {
        SetupProgress(
            workspaceID: workspaceID,
            spaceID: spaceID,
            phase: phase,
            totalCommands: totalCommands,
            currentIndex: -1,
            currentCommand: nil,
            lastFailedIndex: nil
        )
    }

    /// Snapshot for the brief "Removing..." state (no archive commands or
    /// post-archive `git worktree remove` window). `totalCommands` is `0`
    /// and `stepText` is unused — UI gates on `phase == .removing`.
    static func removingPlaceholder(
        workspaceID: UUID,
        spaceID: UUID
    ) -> SetupProgress {
        SetupProgress(
            workspaceID: workspaceID,
            spaceID: spaceID,
            phase: .removing,
            totalCommands: 0,
            currentIndex: -1,
            currentCommand: nil,
            lastFailedIndex: nil
        )
    }

    // MARK: - UI helpers

    var stepText: String {
        let displayed = max(currentIndex + 1, 1)
        return "\(displayed)/\(totalCommands)"
    }

    var commandLabel: String {
        currentCommand ?? "starting…"
    }

    var didFailRun: Bool {
        lastFailedIndex != nil
    }

    /// User-visible prefix on the sidebar row and capsule.
    /// "Setup", "Cleanup", or "Removing...".
    var labelPrefix: String {
        switch phase {
        case .setup:    return "Setup"
        case .cleanup:  return "Cleanup"
        case .removing: return "Removing..."
        }
    }
}
```

```swift
// File: tian/Worktree/WorktreeError.swift  (additive case only)

enum WorktreeError: Error, CustomStringConvertible {
    // ... existing cases ...
    case closeInFlight

    var description: String {
        switch self {
        // ... existing cases ...
        case .closeInFlight:
            return "Another worktree close is in progress. Try again in a moment."
        }
    }
}
```

```swift
// File: tian/Worktree/WorktreeOrchestrator.swift  (additive shape only)

@MainActor @Observable
final class WorktreeOrchestrator {
    // ... existing properties ...

    /// True while a `removeWorktreeSpace` invocation is between its first
    /// line and its final cleanup. Concurrent removal of a *different*
    /// Space is rejected with `WorktreeError.closeInFlight`. Concurrent
    /// removal of the *same* Space is filtered out at the UI layer by
    /// `SidebarSpaceRowMutationGate` (which hides "Close Space" while
    /// `setupProgress != nil`).
    private(set) var isCloseInFlight: Bool = false

    func removeWorktreeSpace(
        spaceID: UUID,
        force: Bool = false,
        workspaceID: UUID? = nil
    ) async throws {
        if isCloseInFlight {
            throw WorktreeError.closeInFlight
        }
        isCloseInFlight = true
        defer {
            isCloseInFlight = false
            setupProgress = nil   // synchronous nil-out covers ALL exit paths
        }
        // ... existing body, with progress wiring described in §1 ...
    }
}
```

```swift
// File: tian/View/Worktree/SetupProgressCapsule.swift  (label rendering shape)

struct SetupProgressCapsule: View {
    let progress: SetupProgress
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)

            // Phase-driven label
            switch progress.phase {
            case .setup, .cleanup:
                Text("\(progress.labelPrefix) \(progress.stepText)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if progress.didFailRun { failureGlyph }
                Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(progress.commandLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 320, alignment: .leading)
                cancelButton
            case .removing:
                Text(progress.labelPrefix)   // "Removing..."
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                // No step counter, no command label, no cancel button.
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    @ViewBuilder private var failureGlyph: some View {
        Image(systemName: "xmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.red)
            .accessibilityLabel("a step in this run failed")
    }

    @ViewBuilder private var cancelButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel \(progress.labelPrefix.lowercased())")
    }
}
```

```swift
// File: tian/View/Worktree/SkipTeardownConfirmationDialog.swift  (new)

import AppKit

@MainActor
enum SkipTeardownConfirmationDialog {

    enum Response { case skipTeardown, cancel }

    static func show(
        on window: NSWindow,
        archiveCommandCount: Int,
        completion: @escaping (Response) -> Void
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Skip teardown?"
        alert.informativeText = """
        This space has \(archiveCommandCount) archive command\
        \(archiveCommandCount == 1 ? "" : "s") configured \
        in .tian/config.toml that will not run if you close \
        without removing the worktree.
        """
        alert.addButton(withTitle: "Skip Teardown")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true

        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: completion(.skipTeardown)
            default:                       completion(.cancel)
            }
        }
    }
}
```

---

## 4. Test Plan

All tests live in `tianTests/` (Swift Testing framework, `@MainActor`-annotated, using existing `MockWorkspaceProvider` and `makeTempGitRepo` helpers).

- **FR-004** (task 1): `SetupProgress.Phase enum and labelPrefix render correct strings` — unit test in `tianTests/SetupProgressTests.swift`.
- **FR-004** (task 1): `removingPlaceholder factory produces phase=.removing with totalCommands=0` — unit test.
- **FR-005, FR-022** (task 2): manual capsule render verification in DEBUG preview (no automated SwiftUI snapshot test infra exists in this project; visual regression deferred).
- **FR-006** (task 3): same — sidebar render verified manually via DEBUG preview.
- **FR-007, FR-010, FR-011** (task 4): `archive flow publishes phase=.cleanup snapshots with correct stepText` — integration test in `WorktreeOrchestratorTests.swift` using a temp repo with a config file containing 2 archive commands. Asserts that during `removeWorktreeSpace`, `setupProgress` transitions to `.cleanup` with `currentIndex` advancing 0→1.
- **FR-040, FR-041, FR-050** (task 4): `archive failure halts pipeline and preserves worktree` — integration test. Config has an archive command that exits 1 (e.g., `false`). Asserts: (a) `setupProgress.lastFailedIndex` is set, (b) the worktree directory still exists on disk after `removeWorktreeSpace` returns, (c) the Space is NOT removed from the SpaceCollection, (d) `setupProgress` is nil after the call returns.
- **FR-040, FR-041** (task 4): `user cancel during archive preserves worktree` — integration test. Config has an archive command that sleeps 5s (e.g., `sleep 5`). Test calls `cancelCommands()` mid-flight. Asserts the worktree directory exists and the Space is preserved.
- **FR-012, FR-022** (task 4): `no-archive removeWorktreeSpace publishes phase=.removing briefly` — integration test. Config has empty archive section. Asserts `setupProgress.phase == .removing` is observed at some point during the call (via @Observable change tracking), and `setupProgress` is nil after the call returns.
- **FR-061** (task 5): `concurrent removeWorktreeSpace on different Space is rejected with closeInFlight` — integration test. Spawns Space A and Space B both worktree-backed. First `removeWorktreeSpace(spaceID: A)` task is launched (with a slow archive command). While it is running, second `removeWorktreeSpace(spaceID: B)` is awaited. Asserts the second call throws `WorktreeError.closeInFlight`.
- **FR-053** (task 4): `setupProgress is nil when WorktreeError.uncommittedChanges is thrown` — integration test. Worktree has uncommitted changes; archive succeeds; `git worktree remove` fails. Asserts `setupProgress` is nil when the error is observed by the caller.
- **FR-003** (task 6): `closeSpace shows skip-teardown dialog when archive commands exist and user picks Close Only` — manual smoke test via UI (no NSAlert mocking infra). Documented as a step-by-step QA checklist in §6.
- **FR-062** (task 7): `windowShouldClose calls cancelCommands` — assertion-style test injects a mock orchestrator and verifies `cancelCommands()` is called when `windowShouldClose` fires. Done as a small unit test on the controller; if the controller is hard to mock, this test is replaced by a manual QA step.

Skeleton for the central archive-progress test:

```swift
// FR-007, FR-010, FR-011:
@Test func archiveFlowPublishesCleanupPhase() async throws {
    let repoRoot = try makeTempGitRepo()
    defer { cleanup(repoRoot) }
    try writeConfig(at: repoRoot, archiveCommands: ["echo one", "echo two"])

    let provider = MockWorkspaceProvider()
    let workspace = makeWorkspace(into: provider, repoRoot: repoRoot)
    let orch = WorktreeOrchestrator(workspaceProvider: provider)

    let result = try await orch.createWorktreeSpace(branchName: "test-cleanup", repoPath: repoRoot)

    var observed: [SetupProgress.Phase] = []
    let cancel = withObservationTracking {
        if let p = orch.setupProgress { observed.append(p.phase) }
    } onChange: { /* re-track */ }

    try await orch.removeWorktreeSpace(spaceID: result.spaceID)

    #expect(observed.contains(.cleanup))
    #expect(orch.setupProgress == nil)
}
```

---

## 5. Tasks

Tasks are dependency-ordered. Each is tagged with the model tier `/execute-task` should start with.

1. **[model: haiku]** Extend `SetupProgress` with `Phase` enum and `labelPrefix`
   - Files: `tian/Worktree/SetupProgress.swift`, `tianTests/SetupProgressTests.swift` (new)
   - Depends on: —
   - Done when: `Phase` enum compiles, `starting(...)` requires `phase` parameter, `removingPlaceholder` factory exists, `labelPrefix` returns "Setup" / "Cleanup" / "Removing..." correctly. Unit tests pass. Existing creation flow callsite (`continueCreation`) still compiles after passing `phase: .setup` to the factory.

2. **[model: sonnet]** Phase-driven rendering in `SetupProgressCapsule`
   - Files: `tian/View/Worktree/SetupProgressCapsule.swift`
   - Depends on: 1
   - Done when: capsule renders `Setup n/N + cmd` for `.setup`, `Cleanup n/N + cmd` for `.cleanup`, bare `Removing...` (no counter, no command, no cancel button) for `.removing`. Manually verified in DEBUG preview.

3. **[model: haiku]** Phase-driven prefix in sidebar row
   - Files: `tian/View/Sidebar/SidebarSpaceRowView.swift`
   - Depends on: 1
   - Done when: `setupProgressRow` displays `progress.labelPrefix + " " + stepText` for `.setup`/`.cleanup` and just `progress.labelPrefix` (no step text, no command label) for `.removing`.

4. **[model: opus]** Wire archive progress + failure halt + nil-out timing in orchestrator
   - Files: `tian/Worktree/WorktreeOrchestrator.swift`, `tian/Worktree/WorktreeError.swift`
   - Depends on: 1
   - Done when: (a) `runShellCommands` updates `setupProgress` for any non-nil value (label guard removed). (b) `removeWorktreeSpace` initializes `setupProgress` with `.cleanup` before archive runs (when archive non-empty), transitions to `.removingPlaceholder` for `git worktree remove` + pruning, and nils it synchronously in a `defer`. (c) Archive failure (non-zero exit) and user cancel both halt before `git worktree remove` and preserve the worktree on disk. (d) `setupProgress = nil` is set synchronously immediately before `WorktreeError.uncommittedChanges` is thrown so the modal alert appears without capsule overlap. (e) New `WorktreeError.closeInFlight` case added with description. All FR-007, FR-010-013, FR-040-041, FR-050-053 integration tests pass.

5. **[model: sonnet]** In-flight guard for concurrent close
   - Files: `tian/Worktree/WorktreeOrchestrator.swift`, `tian/Core/IPCCommandHandler.swift`, `tian-cli/CommandRouter.swift`
   - Depends on: 4
   - Done when: `isCloseInFlight` flag set/cleared correctly. Concurrent `removeWorktreeSpace` for a different Space throws `WorktreeError.closeInFlight`. IPC handler returns distinct failure code (4). CLI surfaces clear error message. FR-061 test passes.

6. **[model: sonnet]** "Close Only" footgun confirmation
   - Files: `tian/View/Worktree/SkipTeardownConfirmationDialog.swift` (new), `tian/View/Sidebar/SidebarExpandedContentView.swift`, `tian/Worktree/WorktreeService.swift`
   - Depends on: 4
   - Done when: `WorktreeService.archiveCommandCount(repoRoot:)` static helper returns the correct count (or 0 on missing/invalid config). `closeSpace` in `SidebarExpandedContentView` invokes `SkipTeardownConfirmationDialog` when response is `.closeOnly` AND archiveCommandCount > 0. Picking "Skip Teardown" closes the Space without removing the worktree (today's behavior). Picking "Cancel" leaves the Space open. Manual QA confirms: with `[[archive]]` configured, "Close Only" → secondary prompt; without `[[archive]]`, "Close Only" closes immediately as today.

7. **[model: haiku]** Window-close cancel hook
   - Files: `tian/WindowManagement/WorkspaceWindowController.swift`
   - Depends on: 4
   - Done when: `windowShouldClose` calls `worktreeOrchestrator.cancelCommands()` once before the existing workspace-cleanup loop. Window close is not delayed (call is fire-and-forget).

8. **[model: sonnet]** Project regen + build verification
   - Files: `project.yml` (only if new files don't auto-discover; XcodeGen typically picks up new sources by glob)
   - Depends on: 1, 2, 3, 4, 5, 6, 7
   - Done when: `xcodegen generate` succeeds, `scripts/build.sh Debug` succeeds with no warnings, `xcodebuild -derivedDataPath .build test -only-testing:tianTests` passes (UI tests skipped per project memory).

---

## 6. Risks & Open Questions

- **Risk:** The `runShellCommands` label guard at line 347 was added to coalesce `@Observable` notifications "one per command" — lifting the guard means archive flows now also publish per-command snapshots. This is the *intended* behavior (the whole feature depends on it), but if any code path elsewhere depended on archive *not* publishing snapshots, it will start firing extra observations. Mitigation: grep the codebase for `setupProgress` readers; the only readers today are `SidebarSpaceRowView` (already gated on Space identity) and `WorkspaceWindowContent.displayedProgress` (already correctly handles nil-out / re-fire). No third reader exists.
- **Risk:** The `isCloseInFlight` guard rejects concurrent close on a *different* Space, but if the user has `tian-cli worktree remove` driven from a script that fires multiple removals in parallel, the script will get sporadic `closeInFlight` errors. Mitigation: documented in the PRD §8 (out of scope) and §6 (edge states); the CLI error message tells the user to retry. Acceptable for v1.
- **Risk:** `WorktreeService.archiveCommandCount` re-parses the TOML config independently of the orchestrator's parse. If the config is malformed, the helper returns 0 and the secondary confirmation is suppressed — the user picks "Close Only" without warning even though archive *would* have run if the config were valid. Mitigation: the orchestrator's parse path already logs malformed configs; the helper logs at `info` level when it returns 0 due to parse failure so the divergence is observable. Not a bug, but documented.
- **Risk:** Window close fires `cancelCommands()` fire-and-forget (FR-062). If the SIGTERM doesn't reach the child process before the window's `windowWillClose` runs and the orchestrator deinits, the child becomes a detached process. macOS will eventually reap it (parent process exits, kernel reparents to `launchd`), but `docker compose down` could continue running in the background. Mitigation: this matches today's behavior for any in-flight setup at app quit, so it is not a regression. Documented in the PRD as accepted v1 behavior.
- **Open question:** None — all PRD open questions were resolved during the v1.1 review.
