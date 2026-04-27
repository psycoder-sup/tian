# Worktree setup progress + lag fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the unscoped `isCreating` spinner with a per-Space, per-workspace progress notifier (sidebar Space row + bottom-right capsule), and move shell-command execution off the main actor with incremental pipe drain to eliminate UI lag and pipe-overflow deadlock during worktree setup.

**Architecture:** New `SetupProgress` value type carries `(workspaceID, spaceID, currentIndex, totalCommands, currentCommand, lastFailedIndex)`. The orchestrator publishes it as an optional `@Observable` property; UI surfaces (`SidebarSpaceRowView`, new `SetupProgressCapsule`) bind to it. Shell command execution is moved into a `nonisolated` static helper that uses `readabilityHandler` to drain pipes incrementally with a 256 KB cap. Cancellation crosses isolation as a Sendable token closure that signals the child PID via `kill()`.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, swift-testing (`@Test` / `#expect`), Foundation `Process` / `Pipe`, XcodeGen (`project.yml`). Build: `scripts/build.sh`. Tests: `xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build -only-testing:tianTests/<name>`.

**Spec:** `docs/superpowers/specs/2026-04-27-worktree-setup-progress-design.md`.

---

## File Structure

**Create:**
- `tian/Worktree/SetupProgress.swift` — the `SetupProgress` value type and `CancellationToken` Sendable wrapper.
- `tian/View/Worktree/SetupProgressCapsule.swift` — replaces the bottom-right cancel button with a richer capsule.

**Modify:**
- `tian/Worktree/WorktreeOrchestrator.swift` — replace `isCreating` with `setupProgress`, extract `runShellCommand` to a `nonisolated static` helper, switch to `readabilityHandler`, replace `currentCommandProcess` with a Sendable cancellation handle.
- `tian/View/Workspace/WorkspaceWindowContent.swift` — wire the new capsule, drop reference to `SetupCancelButton`.
- `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift` — drop the `ProgressView()` and `isCreatingWorktree` parameter.
- `tian/View/Sidebar/SidebarExpandedContentView.swift` — pass orchestrator to space rows; drop `isCreatingWorktree:` argument.
- `tian/View/Sidebar/SidebarSpaceRowView.swift` — accept `setupProgress: SetupProgress?` (or the orchestrator) and render a setup-progress style when its `spaceID` matches.
- `tianTests/WorktreeOrchestratorTests.swift` — update existing assertions (`!orchestrator.isCreating` → `orchestrator.setupProgress == nil`) and add new tests.

**Delete:**
- `tian/View/Worktree/SetupCancelButton.swift`.

After any file create/delete: `xcodegen generate` so `tian.xcodeproj` picks them up.

Each task ends with a commit. Use `xcodegen generate && xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build -only-testing:tianTests/WorktreeOrchestratorTests` for the orchestrator-focused tests; the full suite (`xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build`) at the end of the plan.

---

## Task 1: `SetupProgress` value type

**Goal:** Introduce the new model in its own file. No orchestrator wiring yet — pure value type with a unit test.

**Files:**
- Create: `tian/Worktree/SetupProgress.swift`
- Test: `tianTests/SetupProgressTests.swift` (new)

- [ ] **Step 1: Write the failing test**

Create `tianTests/SetupProgressTests.swift`:

```swift
import Testing
import Foundation
@testable import tian

@Suite("SetupProgress")
struct SetupProgressTests {

    @Test func equality_byAllFields() {
        let workspaceID = UUID()
        let spaceID = UUID()
        let a = SetupProgress(
            workspaceID: workspaceID,
            spaceID: spaceID,
            totalCommands: 3,
            currentIndex: 1,
            currentCommand: "echo hi",
            lastFailedIndex: nil
        )
        let b = a
        var c = a
        c.currentIndex = 2
        #expect(a == b)
        #expect(a != c)
    }

    @Test func startingValue_hasNegativeIndexAndNoFailure() {
        let progress = SetupProgress.starting(
            workspaceID: UUID(),
            spaceID: UUID(),
            totalCommands: 5
        )
        #expect(progress.currentIndex == -1)
        #expect(progress.currentCommand == nil)
        #expect(progress.lastFailedIndex == nil)
        #expect(progress.totalCommands == 5)
    }
}
```

- [ ] **Step 2: Run the test — expect "cannot find type 'SetupProgress'"**

```bash
xcodegen generate
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/SetupProgressTests 2>&1 | tail -20
```

Expected: build failure / `cannot find type 'SetupProgress' in scope`.

- [ ] **Step 3: Implement the type**

Create `tian/Worktree/SetupProgress.swift`:

