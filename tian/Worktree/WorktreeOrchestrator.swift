import AppKit
import Foundation
import os

/// Central coordinator for worktree Space creation and cleanup.
///
/// Drives the end-to-end flow: git worktree creation, config parsing,
/// Space/pane setup, shell readiness, setup commands, and layout application.
@MainActor @Observable
final class WorktreeOrchestrator {

    // MARK: - Properties

    private let workspaceProvider: any WorkspaceProviding

    /// Populated while `[[setup]]` commands run for a freshly-created
    /// worktree Space. `nil` means no setup is in flight. Drives the
    /// sidebar Space-row progress UI and the bottom-right capsule.
    var setupProgress: SetupProgress?

    /// Set to true when the user cancels the in-flight setup or archive
    /// command loop. Reset at the top of each create/remove flow.
    var commandsCancelled: Bool = false

    /// Last error surfaced by the orchestrator, for UI binding.
    var lastError: WorktreeError?

    /// Temporary event monitor for Ctrl+C during shell command loops.
    private var ctrlCMonitor: Any?

    /// Sendable closure that terminates the in-flight shell command, if any.
    /// Published from the nonisolated runner just before the child starts;
    /// cleared when it exits. Read by `cancelCommands()`.
    private var cancellationToken: (@Sendable () -> Void)?

    // MARK: - Init

    init(workspaceProvider: any WorkspaceProviding) {
        self.workspaceProvider = workspaceProvider
    }

    // MARK: - Creation Flow

    /// Creates a worktree-backed Space with full setup.
    ///
    /// Implements the 15-step creation flow from the spec (Section 4.1):
    /// resolve repo → parse config → duplicate detection → pre-flight checks →
    /// create worktree → gitignore → copy files → create Space → shell readiness →
    /// setup commands → layout application.
    ///
    /// - Parameters:
    ///   - branchName: Git branch name for the worktree.
    ///   - existingBranch: If true, checks out an existing branch instead of creating a new one.
    ///   - repoPath: Absolute path to a directory inside the repo. If nil, derived from the active Space.
    ///   - workspaceID: Target workspace ID. If nil, uses the key window's active workspace.
    /// - Returns: Result containing the Space ID and whether an existing Space was focused.
    func createWorktreeSpace(
        branchName: String,
        existingBranch: Bool = false,
        remoteRef: String? = nil,
        repoPath: String? = nil,
        workspaceID: UUID? = nil
    ) async throws -> WorktreeCreateResult {
        commandsCancelled = false

        // Step 1: Resolve workspace and git repo root
        let targetWorkspace = resolveWorkspace(workspaceID: workspaceID)
            ?? resolveWorkspace(workspaceID: nil)
        let directory: String
        if let repoPath {
            directory = repoPath
        } else if let ws = targetWorkspace {
            directory = ws.spaceCollection.resolveWorkingDirectory()
        } else {
            throw WorktreeError.notAGitRepo(directory: "~")
        }
        let repoRoot = try await WorktreeService.resolveRepoRoot(from: directory)
        Log.worktree.info("Resolved git repo root: \(repoRoot)")

        // Step 2: Parse config
        let config = parseConfig(repoRoot: repoRoot)

        // Step 3: Duplicate detection (FR-027)
        let worktreeBase = WorktreeService.resolveWorktreeBase(
            repoRoot: repoRoot, worktreeDir: config.worktreeDir
        )
        let expectedPath = URL(filePath: worktreeBase)
            .appendingPathComponent(branchName)
            .standardizedFileURL

        if let existingSpace = findExistingSpace(worktreePath: expectedPath) {
            Log.worktree.info("Worktree Space already exists for \(expectedPath.path), focusing existing Space \(existingSpace.id)")
            activateSpace(existingSpace)
            return WorktreeCreateResult(spaceID: existingSpace.id, existed: true)
        }

        // Step 4: Pre-flight checks
        if !existingBranch && remoteRef == nil {
            let exists = try await WorktreeService.branchExists(
                repoRoot: repoRoot, branchName: branchName
            )
            if exists {
                throw WorktreeError.branchAlreadyExists(branchName: branchName)
            }
        }
        if WorktreeService.worktreePathExists(
            repoRoot: repoRoot,
            worktreeDir: config.worktreeDir,
            branchName: branchName
        ) {
            throw WorktreeError.worktreePathExists(path: expectedPath.path)
        }

        // Step 6: Create worktree on disk
        let worktreePath = try await WorktreeService.createWorktree(
            repoRoot: repoRoot,
            worktreeDir: config.worktreeDir,
            branchName: branchName,
            existingBranch: existingBranch,
            remoteRef: remoteRef
        )

        // Steps 7-15 are wrapped so the on-disk worktree is cleaned up on failure.
        do {
            return try await continueCreation(
                worktreePath: worktreePath,
                repoRoot: repoRoot,
                branchName: branchName,
                config: config,
                targetWorkspace: targetWorkspace
            )
        } catch {
            try? await WorktreeService.removeWorktree(
                repoRoot: repoRoot, worktreePath: worktreePath, force: true
            )
            throw error
        }
    }

