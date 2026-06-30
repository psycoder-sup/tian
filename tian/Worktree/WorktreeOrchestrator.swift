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

    /// True while a `removeWorktreeSpace` invocation is between its first
    /// line and its final cleanup. Concurrent removal of a *different*
    /// Space is rejected with `WorktreeError.closeInFlight`. Concurrent
    /// removal of the *same* Space is filtered out at the UI layer by
    /// `SidebarSpaceRowMutationGate` (which hides "Close Space" while
    /// `setupProgress != nil`).
    private(set) var isCloseInFlight: Bool = false

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
    ///   - base: Base git ref (branch/tag/commit) to create the new branch from. If nil,
    ///     the branch is created from current HEAD. Invalid when combined with `existingBranch`.
    ///   - repoPath: Absolute path to a directory inside the repo. If nil, derived from the active Space.
    ///   - workspaceID: Target workspace ID. If nil, uses the key window's active workspace.
    ///   - creatorSpaceID: The Space that requested this worktree (the calling pane's
    ///     Space). Recorded as the new Space's `parentSpaceID` so the sidebar nests it
    ///     under its orchestrator. Ignored when the creator lives in a different
    ///     workspace (sidebar is per-window). Capped at two levels in `continueCreation`.
    /// - Returns: Result containing the Space ID and whether an existing Space was focused.
    func createWorktreeSpace(
        branchName: String,
        existingBranch: Bool = false,
        remoteRef: String? = nil,
        base: String? = nil,
        repoPath: String? = nil,
        workspaceID: UUID? = nil,
        background: Bool = false,
        creatorSpaceID: UUID? = nil
    ) async throws -> WorktreeCreateResult {
        commandsCancelled = false

        // `--base` selects the start point for a *new* branch. Checking out an
        // existing branch uses that branch's own tip, so a base is meaningless
        // there — reject the combination rather than silently ignoring it.
        if existingBranch, base != nil {
            throw WorktreeError.baseWithExisting
        }

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
            let disposition = background ? "leaving it in the background" : "focusing it"
            Log.worktree.info("Worktree Space already exists for \(expectedPath.path); \(disposition) (Space \(existingSpace.id))")
            if !background {
                activateSpace(existingSpace)
            }
            return WorktreeCreateResult(
                spaceID: existingSpace.id,
                existed: true,
                tabID: existingSpace.activeTab?.id,
                paneID: existingSpace.activeTab?.paneViewModel.splitTree.focusedPaneID,
                claudeTabID: existingSpace.claudeSection.activeTab?.id,
                claudePaneID: existingSpace.claudeSection.activeTab?.paneViewModel.splitTree.focusedPaneID
            )
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
        // When a base ref is given (new-branch path), verify it resolves before
        // `git worktree add` so the failure is a clear message instead of a raw
        // git error.
        if let base {
            let resolves = try await WorktreeService.refExists(repoRoot: repoRoot, ref: base)
            if !resolves {
                throw WorktreeError.invalidBaseRef(ref: base)
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
            remoteRef: remoteRef,
            base: base
        )

        // Steps 7-15 are wrapped so the on-disk worktree is cleaned up on failure.
        do {
            return try await continueCreation(
                worktreePath: worktreePath,
                repoRoot: repoRoot,
                branchName: branchName,
                config: config,
                targetWorkspace: targetWorkspace,
                background: background,
                creatorSpaceID: creatorSpaceID
            )
        } catch {
            try? await WorktreeService.removeWorktree(
                repoRoot: repoRoot, worktreePath: worktreePath, force: true
            )
            throw error
        }
    }

    // MARK: - Claude Worktree Engine

    /// Creates a Space whose first Claude pane runs `claude --worktree`, then
    /// detects the worktree Claude created and binds the Space to it.
    ///
    /// Unlike `createWorktreeSpace` (tian's own `git worktree add` engine), tian
    /// neither picks the name nor runs git here: it launches plain
    /// `claude --worktree` (cwd = repo root) and polls `git worktree list` until
    /// a new `<repo>/.claude/worktrees/<name>` entry appears, then renames the
    /// Space and binds `defaultWorkingDirectory`/`worktreePath` from the detected
    /// path. Because `claude --worktree` registers that dir as a git worktree,
    /// git auto-ignores it — so this path skips the gitignore/copy/setup/layout
    /// work `createWorktreeSpace` does (it is intentionally lighter).
    ///
    /// - Parameters:
    ///   - repoPath: Absolute path to a directory inside the repo.
    ///   - workspaceID: Target workspace ID. If nil, uses the key window's active workspace.
    ///   - creatorSpaceID: The Space that requested this worktree, recorded as the
    ///     new Space's `parentSpaceID` (two-level cap; same rule as `createWorktreeSpace`).
    /// - Returns: Result with the created Space/pane IDs.
    @discardableResult
    func createClaudeWorktreeSpace(
        repoPath: String,
        workspaceID: UUID? = nil,
        creatorSpaceID: UUID? = nil
    ) async throws -> WorktreeCreateResult {
        // Step 1: Resolve workspace + git repo root.
        guard let targetWorkspace = resolveWorkspace(workspaceID: workspaceID)
            ?? resolveWorkspace(workspaceID: nil) else {
            throw WorktreeError.gitError(
                command: "claude --worktree",
                stderr: "No workspace available to create Space in"
            )
        }
        let repoRoot = try await WorktreeService.resolveRepoRoot(from: repoPath)
        Log.worktree.info("claude --worktree: resolved git repo root \(repoRoot)")

        // Step 2: Snapshot existing worktrees so the new one can be detected by
        // diffing against this set.
        let before = Set(try await WorktreeService.listWorktrees(repoRoot: repoRoot).map(\.path))

        // Step 3: Create the Space and override its seeded Claude pane to run
        // `claude --worktree` (cwd = repo root). Applied synchronously — no
        // `await` between createSpace and applyCustomLaunchCommand — so the
        // override lands before SwiftUI attaches the surface (the autostart env
        // is read once at spawn), the same timing guarantee
        // `createTab(customCommand:)` relies on.
        let claudeWorktreeCommand = "claude --worktree"
        let space = targetWorkspace.spaceCollection.createSpace(
            name: "Creating worktree…",
            workingDirectory: repoRoot,
            focusOnCreate: true
        )
        guard let claudeTab = space.claudeSection.activeTab else {
            throw WorktreeError.gitError(
                command: "claude --worktree",
                stderr: "New Space has no Claude tab to launch claude --worktree in"
            )
        }
        let paneViewModel = claudeTab.paneViewModel
        let paneID = paneViewModel.splitTree.focusedPaneID
        paneViewModel.applyCustomLaunchCommand(claudeWorktreeCommand, toPaneID: paneID)
        claudeTab.launchCommand = claudeWorktreeCommand
        space.defaultWorkingDirectory = URL(filePath: repoRoot)   // until detection rebinds it

        // Record the orchestrator → implementer link (two-level cap; same rule
        // as `continueCreation`). Resolve the creator within targetWorkspace only.
        if let creatorSpaceID,
           let creator = targetWorkspace.spaceCollection.spaces.first(where: { $0.id == creatorSpaceID }) {
            space.parentSpaceID = creator.parentSpaceID ?? creator.id
        }
        Log.worktree.info("claude --worktree: created Space \(space.id); awaiting worktree detection")

        // Step 4: Poll `git worktree list` until Claude's new worktree appears.
        let detected = await detectClaudeWorktree(repoRoot: repoRoot, before: before)

        // Step 5: Bind the Space to the detected worktree, or fall back on timeout.
        if let detected {
            let url = URL(filePath: detected)
            space.name = url.lastPathComponent
            space.defaultWorkingDirectory = url
            space.worktreePath = url
            // Reset the pane's launch override so a future restart/restore runs
            // plain `claude`, never spawning a *second* worktree. Safe to do only
            // now: detection succeeding implies the pane already spawned with
            // `claude --worktree` (the worktree only exists once that command ran),
            // so this can't suppress the original creation.
            paneViewModel.applyCustomLaunchCommand(SectionSpawner.claudeAutostartCommand, toPaneID: paneID)
            claudeTab.launchCommand = SectionSpawner.claudeAutostartCommand
            Log.worktree.info("claude --worktree: detected \(detected); bound Space \(space.id) (name: \(url.lastPathComponent))")
        } else {
            // Claude is still running — leave the Space in place but give it a
            // real name. The pane keeps its `claude --worktree` override: we
            // can't prove a worktree was created, so resetting it could be wrong.
            space.name = "worktree"
            Log.worktree.warning("claude --worktree: timed out waiting for a worktree under \(repoRoot)/.claude/worktrees; leaving Space \(space.id) running")
        }

        return WorktreeCreateResult(
            spaceID: space.id,
            existed: false,
            tabID: space.activeTab?.id,
            paneID: space.activeTab?.paneViewModel.splitTree.focusedPaneID,
            claudeTabID: claudeTab.id,
            claudePaneID: paneID
        )
    }

    /// Polls `git worktree list` until a worktree under
    /// `<repoRoot>/.claude/worktrees/` that wasn't in `before` appears. App-side
    /// code (not a shell command), so `Task.sleep` is fine. Returns the detected
    /// absolute path, or `nil` after the ceiling elapses.
    private func detectClaudeWorktree(repoRoot: String, before: Set<String>) async -> String? {
        let pollInterval: Duration = .milliseconds(400)
        let maxAttempts = 112   // ~45 s at 400 ms per attempt
        let marker = "/.claude/worktrees/"
        for _ in 0..<maxAttempts {
            try? await Task.sleep(for: pollInterval)
            guard let entries = try? await WorktreeService.listWorktrees(repoRoot: repoRoot) else {
                continue
            }
            if let match = entries.first(where: {
                !before.contains($0.path) && $0.path.contains(marker)
            }) {
                return match.path
            }
        }
        return nil
    }

    // MARK: - Cleanup Flow

    /// Removes a worktree-backed Space and its git worktree.
    ///
    /// - Parameters:
    ///   - spaceID: The ID of the Space to remove.
    ///   - force: If true, forces removal even with uncommitted changes.
    ///   - workspaceID: Hint for which workspace to search. If nil, searches all.
    ///   - deleteBranch: If true, deletes the branch backing the worktree after
    ///     the worktree is removed (`git branch -d`, or `-D` with `force`). An
    ///     unmerged branch is kept (the worktree — the primary action — already
    ///     succeeded); see `WorktreeRemovalResult`.
    @discardableResult
    func removeWorktreeSpace(
        spaceID: UUID,
        force: Bool = false,
        workspaceID: UUID? = nil,
        deleteBranch: Bool = false
    ) async throws -> WorktreeRemovalResult {
        // In-flight guard (FR-061): reject concurrent close requests for
        // a *different* Space. Same-Space double-close is prevented at
        // the UI layer by `SidebarSpaceRowMutationGate`.
        if isCloseInFlight {
            throw WorktreeError.closeInFlight
        }
        isCloseInFlight = true

        commandsCancelled = false

        // Synchronous nil-out covers ALL exit paths (success, archive
        // failure, cancel, throw). Pairs with the explicit pre-throw
        // nil-out in the uncommitted-changes branch (FR-053): even
        // though `defer` fires before the throw is observed by the
        // caller, the explicit pre-throw assignment guarantees the
        // ordering on the @MainActor with respect to any subsequent
        // alert presentation.
        defer {
            isCloseInFlight = false
            setupProgress = nil
        }

        // Step 1: Find Space
        guard let (space, spaceCollection) = findSpace(id: spaceID) else { return .none }

        // Step 2: Check worktreePath
        guard let worktreeURL = space.worktreePath else {
            // Not a worktree Space — just close it
            spaceCollection.removeSpace(id: spaceID)
            return .none
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

        // Resolve the workspace ID for progress publishing. The Space lives
        // in some workspace's collection; find it so the sidebar row picks
        // up `setupProgress`.
        let resolvedWorkspaceID: UUID? = findInHierarchy { _, workspace in
            workspace.spaceCollection.spaces.contains(where: { $0.id == spaceID })
                ? workspace.id
                : nil
        }

        // Step 4.5: Run archive commands (inverse of [[setup]]). Must happen
        // while the worktree directory still exists so commands can `cd`
        // into it (e.g. `docker compose down`).
        if !config.archiveCommands.isEmpty, let wsID = resolvedWorkspaceID {
            setupProgress = SetupProgress.starting(
                workspaceID: wsID,
                spaceID: spaceID,
                phase: .cleanup,
                totalCommands: config.archiveCommands.count
            )
            await runShellCommands(
                commands: config.archiveCommands,
                label: "archive",
                worktreePath: worktreePath,
                config: config,
                haltOnFirstFailure: true
            )
            // Halt the cleanup pipeline before `git worktree remove` if
            // the user cancelled (FR-040, FR-041) or any archive command
            // exited non-zero (FR-050). The defer nils setupProgress.
            if commandsCancelled {
                Log.worktree.info("Archive cancelled by user; preserving worktree at \(worktreePath)")
                return .none
            }
            if setupProgress?.didFailRun == true {
                Log.worktree.warning("Archive failed; preserving worktree at \(worktreePath)")
                return .none
            }
        }

        // Pre-remove transition: brief "Removing..." snapshot covers
        // `git worktree remove` + pruning even when no archive ran (FR-012).
        if let wsID = resolvedWorkspaceID {
            setupProgress = SetupProgress.removingPlaceholder(
                workspaceID: wsID,
                spaceID: spaceID
            )
        }

        // Resolve the branch checked out in the worktree *before* removal —
        // `git symbolic-ref` reads the worktree directory, gone afterward.
        // Only when deletion is requested, to avoid an extra git call on the
        // common (UI) close path. A `nil` result means detached HEAD (or a
        // transient git error): there is no branch this worktree clearly owns,
        // so we skip deletion rather than guess from the user-renamable Space
        // name and risk deleting an unrelated branch (e.g. a Space renamed to
        // "main").
        let branchToDelete: String? = deleteBranch
            ? (try? await WorktreeService.currentBranch(worktreePath: worktreePath))
            : nil

        // Step 5: Remove worktree. If this throws (e.g. uncommitted
        // changes), nil setupProgress synchronously *before* the throw
        // so the modal alert never overlaps the progress capsule (FR-053).
        do {
            try await WorktreeService.removeWorktree(
                repoRoot: mainRepoRoot,
                worktreePath: worktreePath,
                force: force
            )
        } catch {
            setupProgress = nil
            throw error
        }

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

        // Step 7: Delete the branch (best-effort follow-up). The worktree —
        // the primary action — already succeeded, so a kept/failed branch is
        // reported, never thrown. An unmerged branch is kept unless `force`
        // upgraded the delete to `git branch -D`.
        guard deleteBranch else { return .none }
        guard let branch = branchToDelete else {
            Log.worktree.info("Branch deletion requested but worktree had no branch checked out (detached HEAD); skipping branch delete")
            // Distinct from `.none` (deletion not requested / removal preempted)
            // so the CLI can tell the user the branch was skipped, not deleted.
            return WorktreeRemovalResult(
                branchName: nil, branchDeleted: false, branchKeptReason: "no branch"
            )
        }
        do {
            let outcome = try await WorktreeService.deleteBranch(
                repoRoot: mainRepoRoot, branchName: branch, force: force
            )
            switch outcome {
            case .deleted:
                return WorktreeRemovalResult(
                    branchName: branch, branchDeleted: true, branchKeptReason: nil
                )
            case .keptUnmerged:
                Log.worktree.warning("Kept branch '\(branch)' after removing worktree: not fully merged (re-run with --force to delete)")
                return WorktreeRemovalResult(
                    branchName: branch, branchDeleted: false, branchKeptReason: "unmerged"
                )
            case .notFound:
                return WorktreeRemovalResult(
                    branchName: branch, branchDeleted: false, branchKeptReason: "not found"
                )
            }
        } catch {
            Log.worktree.warning("Failed to delete branch '\(branch)': \(error)")
            return WorktreeRemovalResult(
                branchName: branch, branchDeleted: false, branchKeptReason: "error"
            )
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
        targetWorkspace: Workspace?,
        background: Bool,
        creatorSpaceID: UUID? = nil
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
            workingDirectory: worktreePath,
            focusOnCreate: !background
        )
        let worktreeURL = URL(filePath: worktreePath)
        newSpace.name = branchName
        newSpace.defaultWorkingDirectory = worktreeURL
        newSpace.worktreePath = worktreeURL

        // Record the orchestrator → implementer link so the sidebar nests this
        // Space under its creator. Resolve the creator *within targetWorkspace*
        // only — the sidebar is per-window, so a cross-workspace creator leaves
        // parentSpaceID nil (top-level). Two-level cap: if the creator is itself
        // an implementer (has a parentSpaceID), attach to its parent (the top
        // orchestrator) rather than the creator, so we never nest 3 deep.
        if let creatorSpaceID,
           let creator = targetWorkspace.spaceCollection.spaces.first(where: { $0.id == creatorSpaceID }) {
            newSpace.parentSpaceID = creator.parentSpaceID ?? creator.id
        }
        Log.worktree.info("Created worktree Space '\(branchName)' (id: \(newSpace.id), parent: \(newSpace.parentSpaceID?.uuidString ?? "none"))")

        // Step 11: (removed) Setup no longer runs in the interactive pane, so
        // waiting for shell readiness here is unnecessary. Layout `.pane` commands
        // still wait for readiness inline before typing.
        //
        // v4 space-sections: the Terminal section starts empty on a fresh
        // Space, so `activeTab` (which aliases the Terminal section) would
        // be nil. `showTerminal()` is a no-op for visibility and spawns the
        // first Terminal tab when empty; after this the activeTab force-
        // unwraps are safe.
        newSpace.showTerminal(background: background)
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
        return WorktreeCreateResult(
            spaceID: newSpace.id,
            existed: false,
            tabID: newSpace.activeTab?.id,
            paneID: initialPaneID,
            claudeTabID: newSpace.claudeSection.activeTab?.id,
            claudePaneID: newSpace.claudeSection.activeTab?.paneViewModel.splitTree.focusedPaneID
        )
    }

    // MARK: - Shell Commands

    /// Runs an ordered list of shell commands sequentially with the
    /// worktree as cwd. Drives both `[[setup]]` (during creation) and
    /// `[[archive]]` (during removal). `label` is interpolated into log
    /// lines so the two flows are distinguishable in `tian.log`.
    ///
    /// - Parameters:
    ///   - haltOnFirstFailure: When `true`, the loop breaks immediately after
    ///     the first non-zero exit (used by the archive/cleanup path so the
    ///     worktree is preserved on disk). When `false` (default), the loop
    ///     continues past failures so subsequent independent steps still run.
    private func runShellCommands(
        commands: [String],
        label: String,
        worktreePath: String,
        config: WorktreeConfig,
        haltOnFirstFailure: Bool = false
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
            // Generalized from a `label == "setup"` guard to "publish whenever
            // setupProgress is non-nil" so [[archive]] runs drive the same UI.
            if var snapshot = setupProgress {
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
            if exit != 0, setupProgress != nil {
                setupProgress?.lastFailedIndex = index
                if haltOnFirstFailure {
                    // Halt on first failure (FR-050) — preserve the worktree
                    // on disk by short-circuiting the loop. Downstream UI
                    // surfaces the failure via `didFailRun`.
                    Log.worktree.warning("\(label.capitalized) command \(index + 1)/\(commands.count) failed (exit=\(exit)); halting pipeline")
                    break
                }
                // Otherwise continue: subsequent independent steps still run;
                // downstream UI surfaces the failure via `didFailRun`.
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