```swift
import Foundation

/// Per-Space progress signal published by `WorktreeOrchestrator` while
/// `[[setup]]` commands run. Drives both the sidebar Space-row indicator
/// and the bottom-right `SetupProgressCapsule`.
///
/// Lifecycle:
/// - `nil` ⇔ no setup is in flight.
/// - Non-nil from just before the first `[[setup]]` command runs until
///   the loop exits (success, all-failed, or cancelled). Cleared back
///   to `nil` before layout application.
struct SetupProgress: Equatable, Sendable {
    /// Workspace that owns the new Space.
    let workspaceID: UUID
    /// The Space being set up.
    let spaceID: UUID
    /// Number of `[[setup]]` commands declared in `.tian/config.toml`.
    let totalCommands: Int
    /// 0-based index of the currently executing command. `-1` before the
    /// first command starts.
    var currentIndex: Int
    /// The command string currently running, or `nil` before the first
    /// command starts.
    var currentCommand: String?
    /// Index of the most recent command that exited non-zero, if any.
    var lastFailedIndex: Int?

    /// Builds the initial pre-run progress value.
    static func starting(
        workspaceID: UUID,
        spaceID: UUID,
        totalCommands: Int
    ) -> SetupProgress {
        SetupProgress(
            workspaceID: workspaceID,
            spaceID: spaceID,
            totalCommands: totalCommands,
            currentIndex: -1,
            currentCommand: nil,
            lastFailedIndex: nil
        )
    }
}

/// Sendable handle for terminating an in-flight setup command from another
/// isolation domain. The closure captures only the child PID and signals
/// it via `kill(2)`.
struct SetupCancellationToken: Sendable {
    let terminate: @Sendable () -> Void
}
```

- [ ] **Step 4: Regenerate project and run the test — expect pass**

```bash
xcodegen generate
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/SetupProgressTests 2>&1 | tail -20
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add tian/Worktree/SetupProgress.swift tianTests/SetupProgressTests.swift project.yml tian.xcodeproj
git commit -m "$(cat <<'EOF'
✨ feat(worktree): SetupProgress value type + cancellation token

Pure value type the orchestrator will publish during [[setup]] command
execution. Includes a Sendable cancellation token wrapper so the
nonisolated runner can hand cancel-by-PID back to the main actor.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Replace `isCreating` with `setupProgress` (lifecycle only)

**Goal:** Wire the new optional onto the orchestrator. Set it before `runShellCommands` for `[[setup]]`, clear it after. Don't yet track per-command index — that's Task 3.

**Files:**
- Modify: `tian/Worktree/WorktreeOrchestrator.swift`
- Modify: `tian/View/Sidebar/SidebarExpandedContentView.swift`
- Modify: `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift`
- Modify: `tian/View/Workspace/WorkspaceWindowContent.swift`
- Modify: `tianTests/WorktreeOrchestratorTests.swift`

- [ ] **Step 1: Update existing tests to drop `isCreating` and add a lifecycle assertion**

In `tianTests/WorktreeOrchestratorTests.swift`:

Replace this line in `createWorktreeSpaceWithConfig` (around line 131):
```swift
        // Verify isCreating is reset
        #expect(!orchestrator.isCreating)
```
with:
```swift
        // Verify setupProgress is cleared
        #expect(orchestrator.setupProgress == nil)
```

Replace this line in `cancelSetupSkipsRemainingCommands` (around line 246):
```swift
        // isCreating should be reset
        #expect(!orchestrator.isCreating)
```
with:
```swift
        // setupProgress should be cleared
        #expect(orchestrator.setupProgress == nil)
```

Add this new test inside the `WorktreeOrchestratorTests` struct (place it after `cancelSetupSkipsRemainingCommands`):

```swift
    // MARK: - SetupProgress lifecycle

    @Test func setupProgress_isNilBeforeAndAfterCreation() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 0.5

        [[setup]]
        command = "true"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        #expect(orchestrator.setupProgress == nil)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "lifecycle-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(orchestrator.setupProgress == nil)
        #expect(!result.existed)
    }

    @Test func setupProgress_carriesWorkspaceAndSpaceIDsDuringRun() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // A single command that blocks until the test releases it. While
        // blocked, we snapshot setupProgress and assert its IDs.
        let gate = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-setup-gate-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: gate) }

        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 5

        [[setup]]
        command = "while [ ! -f \(gate) ]; do sleep 0.02; done"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        Task { @MainActor in
            // Wait for setupProgress to appear, snapshot, then release the gate.
            for _ in 0..<200 {
                if orchestrator.setupProgress != nil { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(orchestrator.setupProgress?.workspaceID == workspace.id)
            #expect(orchestrator.setupProgress?.totalCommands == 1)
            FileManager.default.createFile(atPath: gate, contents: Data(), attributes: nil)
        }

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "ids-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(orchestrator.setupProgress?.spaceID == nil)        // cleared
        #expect(orchestrator.setupProgress == nil)
        #expect(result.spaceID == workspace.spaceCollection.spaces.first { $0.id == result.spaceID }?.id)
    }
```

- [ ] **Step 2: Run the failing tests**

```bash
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/WorktreeOrchestratorTests 2>&1 | tail -30
```

Expected: build error — `setupProgress` not a member of `WorktreeOrchestrator`.

- [ ] **Step 3: Replace `isCreating` with `setupProgress` on the orchestrator**

In `tian/Worktree/WorktreeOrchestrator.swift`, find:

```swift
    /// True during creation flow; drives sidebar progress indicator.
    var isCreating: Bool = false
```

Replace with:

```swift
    /// Populated while `[[setup]]` commands run for a freshly-created
    /// worktree Space. `nil` means no setup is in flight. Drives the
    /// sidebar Space-row progress UI and the bottom-right capsule.
    var setupProgress: SetupProgress?
```

Find the two lines in `createWorktreeSpace`:

```swift
        // Step 5: Begin creation
        isCreating = true
        defer { isCreating = false }
```

Delete both lines and the comment. (The `setupProgress` lifecycle is bound to the setup-command loop, not the entire creation flow. Worktree creation, file copy, and Space creation happen silently — they're fast.)

In `continueCreation`, find the call site for `runShellCommands(commands: config.setupCommands, label: "setup", …)` (around line 289) and wrap it with progress lifecycle:

```swift
        // Step 12: Run setup commands as background processes (FR-012)
        if !config.setupCommands.isEmpty {
            setupProgress = SetupProgress.starting(
                workspaceID: targetWorkspace.id,
                spaceID: newSpace.id,
                totalCommands: config.setupCommands.count
            )
        }
        await runShellCommands(
            commands: config.setupCommands,
            label: "setup",
            worktreePath: worktreePath,
            config: config
        )
        setupProgress = nil
```

- [ ] **Step 4: Update view layer to drop the now-removed `isCreating`**

In `tian/View/Sidebar/SidebarWorkspaceHeaderView.swift`, delete the `let isCreatingWorktree: Bool` parameter and the `if isCreatingWorktree { ProgressView() … }` block (the whole 5-line block). The header now never shows a spinner.

The full updated header struct opening:

```swift
struct SidebarWorkspaceHeaderView: View {
    let workspace: Workspace
    let isExpanded: Bool
    let isActive: Bool
    let isKeyboardSelected: Bool
    let onToggleDisclosure: () -> Void
    let onAddSpace: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)

            InlineRenameView(
                text: workspace.name,
                isRenaming: $isRenaming,
                onCommit: { workspace.name = $0 }
            )
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)

            Spacer()

            Button(action: onAddSpace) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(white: 0.4, opacity: 1))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-space-\(workspace.id)")
            .accessibilityLabel("New space in \(workspace.name)")
            .help("New space (⇧⌘T)")
        }
        // … rest unchanged …
