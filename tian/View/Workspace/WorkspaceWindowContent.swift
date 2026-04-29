import SwiftUI

struct WorkspaceWindowContent: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator

    @State private var showDebugOverlay = false
    @State private var createSpaceRequest: CreateSpaceRequest?
    @State private var pendingResolveTask: Task<Void, Never>?
    /// Tracks the capsule's *displayed* progress, distinct from the
    /// orchestrator's source-of-truth `setupProgress`. When a run ends with
    /// a recorded failure, we hold this for `setupCapsuleLingerSeconds` so
    /// the failure indication is observable before the capsule disappears.
    @State private var displayedProgress: SetupProgress?
    @State private var lingerTask: Task<Void, Never>?

    private static let setupCapsuleLingerSeconds: Duration = .seconds(3)

    var body: some View {
        ZStack(alignment: .bottom) {
            StatusBarView()

            ZStack(alignment: .bottomTrailing) {
                SidebarContainerView(
                    workspaceCollection: workspaceCollection,
                    worktreeOrchestrator: worktreeOrchestrator,
                    bottomContentInset: StatusBarView.height
                )

                if let progress = displayedProgress {
                    SetupProgressCapsule(progress: progress) {
                        worktreeOrchestrator.cancelCommands()
                    }
                    .padding(12)
                    .transition(.opacity)
                }

                if showDebugOverlay {
                    DebugOverlayView()
                        .padding(12)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
        .overlay {
            if let req = createSpaceRequest, let workspace = req.workspace {
                CreateSpaceView(
                    workspace: workspace,
                    repoRoot: req.repoRoot,
                    worktreeDir: req.worktreeDir,
                    onSubmitPlain: { name in
                        let captured = req
                        createSpaceRequest = nil
                        let wd = captured.workspace?.spaceCollection.resolveWorkingDirectory() ?? "~"
                        captured.workspace?.spaceCollection.createSpace(
                            name: name,
                            workingDirectory: wd
                        )
                    },
                    onSubmitWorktree: { submission in
                        let captured = req
                        createSpaceRequest = nil
                        guard let repoRoot = captured.repoRoot else { return }
                        Task {
                            do {
                                _ = try await worktreeOrchestrator.createWorktreeSpace(
                                    branchName: submission.branchName,
                                    existingBranch: submission.existingBranch,
                                    remoteRef: submission.remoteRef,
                                    repoPath: repoRoot.path,
                                    workspaceID: captured.workspace?.id
                                )
                            } catch {
                                worktreeOrchestrator.presentError(error)
                            }
                        }
                    },
                    onCancel: {
                        pendingResolveTask?.cancel()
                        pendingResolveTask = nil
                        createSpaceRequest = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .alert(
            "Worktree error",
            isPresented: Binding(
                get: { worktreeOrchestrator.lastError != nil },
                set: { if !$0 { worktreeOrchestrator.lastError = nil } }
            ),
            presenting: worktreeOrchestrator.lastError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { err in
            Text(String(describing: err))   // WorktreeError conforms to CustomStringConvertible
        }
        .animation(.easeInOut(duration: 0.15), value: showDebugOverlay)
        .animation(.easeInOut(duration: 0.15), value: createSpaceRequest != nil)
        .animation(.easeInOut(duration: 0.15), value: displayedProgress != nil)
        .onChange(of: worktreeOrchestrator.setupProgress) { _, new in
            if let new {
                lingerTask?.cancel()
                lingerTask = nil
                displayedProgress = new
            } else if let prev = displayedProgress, prev.didFailRun {
                // Hold the capsule with its failure glyph visible briefly so
                // the user can register that something went wrong.
                lingerTask?.cancel()
                lingerTask = Task { @MainActor in
                    try? await Task.sleep(for: Self.setupCapsuleLingerSeconds)
                    if !Task.isCancelled {
                        displayedProgress = nil
                    }
                }
            } else {
                lingerTask?.cancel()
                lingerTask = nil
                displayedProgress = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleDebugOverlay)) { notification in
            guard let obj = notification.object as? WorkspaceCollection,
                  obj === workspaceCollection else { return }
            showDebugOverlay.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCreateSpaceInput)) { notification in
            guard let obj = notification.object as? WorkspaceCollection,
                  obj === workspaceCollection else { return }
            let workspaceID = notification.userInfo?[Notification.createSpaceWorkspaceIDKey] as? UUID
            let workspace: Workspace? = {
                if let id = workspaceID,
                   let ws = workspaceCollection.workspaces.first(where: { $0.id == id }) {
                    return ws
                }
                return workspaceCollection.activeWorkspace
            }()
            guard let workspace else { return }
            let wd = workspace.spaceCollection.resolveWorkingDirectory()
            // Rapid repeat triggers (⇧⌘T held, or ⇧⌘T after clicking +) used to
            // spawn overlapping resolutions; the last to finish would re-open
            // the modal even if the user had already cancelled an earlier one.
            // Cancel the in-flight resolution and replace it.
            pendingResolveTask?.cancel()
            pendingResolveTask = Task {
                let repoURL: URL?
                let configRepo: URL
                if let repoRootPath = try? await WorktreeService.resolveRepoRoot(from: wd) {
                    let url = URL(filePath: repoRootPath)
                    repoURL = url
                    configRepo = url
                } else {
                    repoURL = nil
                    configRepo = URL(filePath: wd.isEmpty ? NSHomeDirectory() : wd)
                }
                if Task.isCancelled { return }
                let configURL = WorktreeService.resolveConfigFile(repoRoot: configRepo)
                let config: WorktreeConfig
                if let configURL, let parsed = try? WorktreeConfigParser.parse(fileURL: configURL) {
                    config = parsed
                } else {
                    config = WorktreeConfig()
                }
                if Task.isCancelled { return }
                createSpaceRequest = CreateSpaceRequest(
                    workspace: workspace,
                    repoRoot: repoURL,
                    worktreeDir: config.worktreeDir
                )
                // Intentionally do NOT clear `pendingResolveTask` here: holding
                // a handle to a completed task is harmless, and clearing it
                // unconditionally would risk nil'ing a newer in-flight task if
                // another trigger replaced it between our last cancellation
                // check and this assignment.
            }
        }
    }
}

// MARK: - Create Space Request

private struct CreateSpaceRequest: Equatable {
    weak var workspace: Workspace?
    let repoRoot: URL?
    let worktreeDir: String

    static func == (lhs: CreateSpaceRequest, rhs: CreateSpaceRequest) -> Bool {
        lhs.workspace?.id == rhs.workspace?.id
            && lhs.repoRoot == rhs.repoRoot
            && lhs.worktreeDir == rhs.worktreeDir
    }
}