    // MARK: - Cleanup Flow

    /// Removes a worktree-backed Space and its git worktree.
    ///
    /// - Parameters:
    ///   - spaceID: The ID of the Space to remove.
    ///   - force: If true, forces removal even with uncommitted changes.
    ///   - workspaceID: Hint for which workspace to search. If nil, searches all.
    func removeWorktreeSpace(
        spaceID: UUID,
        force: Bool = false,
        workspaceID: UUID? = nil
    ) async throws {
        commandsCancelled = false

        // Step 1: Find Space
        guard let (space, spaceCollection) = findSpace(id: spaceID) else { return }

        // Step 2: Check worktreePath
        guard let worktreeURL = space.worktreePath else {
            // Not a worktree Space — just close it
            spaceCollection.removeSpace(id: spaceID)
            return
        }
        let worktreePath = worktreeURL.path

        // Step 3: Resolve repo roots. `git rev-parse --show-toplevel` from
        // a linked worktree returns the linked worktree's own path, but
        // both `.tian/config.toml` and the worktree base directory live
        // in the *main* worktree. Resolve both so config parsing and
        // prune use the right paths.
        let linkedRoot = try await WorktreeService.resolveRepoRoot(from: worktreePath)
        let mainRepoRoot = (try? await WorktreeService.resolveMainWorktreePath(repoRoot: linkedRoot))
            ?? linkedRoot

        // Step 4: Parse config from the main worktree.
        let config = parseConfig(repoRoot: mainRepoRoot)

        // Step 4.5: Run archive commands (inverse of [[setup]]). Must happen
        // while the worktree directory still exists so commands can `cd`
        // into it (e.g. `docker compose down`).
        await runShellCommands(
            commands: config.archiveCommands,
            label: "archive",
            worktreePath: worktreePath,
            config: config
        )

        // Step 5: Remove worktree
        try await WorktreeService.removeWorktree(
            repoRoot: mainRepoRoot,
            worktreePath: worktreePath,
            force: force
        )

        // Worktree is gone — Space must be removed regardless of pruning outcome.
        defer { spaceCollection.removeSpace(id: spaceID) }

        // Step 6: Prune empty parents (best-effort)
        do {
            try WorktreeService.pruneEmptyParents(
                worktreePath: worktreePath,
                worktreeDir: config.worktreeDir,
                repoRoot: mainRepoRoot
            )
        } catch {
            Log.worktree.warning("Failed to prune empty parents: \(error)")
        }
    }

    // MARK: - Cancellation

    /// Cancels the in-flight shell command loop. Sets `commandsCancelled`
    /// (loop-level early-exit) and signals the running child via the
    /// published cancellation closure (best-effort SIGTERM through `KillGuard`).
    func cancelCommands() {
        commandsCancelled = true
        cancellationToken?()
    }

    /// Stores an error for the UI alert binding to consume.
    func presentError(_ error: Error) {
        if let wErr = error as? WorktreeError {
            lastError = wErr
        } else {
            lastError = .gitError(command: "unknown", stderr: String(describing: error))
        }
    }

    // MARK: - Creation Steps 7-15