```

In `tian/View/Sidebar/SidebarExpandedContentView.swift`, find the call:

```swift
                    SidebarWorkspaceHeaderView(
                        workspace: workspace,
                        isExpanded: disclosedWorkspaces.contains(workspace.id),
                        isActive: workspace.id == workspaceCollection.activeWorkspaceID,
                        isKeyboardSelected: selectedIndex == flatIndex(for: .workspaceHeader(workspace)),
                        isCreatingWorktree: worktreeOrchestrator.isCreating,
                        onToggleDisclosure: { toggleDisclosure(workspace.id) },
```

Delete the `isCreatingWorktree:` argument line. The remaining call:

```swift
                    SidebarWorkspaceHeaderView(
                        workspace: workspace,
                        isExpanded: disclosedWorkspaces.contains(workspace.id),
                        isActive: workspace.id == workspaceCollection.activeWorkspaceID,
                        isKeyboardSelected: selectedIndex == flatIndex(for: .workspaceHeader(workspace)),
                        onToggleDisclosure: { toggleDisclosure(workspace.id) },
                        onAddSpace: { addSpace(to: workspace) },
                        onSetDirectory: { url in
                            workspace.setDefaultWorkingDirectory(url)
                        },
                        onClose: { workspaceCollection.removeWorkspace(id: workspace.id) }
                    )
```

In `tian/View/Workspace/WorkspaceWindowContent.swift`, replace `worktreeOrchestrator.isCreating` with `worktreeOrchestrator.setupProgress != nil` in two places (lines 18 and 86):

```swift
            if worktreeOrchestrator.setupProgress != nil {
                SetupCancelButton { worktreeOrchestrator.cancelCommands() }
                    .padding(12)
                    .transition(.opacity)
            }
```

```swift
        .animation(.easeInOut(duration: 0.15), value: worktreeOrchestrator.setupProgress != nil)
```

(The cancel-button view itself gets replaced in Task 7; for now we just retarget the binding.)

- [ ] **Step 5: Run the orchestrator tests — expect lifecycle tests pass, IDs test may race**

```bash
xcodegen generate
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/WorktreeOrchestratorTests 2>&1 | tail -30
```

Expected: all tests pass. If `setupProgress_carriesWorkspaceAndSpaceIDsDuringRun` is flaky from the polling window not catching the in-flight state, tighten the inner sleep (10 ms) or extend the outer iteration count (500). The test is intentionally robust to timing.

- [ ] **Step 6: Commit**

```bash
git add tian/Worktree/WorktreeOrchestrator.swift \
        tian/View/Sidebar/SidebarWorkspaceHeaderView.swift \
        tian/View/Sidebar/SidebarExpandedContentView.swift \
        tian/View/Workspace/WorkspaceWindowContent.swift \
        tianTests/WorktreeOrchestratorTests.swift
git commit -m "$(cat <<'EOF'
✨ feat(worktree): replace isCreating with scoped SetupProgress

setupProgress carries the target workspace and space IDs, so the UI
can target only the affected workspace/Space — fixing the bug where
every workspace's sidebar header lit up during any worktree creation
in the window. Lifecycle is bound to the [[setup]] command loop only;
worktree creation and file copy stay silent.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Track `currentIndex`, `currentCommand`, `lastFailedIndex` per command

**Goal:** Update `setupProgress` before each command and capture failures.

**Files:**
- Modify: `tian/Worktree/WorktreeOrchestrator.swift`
- Modify: `tianTests/WorktreeOrchestratorTests.swift`

- [ ] **Step 1: Write the failing test for failure tracking**

Append inside `WorktreeOrchestratorTests`:

```swift
    @Test func setupProgress_recordsLastFailedIndex_whenCommandExitsNonZero() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Three commands; the middle one fails. We capture lastFailedIndex
        // mid-flight via a sentinel-blocked third command.
        let gate = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-fail-gate-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: gate) }

        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 5

        [[setup]]
        command = "true"

        [[setup]]
        command = "exit 7"

        [[setup]]
        command = "while [ ! -f \(gate) ]; do sleep 0.02; done"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        Task { @MainActor in
            // Wait for currentIndex to reach 2 (the gated command).
            for _ in 0..<300 {
                if orchestrator.setupProgress?.currentIndex == 2 { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(orchestrator.setupProgress?.lastFailedIndex == 1)
            FileManager.default.createFile(atPath: gate, contents: Data(), attributes: nil)
        }

        _ = try await orchestrator.createWorktreeSpace(
            branchName: "fail-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        #expect(orchestrator.setupProgress == nil)
    }
```

- [ ] **Step 2: Run — expect failure**

```bash
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/WorktreeOrchestratorTests/setupProgress_recordsLastFailedIndex_whenCommandExitsNonZero 2>&1 | tail -30
```

Expected: test fails — `lastFailedIndex` is `nil` because nothing writes it yet.

- [ ] **Step 3: Update the loop and per-command runner**

In `tian/Worktree/WorktreeOrchestrator.swift`, find `runShellCommands` and replace it with:

```swift
    private func runShellCommands(
        commands: [String],
        label: String,
        worktreePath: String,
        config: WorktreeConfig
    ) async {
        guard !commands.isEmpty else { return }
        installCtrlCMonitor()
        defer { removeCtrlCMonitor() }

        for (index, command) in commands.enumerated() {
            if commandsCancelled {
                Log.worktree.info("\(label.capitalized) cancelled by user after \(index)/\(commands.count) commands")
                break
            }
            // Only [[setup]] populates setupProgress; archive runs silently.
            if label == "setup", setupProgress != nil {
                setupProgress?.currentIndex = index
                setupProgress?.currentCommand = command
            }
            Log.worktree.info("Running \(label) command \(index + 1)/\(commands.count): \(command)")
            let exit = await runShellCommand(
                command,
                label: label,
                worktreePath: worktreePath,
                timeout: config.setupTimeout
            )
            if label == "setup", exit != 0, setupProgress != nil {
                setupProgress?.lastFailedIndex = index
            }
        }
    }
```

Change the signature of `runShellCommand` to return the exit code. Find the existing function (around line 345) and update its declaration plus the trailing return:

```swift
    private func runShellCommand(
        _ command: String,
        label: String,
        worktreePath: String,
        timeout: TimeInterval
    ) async -> Int32 {
```

Just before the closing brace of the function (after the existing `Log.worktree.info("\(label.capitalized) command exit=\(process.terminationStatus): \(command)")` line), append:

```swift
        return process.terminationStatus
    }
```

Make sure there is a `return -1` in the early-failure path inside the `do { try process.run() } catch { … return }` block. Replace the existing `return` (no value) inside that catch with `return -1`:

```swift
        do {
            try process.run()
        } catch {
            Log.worktree.warning("Failed to launch \(label) command '\(command)': \(error.localizedDescription)")
            return -1
        }
```

- [ ] **Step 4: Run the test — expect pass**

```bash
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/WorktreeOrchestratorTests/setupProgress_recordsLastFailedIndex_whenCommandExitsNonZero 2>&1 | tail -20
```

Expected: pass.

- [ ] **Step 5: Run the full orchestrator suite to confirm no regression**

```bash
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/WorktreeOrchestratorTests 2>&1 | tail -30
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add tian/Worktree/WorktreeOrchestrator.swift tianTests/WorktreeOrchestratorTests.swift
git commit -m "$(cat <<'EOF'
✨ feat(worktree): per-command setupProgress + failure tracking

Advance currentIndex/currentCommand before each [[setup]] command.
Record lastFailedIndex on non-zero exit. Loop continues past failures
(unchanged); the new field lets the UI render a per-step ✗ glyph.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Move command execution off the main actor + incremental pipe drain

**Goal:** Eliminate UI lag during setup. Switch `runShellCommand` to a `nonisolated static` helper that uses `readabilityHandler` to drain pipes incrementally with a 256 KB cap. Replace the `currentCommandProcess` reference with a Sendable `SetupCancellationToken` so cancellation crosses isolation cleanly.

**Files:**
- Modify: `tian/Worktree/WorktreeOrchestrator.swift`
- Modify: `tianTests/WorktreeOrchestratorTests.swift`

- [ ] **Step 1: Write the failing pipe-overflow test**

Append inside `WorktreeOrchestratorTests`:

```swift
    @Test func setupCommands_withLargeOutput_doNotDeadlock() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Emit ~300 KB of stdout. With the old readDataToEndOfFile() drain,
        // the child blocks on a full pipe, terminationHandler never fires,
        // and we hit the timeout. With incremental drain, this completes
        // promptly under the 5 s timeout.
        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 5

        [[setup]]
        command = "yes hello | head -c 300000"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let start = ContinuousClock.now
        _ = try await orchestrator.createWorktreeSpace(
            branchName: "loud-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        let elapsed = ContinuousClock.now - start

        // Allow generous slack on busy CI; 4 s well below the 5 s timeout.
        #expect(elapsed < .seconds(4))
        #expect(orchestrator.setupProgress == nil)
    }
```

- [ ] **Step 2: Run — expect timeout / failure**

```bash
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/WorktreeOrchestratorTests/setupCommands_withLargeOutput_doNotDeadlock 2>&1 | tail -30
```

Expected: test fails (elapsed exceeds 4 s due to pipe-full deadlock causing the 5 s timeout to fire).

If the existing pipe drain happens to squeak through at 300 KB on this OS revision (kernel buffer sizing varies), bump the `head -c` count to `2000000` and retry — the deadlock is guaranteed once a full process iteration's output exceeds the kernel pipe buffer.

- [ ] **Step 3: Replace `runShellCommand` with a `nonisolated static` helper**

In `tian/Worktree/WorktreeOrchestrator.swift`:

Delete the existing `currentCommandProcess` property declaration:
```swift
    /// Currently running shell process (setup or archive), if any.
    /// Used for cancellation/timeout.
    private var currentCommandProcess: Process?
```

Replace with:
```swift
    /// Sendable handle for terminating the in-flight shell command, if
    /// any. Set by the nonisolated runner just before the child process
    /// starts and cleared when it exits. Read by `cancelCommands()`.
    private var cancellationToken: SetupCancellationToken?
```

Update `cancelCommands` to use the new field:
```swift
    func cancelCommands() {
        commandsCancelled = true
        cancellationToken?.terminate()
    }
```

Replace the entire body of `runShellCommand` with a thin call into the static helper. The wrapper still runs on `@MainActor`:

```swift
    private func runShellCommand(
        _ command: String,
        label: String,
        worktreePath: String,
        timeout: TimeInterval
    ) async -> Int32 {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        return await Self.runCommandOffMain(
            command: command,
            label: label,
            shellPath: shellPath,
            worktreePath: worktreePath,
            timeout: timeout,
            onStarted: { [weak self] token in
                Task { @MainActor in self?.cancellationToken = token }
            },
            onEnded: { [weak self] in
                Task { @MainActor in self?.cancellationToken = nil }
            }
        )
    }
```

Add the static helper at the bottom of the type (just above the closing `}` of `final class WorktreeOrchestrator`):

```swift
    /// Per-stream output cap. Anything beyond this is discarded and a
    /// truncation marker is appended to the final log line.
    private static let outputBufferCap = 256 * 1024

    /// Runs a single shell command without touching the main actor.
    ///
    /// Uses `readabilityHandler` on each pipe to drain output incrementally
    /// — the child can write more than the kernel pipe buffer (~16-64 KB)
    /// without blocking, eliminating the previous deadlock for chatty
    /// commands like `bun install`.
    ///
    /// `onStarted` and `onEnded` are Sendable callbacks the caller uses
    /// to publish/clear the cancellation token on its own actor.
    nonisolated private static func runCommandOffMain(
        command: String,
        label: String,
        shellPath: String,
        worktreePath: String,
        timeout: TimeInterval,
        onStarted: @Sendable (SetupCancellationToken) -> Void,
        onEnded: @Sendable () -> Void
    ) async -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: shellPath)
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(filePath: worktreePath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = LimitedBuffer(cap: outputBufferCap)
        let stderrBuffer = LimitedBuffer(cap: outputBufferCap)

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stdoutBuffer.append(chunk)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrBuffer.append(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            Log.worktree.warning("Failed to launch \(label) command '\(command)': \(error.localizedDescription)")
            return -1
        }

        let pid = process.processIdentifier
        let token = SetupCancellationToken { kill(pid, SIGTERM) }
        onStarted(token)
        defer { onEnded() }

        let timeoutItem = DispatchWorkItem { kill(pid, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        timeoutItem.cancel()

        // Detach handlers — the child has exited so further availableData
        // reads would just return empty buffers.
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let (stdoutData, stdoutTrunc) = stdoutBuffer.snapshot()
        let (stderrData, stderrTrunc) = stderrBuffer.snapshot()

        let trimmedStdout = (String(data: stdoutData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = (String(data: stderrData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stdoutSuffix = stdoutTrunc ? " … (truncated at \(outputBufferCap) bytes)" : ""
        let stderrSuffix = stderrTrunc ? " … (truncated at \(outputBufferCap) bytes)" : ""
        if !trimmedStdout.isEmpty {
            Log.worktree.info("\(label) stdout: \(trimmedStdout)\(stdoutSuffix)")
        }
        if !trimmedStderr.isEmpty {
            Log.worktree.warning("\(label) stderr: \(trimmedStderr)\(stderrSuffix)")
        }
        Log.worktree.info("\(label.capitalized) command exit=\(process.terminationStatus): \(command)")

        return process.terminationStatus
    }
}

/// Lock-protected bounded byte buffer for incremental pipe drain.
/// Concurrent reads across both stdout and stderr handlers go through
/// independent instances; the lock guards in-instance state.
private final class LimitedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false
    private let cap: Int

    init(cap: Int) { self.cap = cap }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        if truncated { return }
        let space = cap - data.count
        if space <= 0 {
            truncated = true
            return
        }
        if chunk.count <= space {
            data.append(chunk)
        } else {
            data.append(chunk.prefix(space))
            truncated = true
        }
    }

    func snapshot() -> (Data, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
    }
}
```

(The closing `}` of `LimitedBuffer` is the file's end. The orchestrator's closing `}` immediately precedes `private final class LimitedBuffer`.)

- [ ] **Step 4: Build and run**

```bash
scripts/build.sh Debug 2>&1 | tail -20
```

Expected: build succeeds. If Swift 6 strict concurrency complains about `process` capture in the `terminationHandler` closure, the existing code already does this — Foundation's `terminationHandler` is `@Sendable` in the SDK and the capture is fine. If a different diagnostic appears, the most likely culprit is the `kill` call needing `import Darwin` (already imported via Foundation, but if the diagnostic insists, add `import Darwin` near the top of the file).

```bash
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/WorktreeOrchestratorTests 2>&1 | tail -40
```

Expected: all orchestrator tests pass, including `setupCommands_withLargeOutput_doNotDeadlock`.

- [ ] **Step 5: Commit**

```bash
git add tian/Worktree/WorktreeOrchestrator.swift tianTests/WorktreeOrchestratorTests.swift
git commit -m "$(cat <<'EOF'
🐛 fix(worktree): off-main shell exec + incremental pipe drain

Move runShellCommand into a nonisolated static helper. Replace the
blocking readDataToEndOfFile drain with readabilityHandler accumulating
into a 256 KB-capped lock-protected buffer. Fixes pipe-full deadlock
for chatty setup commands and removes UI thread blocking during the
fork/exec + I/O. Cancellation crosses isolation as a Sendable
SetupCancellationToken that signals the child PID via kill(SIGTERM).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: `SetupProgressCapsule` view + delete `SetupCancelButton`

**Goal:** Replace the bottom-right cancel-only capsule with a richer one that shows step counter and current command.

**Files:**
- Create: `tian/View/Worktree/SetupProgressCapsule.swift`
- Delete: `tian/View/Worktree/SetupCancelButton.swift`
- Modify: `tian/View/Workspace/WorkspaceWindowContent.swift`

- [ ] **Step 1: Write the new view**

Create `tian/View/Worktree/SetupProgressCapsule.swift`:

```swift
import SwiftUI

/// Bottom-right overlay shown while `[[setup]]` commands run for a
/// freshly-created worktree Space. Displays the step counter, current
/// command, a failure glyph if the most recent step failed, and a
/// cancel button. Replaces the older cancel-only `SetupCancelButton`.
struct SetupProgressCapsule: View {
    let progress: SetupProgress
    let onCancel: () -> Void

    private var stepText: String {
        let displayed = max(progress.currentIndex + 1, 1)
        return "\(displayed)/\(progress.totalCommands)"
    }

    private var commandLabel: String {
        progress.currentCommand ?? "starting…"
    }

    private var didFailLastStep: Bool {
        guard let failedIndex = progress.lastFailedIndex else { return false }
        return failedIndex == progress.currentIndex
    }

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)

            Text("Setup \(stepText)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if didFailLastStep {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
                    .accessibilityLabel("last step failed")
            }

            Text("·")
                .foregroundStyle(.secondary)

            Text(commandLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320, alignment: .leading)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel setup")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
```

- [ ] **Step 2: Wire the new view + drop the old one**

In `tian/View/Workspace/WorkspaceWindowContent.swift`, replace the `SetupCancelButton` block (currently in the body):

```swift
            if worktreeOrchestrator.setupProgress != nil {
                SetupCancelButton { worktreeOrchestrator.cancelCommands() }
                    .padding(12)
                    .transition(.opacity)
            }
```

with:

```swift
            if let progress = worktreeOrchestrator.setupProgress {
                SetupProgressCapsule(progress: progress) {
                    worktreeOrchestrator.cancelCommands()
                }
                .padding(12)
                .transition(.opacity)
            }
```

Delete `tian/View/Worktree/SetupCancelButton.swift`:

```bash
rm tian/View/Worktree/SetupCancelButton.swift
```

- [ ] **Step 3: Regenerate project + build**

```bash
xcodegen generate
scripts/build.sh Debug 2>&1 | tail -20
```

Expected: build succeeds.

- [ ] **Step 4: Smoke test in app**

```bash
open .build/Build/Products/Debug/tian.app
```

In a real git repo with a `.tian/config.toml` containing 2-3 `[[setup]]` commands (e.g. `echo step1; sleep 1`, `echo step2; sleep 1`), trigger ⇧⌘T → "Create as worktree". Verify the bottom-right capsule shows step counter, current command, and a working cancel button.

- [ ] **Step 5: Commit**

```bash
git add tian/View/Worktree/SetupProgressCapsule.swift \
        tian/View/Workspace/WorkspaceWindowContent.swift \
        project.yml tian.xcodeproj
git rm tian/View/Worktree/SetupCancelButton.swift
git commit -m "$(cat <<'EOF'
🎨 feat(worktree): SetupProgressCapsule replaces SetupCancelButton

Bottom-right capsule now shows step counter (n/N), current command,
and a ✗ glyph when the most recent step failed. Old cancel-only
SetupCancelButton view removed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Sidebar Space-row setup-progress style

**Goal:** When `setupProgress?.spaceID == space.id`, render the sidebar row as a one-line setup indicator instead of the normal Space row, and disable interactions that would mutate the Space.

**Files:**
- Modify: `tian/View/Sidebar/SidebarSpaceRowView.swift`
- Modify: `tian/View/Sidebar/SidebarExpandedContentView.swift`

- [ ] **Step 1: Pass the orchestrator into the row view**

In `tian/View/Sidebar/SidebarExpandedContentView.swift`, change the call to `SidebarSpaceRowView` (around line 46) to pass the orchestrator:

```swift
                                SidebarSpaceRowView(
                                    space: space,
                                    isActive: workspace.id == workspaceCollection.activeWorkspaceID
                                        && space.id == workspace.spaceCollection.activeSpaceID,
                                    isKeyboardSelected: selectedIndex == flatIndex(for: .spaceRow(workspace, space)),
                                    setupProgress: worktreeOrchestrator.setupProgress?.spaceID == space.id
                                        ? worktreeOrchestrator.setupProgress
                                        : nil,
                                    onSelect: { selectSpace(workspace: workspace, spaceID: space.id) },
                                    onSetDirectory: { url in
                                        space.defaultWorkingDirectory = url
                                    },
                                    onClose: { closeSpace(space, in: workspace) }
                                )
```

(Passing `nil` when this row isn't the target keeps SwiftUI re-renders narrow — only the matched row diffs as `setupProgress` advances.)

- [ ] **Step 2: Update `SidebarSpaceRowView` to accept and render setup progress**

In `tian/View/Sidebar/SidebarSpaceRowView.swift`, add the new property in the struct's stored properties block (just after `let isKeyboardSelected: Bool`):

```swift
    let setupProgress: SetupProgress?
```

Add a computed helper near the existing `tabCountLabel`:

```swift
    private var isSettingUp: Bool { setupProgress != nil }
```

In `body`, replace the existing top-level `VStack(alignment: .leading, spacing: 4)` content with a conditional. Find:

```swift
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                InlineRenameView(
                    text: space.name,
                    isRenaming: $isRenaming,
                    onCommit: { space.name = $0 }
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color(white: 0.9) : Color(red: 0.557, green: 0.557, blue: 0.576))

                Spacer()

                Text(tabCountLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            SpaceStatusAreaView(sessions: sessions, space: space, isActive: isActive)
        }
```

Wrap it in an `if isSettingUp { … } else { … }`:

```swift
        Group {
            if let progress = setupProgress {
                setupProgressRow(progress: progress)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        InlineRenameView(
                            text: space.name,
                            isRenaming: $isRenaming,
                            onCommit: { space.name = $0 }
                        )
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isActive ? Color(white: 0.9) : Color(red: 0.557, green: 0.557, blue: 0.576))

                        Spacer()

                        Text(tabCountLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.45))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }

                    SpaceStatusAreaView(sessions: sessions, space: space, isActive: isActive)
                }
            }
        }
