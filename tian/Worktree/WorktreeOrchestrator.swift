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

    /// Currently running shell process (setup or archive), if any.
    /// Used for cancellation/timeout.
    private var currentCommandProcess: Process?

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

    /// Cancels the in-flight shell command loop (setup or archive).
    /// Wired to both the SetupCancelButton and the Ctrl+C monitor.
    func cancelCommands() {
        commandsCancelled = true
        currentCommandProcess?.terminate()
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
            Log.worktree.info("Running \(label) command \(index + 1)/\(commands.count): \(command)")
            await runShellCommand(
                command,
                label: label,
                worktreePath: worktreePath,
                timeout: config.setupTimeout
            )
        }
    }

    private func runShellCommand(
        _ command: String,
        label: String,
        worktreePath: String,
        timeout: TimeInterval
    ) async {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
        let process = Process()
        process.executableURL = URL(filePath: shellPath)
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(filePath: worktreePath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        currentCommandProcess = process
        defer { currentCommandProcess = nil }

        do {
            try process.run()
        } catch {
            Log.worktree.warning("Failed to launch \(label) command '\(command)': \(error.localizedDescription)")
            return
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if process.isRunning {
                Log.worktree.warning("\(label.capitalized) command timed out after \(timeout)s, terminating: \(command)")
                process.terminate()
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        timeoutTask.cancel()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStdout.isEmpty {
            Log.worktree.info("\(label) stdout: \(trimmedStdout)")
        }
        if !trimmedStderr.isEmpty {
            Log.worktree.warning("\(label) stderr: \(trimmedStderr)")
        }
        Log.worktree.info("\(label.capitalized) command exit=\(process.terminationStatus): \(command)")
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
}