    /// Completes creation after the worktree exists on disk. Extracted so the
    /// caller can clean up the on-disk worktree if any step here fails.
    private func continueCreation(
        worktreePath: String,
        repoRoot: String,
        branchName: String,
        config: WorktreeConfig,
        targetWorkspace: Workspace?
    ) async throws -> WorktreeCreateResult {
        // Steps 7-8: Ensure .gitignore + resolve main worktree path
        try WorktreeService.ensureGitignore(
            repoRoot: repoRoot, worktreeDir: config.worktreeDir
        )
        async let mainWorktreePathTask = WorktreeService.resolveMainWorktreePath(
            repoRoot: repoRoot
        )
        let mainWorktreePath = try await mainWorktreePathTask

        // Step 9: Copy env files
        let copiedCount = WorktreeService.copyFiles(
            copyRules: config.copyRules,
            mainWorktreePath: mainWorktreePath,
            newWorktreePath: worktreePath
        )
        if copiedCount > 0 {
            Log.worktree.info("Copied \(copiedCount) files from main worktree to \(worktreePath)")
        }

        // Step 10: Create Space with single pane (FR-011)
        guard let targetWorkspace else {
            throw WorktreeError.gitError(
                command: "worktree create",
                stderr: "No workspace available to create Space in"
            )
        }
        let newSpace = targetWorkspace.spaceCollection.createSpace(
            workingDirectory: worktreePath
        )
        let worktreeURL = URL(filePath: worktreePath)
        newSpace.name = branchName
        newSpace.defaultWorkingDirectory = worktreeURL
        newSpace.worktreePath = worktreeURL
        Log.worktree.info("Created worktree Space '\(branchName)' (id: \(newSpace.id))")

        // Step 11: (removed) Setup no longer runs in the interactive pane, so
        // waiting for shell readiness here is unnecessary. Layout `.pane` commands
        // still wait for readiness inline before typing.
        //
        // v4 space-sections: the Terminal section starts empty on a fresh
        // Space, so `activeTab` (which aliases the Terminal section) would
        // be nil. `showTerminal()` is a no-op for visibility and spawns the
        // first Terminal tab when empty; after this the activeTab force-
        // unwraps are safe.
        newSpace.showTerminal()
        let initialPaneID = newSpace.activeTab!.paneViewModel.splitTree.focusedPaneID
        let paneViewModel = newSpace.activeTab!.paneViewModel

        // Step 12: Run setup commands as background processes (FR-012)
        if !config.setupCommands.isEmpty {
            setupProgress = SetupProgress.starting(
                workspaceID: targetWorkspace.id,
                spaceID: newSpace.id,
                phase: .setup,
                totalCommands: config.setupCommands.count
            )
        }
        do {
            defer { setupProgress = nil }
            await runShellCommands(
                commands: config.setupCommands,
                label: "setup",
                worktreePath: worktreePath,
                config: config
            )
        }
        // setupProgress is now guaranteed nil; layout runs cleanly below.

        // Step 13: Apply layout (FR-013, FR-032)
        if let layout = config.layout {
            await applyLayout(
                node: layout,
                currentPaneID: initialPaneID,
                paneViewModel: paneViewModel,
                config: config,
                initialPaneID: initialPaneID
            )
            Log.worktree.info("Applied layout with \(layout.paneCount) panes")
        }

        // Step 15: Return result
        return WorktreeCreateResult(spaceID: newSpace.id, existed: false)
    }

    // MARK: - Shell Commands

