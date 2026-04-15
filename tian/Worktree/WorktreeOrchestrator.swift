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

    /// True during creation flow; drives sidebar progress indicator.
    var isCreating: Bool = false

    /// Set to true when the user cancels setup commands.
    var setupCancelled: Bool = false

    /// Last error surfaced by the orchestrator, for UI binding.
    var lastError: WorktreeError?

    /// Temporary event monitor for Ctrl+C during setup commands.
    private var ctrlCMonitor: Any?

    /// Currently running setup process, if any. Used for cancellation/timeout.
    private var currentSetupProcess: Process?

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
        setupCancelled = false

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

        // Step 5: Begin creation
        isCreating = true
        defer { isCreating = false }

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
        // Step 1: Find Space
        guard let (space, spaceCollection) = findSpace(id: spaceID) else { return }

        // Step 2: Check worktreePath
        guard let worktreeURL = space.worktreePath else {
            // Not a worktree Space — just close it
            spaceCollection.removeSpace(id: spaceID)
            return
        }
        let worktreePath = worktreeURL.path

        // Step 3: Resolve repo root
        let repoRoot = try await WorktreeService.resolveRepoRoot(from: worktreePath)

        // Step 4: Parse config for worktreeDir
        let config = parseConfig(repoRoot: repoRoot)

        // Step 5: Remove worktree
        try await WorktreeService.removeWorktree(
            repoRoot: repoRoot,
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
                repoRoot: repoRoot
            )
        } catch {
            Log.worktree.warning("Failed to prune empty parents: \(error)")
        }
    }

    // MARK: - Cancellation

    /// Cancels any in-progress setup commands.
    func cancelSetup() {
        setupCancelled = true
        currentSetupProcess?.terminate()
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
        let initialPaneID = newSpace.activeTab!.paneViewModel.splitTree.focusedPaneID
        let paneViewModel = newSpace.activeTab!.paneViewModel

        // Step 12: Run setup commands as background processes (FR-012)
        await runSetupCommands(
            commands: config.setupCommands,
            worktreePath: worktreePath,
            config: config
        )

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

    // MARK: - Setup Commands

    private func runSetupCommands(
        commands: [String],
        worktreePath: String,
        config: WorktreeConfig
    ) async {
        guard !commands.isEmpty else { return }
        installCtrlCMonitor()
        defer { removeCtrlCMonitor() }

        for (index, command) in commands.enumerated() {
            if setupCancelled {
                Log.worktree.info("Setup cancelled by user after \(index)/\(commands.count) commands")
                break
            }
            Log.worktree.info("Running setup command \(index + 1)/\(commands.count): \(command)")
            await runSetupCommand(
                command,
                worktreePath: worktreePath,
                timeout: config.setupTimeout
            )
        }
    }

    private func runSetupCommand(
        _ command: String,
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

        currentSetupProcess = process
        defer { currentSetupProcess = nil }

        do {
            try process.run()
        } catch {
            Log.worktree.warning("Failed to launch setup command '\(command)': \(error.localizedDescription)")
            return
        }

        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if process.isRunning {
                Log.worktree.warning("Setup command timed out after \(timeout)s, terminating: \(command)")
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
            Log.worktree.info("setup stdout: \(trimmedStdout)")
        }
        if !trimmedStderr.isEmpty {
            Log.worktree.warning("setup stderr: \(trimmedStderr)")
        }
        Log.worktree.info("Setup command exit=\(process.terminationStatus): \(command)")
    }

    // MARK: - Ctrl+C Monitor

    private func installCtrlCMonitor() {
        let targetWindow = NSApp.keyWindow
        ctrlCMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window === targetWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .control,
               event.charactersIgnoringModifiers?.lowercased() == "c" {
                self?.cancelSetup()
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