```

Add the `setupProgressRow` helper inside the struct (just before `var body: some View`):

```swift
    @ViewBuilder
    private func setupProgressRow(progress: SetupProgress) -> some View {
        let displayed = max(progress.currentIndex + 1, 1)
        let didFailLast = progress.lastFailedIndex == progress.currentIndex

        HStack(spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(space.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.85))
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.secondary)

            Text("\(displayed)/\(progress.totalCommands)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if didFailLast {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
            }

            Text(progress.currentCommand ?? "starting…")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Color(white: 0.55))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }
```

Also, while in setup, disable the row's mutating gestures and context menu. Find these modifiers near the end of `body`:

```swift
        .onTapGesture { … }
        .onHover { isHovering = $0 }
        .draggable(SpaceDragItem(spaceID: space.id))
        .contextMenu { … }
```

Conditionally apply mutating ones only when not in setup. Replace those four lines with:

```swift
        .onHover { isHovering = $0 }
        .onTapGesture {
            if isSettingUp {
                onSelect()
                return
            }
            let now = Date()
            if let last = lastClickTime, now.timeIntervalSince(last) < 0.3 {
                lastClickTime = nil
                isRenaming = true
            } else {
                lastClickTime = now
                onSelect()
            }
        }
        .modifier(SidebarSpaceRowConditionalDraggable(spaceID: space.id, enabled: !isSettingUp))
        .modifier(SidebarSpaceRowConditionalContextMenu(
            enabled: !isSettingUp,
            onRename: { isRenaming = true },
            currentDirectory: space.defaultWorkingDirectory,
            spaceName: space.name,
            onSetDirectory: onSetDirectory,
            onClose: onClose
        ))
