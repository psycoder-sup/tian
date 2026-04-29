import AppKit

/// Shared close-Space presentation flow used by sidebar views.
///
/// Encapsulates the full dialog chain for worktree-backed Spaces:
/// `WorktreeCloseDialog` → optional `SkipTeardownConfirmationDialog` (Close Only
/// path) → `WorktreeForceRemoveDialog` (Remove Worktree path). Extracted to avoid
/// duplicating this logic across multiple sidebar views.
@MainActor
enum SpaceCloseFlow {

    /// Presents the close-Space dialog chain and performs the chosen action.
    ///
    /// - Parameters:
    ///   - space: The Space to close.
    ///   - workspace: The workspace that owns the Space.
    ///   - worktreeOrchestrator: Orchestrator used for worktree removal.
    static func run(
        space: SpaceModel,
        in workspace: Workspace,
        worktreeOrchestrator: WorktreeOrchestrator
    ) {
        guard let wtPath = space.worktreePath else {
            workspace.spaceCollection.removeSpace(id: space.id)
            return
        }
        guard let window = NSApp.keyWindow else { return }
        WorktreeCloseDialog.show(on: window, worktreePath: wtPath.path) { response in
            switch response {
            case .removeWorktreeAndClose:
                Task { await removeWorktree(space: space, force: false, worktreeOrchestrator: worktreeOrchestrator) }
            case .closeOnly:
                Task { await handleCloseOnly(space: space, workspace: workspace, wtPath: wtPath, window: window) }
            case .cancel:
                break
            }
        }
    }

    // MARK: - Private

    /// Handles the "Close Only" branch: resolves the main worktree root via the
    /// same `resolveMainWorktreePath` call the orchestrator uses (so the
    /// archive-command count matches what would actually run), then optionally
    /// prompts the user to confirm skipping teardown before removing the Space.
    private static func handleCloseOnly(
        space: SpaceModel,
        workspace: Workspace,
        wtPath: URL,
        window: NSWindow
    ) async {
        // Resolve repo root the same way WorktreeOrchestrator.removeWorktreeSpace
        // does: linked-root → main-root via `git worktree list --porcelain`.
        let mainRepoRoot: String
        if let linkedRoot = try? await WorktreeService.resolveRepoRoot(from: wtPath.path) {
            mainRepoRoot = (try? await WorktreeService.resolveMainWorktreePath(repoRoot: linkedRoot))
                ?? linkedRoot
        } else {
            // Fallback: use the workspace's default directory if available,
            // otherwise the linked worktree path. The archive count may be
            // inaccurate if .tian/config.toml differs between branches, but
            // this path is only reached when git commands fail entirely.
            mainRepoRoot = workspace.defaultWorkingDirectory?.path ?? wtPath.path
        }

        // Guard: the workspace window may have been closed during the two awaits
        // above (resolveRepoRoot / resolveMainWorktreePath). If windowShouldClose
        // already tore down the SpaceCollection, bail out to avoid operating on
        // stale state or triggering double-cleanup.
        guard workspace.spaceCollection.spaces.contains(where: { $0.id == space.id }) else { return }

        let archiveCount = WorktreeService.archiveCommandCount(repoRoot: mainRepoRoot)
        if archiveCount > 0 {
            SkipTeardownConfirmationDialog.show(
                on: window,
                archiveCommandCount: archiveCount
            ) { skipResponse in
                if skipResponse == .skipTeardown {
                    workspace.spaceCollection.removeSpace(id: space.id)
                }
            }
        } else {
            workspace.spaceCollection.removeSpace(id: space.id)
        }
    }

    /// Attempts worktree removal via the orchestrator; re-prompts on
    /// uncommitted-changes error.
    private static func removeWorktree(
        space: SpaceModel,
        force: Bool,
        worktreeOrchestrator: WorktreeOrchestrator
    ) async {
        do {
            try await worktreeOrchestrator.removeWorktreeSpace(
                spaceID: space.id, force: force
            )
        } catch let error as WorktreeError {
            if case .uncommittedChanges(let path) = error, let window = NSApp.keyWindow {
                WorktreeForceRemoveDialog.show(on: window, worktreePath: path) { response in
                    if response == .forceRemove {
                        Task { await removeWorktree(space: space, force: true, worktreeOrchestrator: worktreeOrchestrator) }
                    }
                }
            } else {
                worktreeOrchestrator.presentError(error)
            }
        } catch {
            worktreeOrchestrator.presentError(error)
        }
    }
}
