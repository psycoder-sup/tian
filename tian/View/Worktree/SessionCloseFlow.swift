import AppKit

/// Shared close-Session presentation flow used by sidebar views.
///
/// Encapsulates the full dialog chain for worktree-backed Sessions:
/// `WorktreeCloseDialog` → optional `SkipTeardownConfirmationDialog` (Close Only
/// path) → `WorktreeForceRemoveDialog` (Remove Worktree path). Extracted to avoid
/// duplicating this logic across multiple sidebar views.
@MainActor
enum SessionCloseFlow {

    /// Presents the close-Session dialog chain and performs the chosen action.
    ///
    /// - Parameters:
    ///   - session: The Session to close.
    ///   - workspace: The workspace that owns the Session.
    ///   - worktreeOrchestrator: Orchestrator used for worktree removal.
    static func run(
        session: Session,
        in workspace: Workspace,
        worktreeOrchestrator: WorktreeOrchestrator
    ) {
        guard let wtPath = session.worktreePath else {
            workspace.sessionCollection.removeSession(id: session.id)
            return
        }
        guard let window = NSApp.keyWindow else { return }
        WorktreeCloseDialog.show(on: window, worktreePath: wtPath.path) { response in
            switch response {
            case .removeWorktreeAndClose:
                Task { await removeWorktree(session: session, force: false, worktreeOrchestrator: worktreeOrchestrator) }
            case .closeOnly:
                Task { await handleCloseOnly(session: session, workspace: workspace, wtPath: wtPath, window: window) }
            case .cancel:
                break
            }
        }
    }

    // MARK: - Private

    /// Handles the "Close Only" branch: resolves the main worktree root via the
    /// same `resolveMainWorktreePath` call the orchestrator uses (so the
    /// archive-command count matches what would actually run), then optionally
    /// prompts the user to confirm skipping teardown before removing the Session.
    private static func handleCloseOnly(
        session: Session,
        workspace: Workspace,
        wtPath: URL,
        window: NSWindow
    ) async {
        // Resolve repo root the same way WorktreeOrchestrator.removeWorktreeSession
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
        // already tore down the SessionCollection, bail out to avoid operating on
        // stale state or triggering double-cleanup.
        guard workspace.sessionCollection.sessions.contains(where: { $0.id == session.id }) else { return }

        let archiveCount = WorktreeService.archiveCommandCount(repoRoot: mainRepoRoot)
        if archiveCount > 0 {
            SkipTeardownConfirmationDialog.show(
                on: window,
                archiveCommandCount: archiveCount
            ) { skipResponse in
                if skipResponse == .skipTeardown {
                    workspace.sessionCollection.removeSession(id: session.id)
                }
            }
        } else {
            workspace.sessionCollection.removeSession(id: session.id)
        }
    }

    /// Attempts worktree removal via the orchestrator; re-prompts on
    /// uncommitted-changes error.
    private static func removeWorktree(
        session: Session,
        force: Bool,
        worktreeOrchestrator: WorktreeOrchestrator
    ) async {
        do {
            try await worktreeOrchestrator.removeWorktreeSession(
                sessionID: session.id, force: force
            )
        } catch let error as WorktreeError {
            if case .uncommittedChanges(let path) = error, let window = NSApp.keyWindow {
                WorktreeForceRemoveDialog.show(on: window, worktreePath: path) { response in
                    if response == .forceRemove {
                        Task { await removeWorktree(session: session, force: true, worktreeOrchestrator: worktreeOrchestrator) }
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