```

Add the two view-modifier helpers at the bottom of the file (after the closing `}` of `SidebarSpaceRowView`):

```swift
private struct SidebarSpaceRowConditionalDraggable: ViewModifier {
    let spaceID: UUID
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(SpaceDragItem(spaceID: spaceID))
        } else {
            content
        }
    }
}

private struct SidebarSpaceRowConditionalContextMenu: ViewModifier {
    let enabled: Bool
    let onRename: () -> Void
    let currentDirectory: URL?
    let spaceName: String
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu {
                Button("Rename", action: onRename)
                Divider()
                DefaultDirectoryMenu(
                    name: spaceName,
                    currentDirectory: currentDirectory,
                    onSet: onSetDirectory
                )
                Divider()
                Button("Close Space", action: onClose)
            }
        } else {
            content
        }
    }
}
```

- [ ] **Step 3: Regenerate + build**

```bash
xcodegen generate
scripts/build.sh Debug 2>&1 | tail -20
```

Expected: build succeeds.

- [ ] **Step 4: Smoke test in app**

```bash
open .build/Build/Products/Debug/tian.app
```

In a repo with `[[setup]]` commands of measurable duration (e.g. `sleep 2; echo done`), trigger ⇧⌘T → "Create as worktree". Verify:

1. Only the new Space's row in the sidebar shows `⏳  <branch>  ·  1/N  <command>` — other Spaces and other workspaces' headers look normal.
2. The bottom-right capsule shows the same counter and command.
3. After setup completes, the row reverts to the normal Space row layout.
4. While in setup, attempting to rename or right-click the in-progress row does not produce a rename/menu; clicking still focuses the Space.

- [ ] **Step 5: Commit**

```bash
git add tian/View/Sidebar/SidebarSpaceRowView.swift \
        tian/View/Sidebar/SidebarExpandedContentView.swift