    /// Runs an ordered list of shell commands sequentially with the
    /// worktree as cwd. Drives both `[[setup]]` (during creation) and
    /// `[[archive]]` (during removal). Failures are logged and the loop
    /// continues; the only early exit is user cancellation via Ctrl+C.
    /// `label` is interpolated into log lines so the two flows are
    /// distinguishable in `tian.log`.
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
            // Coalesce two @Observable notifications into one per command.
            if label == "setup", var snapshot = setupProgress {
                snapshot.currentIndex = index
                snapshot.currentCommand = command
                setupProgress = snapshot
            }
            Log.worktree.info("Running \(label) command \(index + 1)/\(commands.count): \(command)")
            let exit = await runShellCommand(
                command,
                label: label,
                worktreePath: worktreePath,
                timeout: config.setupTimeout,
                killGrace: config.setupKillGrace
            )
            if label == "setup", exit != 0, setupProgress != nil {
                setupProgress?.lastFailedIndex = index
            }
        }
    }

    private func runShellCommand(
        _ command: String,
        label: String,
        worktreePath: String,
        timeout: TimeInterval,
        killGrace: TimeInterval
    ) async -> Int32 {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        return await Self.runCommandOffMain(
            command: command,
            label: label,
            shellPath: shellPath,
            worktreePath: worktreePath,
            timeout: timeout,
            killGrace: killGrace,
            onStarted: { [weak self] terminate in
                Task { @MainActor in self?.cancellationToken = terminate }
            },
            onEnded: { [weak self] in
                Task { @MainActor in self?.cancellationToken = nil }
            }
        )
    }

    // MARK: - Ctrl+C Monitor

    private func installCtrlCMonitor() {
        let targetWindow = NSApp.keyWindow
        ctrlCMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window === targetWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .control,
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                self?.cancelCommands()
                return nil
            }
            return event
        }
    }

    private func removeCtrlCMonitor() {
        if let monitor = ctrlCMonitor {
            NSEvent.removeMonitor(monitor)
            ctrlCMonitor = nil
        }
    }

    // MARK: - Layout Application

    /// Recursively applies a layout tree by performing incremental splits.
    ///
    /// Preserves the initial pane's terminal session (FR-032) by splitting
    /// from the existing pane rather than replacing the PaneViewModel.
    private func applyLayout(
        node: LayoutNode,
        currentPaneID: UUID,
        paneViewModel: PaneViewModel,
        config: WorktreeConfig,
        initialPaneID: UUID
    ) async {
        switch node {
        case .pane(let command):
            guard let command, let surface = paneViewModel.surface(for: currentPaneID) else { return }
            await ShellReadinessWaiter.waitForReady(
                surfaceID: surface.id, timeout: config.shellReadyDelay
            )
            surface.sendText(command)

        case .split(let direction, let ratio, let first, let second):
            // Split the current pane
            guard let newPaneID = paneViewModel.splitPane(
                direction: direction, targetPaneID: currentPaneID
            ) else { return }

            // Update ratio from default 0.5 to target
            if ratio != 0.5,
               let splitID = paneViewModel.splitTree.root.findDirectParentSplitID(of: newPaneID) {
                paneViewModel.updateRatio(splitID: splitID, newRatio: ratio)
            }

            await applyLayout(
                node: first,
                currentPaneID: currentPaneID,
                paneViewModel: paneViewModel,
                config: config,
                initialPaneID: initialPaneID
            )
            await applyLayout(
                node: second,
                currentPaneID: newPaneID,
                paneViewModel: paneViewModel,
                config: config,
                initialPaneID: initialPaneID
            )
        }
    }

    // MARK: - Private Helpers

    /// Resolves the target workspace by ID or from the key window.
    private func resolveWorkspace(workspaceID: UUID?) -> Workspace? {
        if let workspaceID {
            for collection in workspaceProvider.allWorkspaceCollections {
                if let workspace = collection.workspaces.first(where: { $0.id == workspaceID }) {
                    return workspace
                }
            }
            return nil
        }
        return workspaceProvider.activeWorkspaceForKeyWindow()
    }

    /// Parses the worktree config from the repo, falling back to defaults.
    private func parseConfig(repoRoot: String) -> WorktreeConfig {
        let repoURL = URL(filePath: repoRoot)
        guard let configURL = WorktreeService.resolveConfigFile(repoRoot: repoURL) else {
            let configPath = repoURL.appendingPathComponent(".tian").appendingPathComponent("config.toml").path
            Log.worktree.info("No .tian/config.toml found at \(configPath). Using defaults.")
            return WorktreeConfig()
        }
        do {
            return try WorktreeConfigParser.parse(fileURL: configURL)
        } catch {
            Log.worktree.warning("Failed to parse .tian/config.toml: \(error). Proceeding without config.")
            return WorktreeConfig()
        }
    }

    /// Iterates all workspaces across all windows, returning the first match.
    private func findInHierarchy<T>(
        _ body: (WorkspaceCollection, Workspace) -> T?
    ) -> T? {
        for collection in workspaceProvider.allWorkspaceCollections {
            for workspace in collection.workspaces {
                if let result = body(collection, workspace) { return result }
            }
        }
        return nil
    }

    private func findExistingSpace(worktreePath: URL) -> SpaceModel? {
        let needle = worktreePath.standardizedFileURL.path
        return findInHierarchy { _, workspace in
            workspace.spaceCollection.spaces.first {
                $0.worktreePath?.standardizedFileURL.path == needle
            }
        }
    }

    private func activateSpace(_ space: SpaceModel) {
        findInHierarchy { collection, workspace -> Void? in
            guard workspace.spaceCollection.spaces.contains(where: { $0.id == space.id }) else {
                return nil
            }
            collection.activateWorkspace(id: workspace.id)
            workspace.spaceCollection.activateSpace(id: space.id)
            return ()
        }
    }

    private func findSpace(id: UUID) -> (SpaceModel, SpaceCollection)? {
        findInHierarchy { _, workspace in
            workspace.spaceCollection.spaces
                .first(where: { $0.id == id })
                .map { ($0, workspace.spaceCollection) }
        }
    }

    /// Per-stream output cap. Anything beyond this is discarded and a
    /// truncation marker is appended to the final log line.
    nonisolated private static let outputBufferCap = 256 * 1024

    /// Runs a single shell command without touching the main actor.
    /// Drains pipes incrementally via `readabilityHandler` (no kernel-buffer
    /// deadlock) and routes every `kill()` through `KillGuard` (no signal
    /// to a recycled PID, automatic SIGKILL after `killGrace`).
    ///
    /// `onStarted` publishes a Sendable terminate-closure to the caller's
    /// actor; `onEnded` clears it.
    nonisolated private static func runCommandOffMain(
        command: String,
        label: String,
        shellPath: String,
        worktreePath: String,
        timeout: TimeInterval,
        killGrace: TimeInterval,
        onStarted: @Sendable (@Sendable @escaping () -> Void) -> Void,
        onEnded: @Sendable () -> Void
    ) async -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: shellPath)
        // -i so zsh sources ~/.zshrc — most users put dev-tool PATH (pnpm,
        // nvm, mise, …) there, not in ~/.zprofile. Without -i, `pnpm install`
        // and similar setup commands exit 127 (command not found).
        process.arguments = ["-l", "-i", "-c", command]
        process.currentDirectoryURL = URL(filePath: worktreePath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Redirect stdin to /dev/null so `-i` zsh doesn't block on read
        // (e.g. plugins gated on `[[ -t 0 ]]`, stale compinit prompts, or
        // shell integrations issuing terminal queries). /dev/null always
        // exists on macOS, so force-unwrap is safe.
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")!

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

        let killGuard = KillGuard(pid: process.processIdentifier)
        onStarted({ killGuard.terminate(grace: killGrace) })
        defer { onEnded() }

        let timeoutItem = DispatchWorkItem { killGuard.terminate(grace: killGrace) }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        // Single-resume gate: the terminationHandler and the post-assignment
        // `isRunning` check both race to claim it. Without this, a child that
        // reaps between `process.run()` and assigning the handler below would
        // hang the await — Foundation does not retroactively invoke a handler
        // assigned after the process has terminated.
        let resumed = ResumeOnce()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in
                if resumed.claim() {
                    // markDead() before resume(): any kill that lost the race
                    // (pending timeout, stale published closure) becomes a no-op.
                    killGuard.markDead()
                    continuation.resume()
                }
            }
            if !process.isRunning, resumed.claim() {
                killGuard.markDead()
                continuation.resume()
            }
        }
        timeoutItem.cancel()

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
            // Interactive shells routinely write success-path chatter to
            // stderr (gitstatusd, p10k, nvm, compinit). Only surface as a
            // warning when the command actually failed.
            if process.terminationStatus == 0 {
                Log.worktree.info("\(label) stderr: \(trimmedStderr)\(stderrSuffix)")
            } else {
                Log.worktree.warning("\(label) stderr: \(trimmedStderr)\(stderrSuffix)")
            }
        }
        Log.worktree.info("\(label.capitalized) command exit=\(process.terminationStatus): \(command)")

        return process.terminationStatus
    }
}

/// One-shot resume claim. Used to gate `CheckedContinuation.resume()`
/// when two code paths race to call it (e.g. `terminationHandler` and a
/// post-`process.run()` `isRunning` recheck).
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