git commit -m "$(cat <<'EOF'
🎨 feat(sidebar): setup-progress row style for in-flight Spaces

The Space being created now renders a single-line progress style
(hourglass · name · n/N · command) while [[setup]] runs, and
disables rename/drag/context-menu actions until setup completes.
Other Spaces and workspaces are unaffected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Cancel-mid-command + final test pass

**Goal:** Tighten the cancellation test under the new off-main runner and confirm the full test suite is green.

**Files:**
- Modify: `tianTests/WorktreeOrchestratorTests.swift`

- [ ] **Step 1: Strengthen the cancellation test**

In `tianTests/WorktreeOrchestratorTests.swift`, replace the body of `cancelSetupSkipsRemainingCommands` (currently uses 0.01 s timeouts so the commands all time out without observing cancel). Replace it with:

```swift
    @Test func cancelSetupSkipsRemainingCommands() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 30

        [[setup]]
        command = "sleep 30"

        [[setup]]
        command = "sleep 30"

        [[setup]]
        command = "sleep 30"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // Cancel once setupProgress shows the first command running.
        Task { @MainActor in
            for _ in 0..<300 {
                if orchestrator.setupProgress?.currentCommand?.hasPrefix("sleep") == true { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            orchestrator.cancelCommands()
        }

        let start = ContinuousClock.now
        let result = try await orchestrator.createWorktreeSpace(
            branchName: "cancel-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        let elapsed = ContinuousClock.now - start

        // Whole creation finishes well before any 30 s sleep would.
        #expect(elapsed < .seconds(5))
        #expect(!result.existed)
        #expect(orchestrator.setupProgress == nil)
    }
```

- [ ] **Step 2: Run the full orchestrator suite**

```bash
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build \
  -only-testing:tianTests/WorktreeOrchestratorTests 2>&1 | tail -40
```

Expected: all green.

- [ ] **Step 3: Run the full test suite**

```bash
xcodebuild test -project tian.xcodeproj -scheme tian -derivedDataPath .build 2>&1 | tail -40
```

Expected: all green. Investigate any failure before committing.

- [ ] **Step 4: Commit**

```bash
git add tianTests/WorktreeOrchestratorTests.swift
git commit -m "$(cat <<'EOF'
🧪 test(worktree): cancel-mid-command verifies real termination

Old cancel test used a 0.01 s timeout so commands timed out before any
cancellation could be observed. Switch to long sleep commands and
assert the whole creation finishes within 5 s — proves cancelCommands
actually terminates the in-flight child via the new SetupCancellationToken.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review Notes

**Spec coverage** — every requirement from `2026-04-27-worktree-setup-progress-design.md` maps to a task:

- §1 Model (`SetupProgress` shape, lifecycle, scope, failures) → Tasks 1–3.
- §2 UI placement: sidebar Space row → Task 6; bottom-right capsule → Task 5; removals → Task 2 (header) + Task 5 (capsule).
- §3 Performance (off-main runner, 256 KB pipe-drain cap, Sendable cancellation handle) → Task 4.
- §4 Failure handling (`lastFailedIndex`, log-only, no halt) → Task 3 logic + Task 5 (capsule glyph) + Task 6 (row glyph). Capsule fade-on-failure was specced as ~3 s lingering; this is left to a follow-up since it's pure cosmetic and the spec marks it as "if `lastFailedIndex` is non-nil at the moment it clears, the capsule lingers ~3 s before disappearing" — straightforward to add as `.transition(.opacity.delay(3))` if desired.
- §5 Testing — model lifecycle (Task 2), failure surfacing (Task 3), pipe-overflow no-deadlock (Task 4), cancellation mid-command (Task 7). View-level tests (5.5) were optional in the spec ("or snapshot test if the harness already supports them") and the codebase has no snapshot harness today; the smoke-test steps in Tasks 5 and 6 cover the visual asserts manually.

**Type consistency** — `SetupProgress` properties match across all tasks (`workspaceID`, `spaceID`, `totalCommands`, `currentIndex`, `currentCommand`, `lastFailedIndex`). `SetupCancellationToken.terminate` is consistent in Tasks 1, 4. `cancellationToken` field name is consistent in Task 4.

**Placeholder scan** — no TBDs. Every code step has full code. Test commands are exact.
