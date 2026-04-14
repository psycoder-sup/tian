import SwiftUI

struct WorkspaceWindowContent: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator

    @State private var showDebugOverlay = false
    @State private var createSpaceRequest: CreateSpaceRequest?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SidebarContainerView(
                workspaceCollection: workspaceCollection,
                worktreeOrchestrator: worktreeOrchestrator
            )

            if worktreeOrchestrator.isCreating {
                SetupCancelButton { worktreeOrchestrator.cancelSetup() }
                    .padding(12)
                    .transition(.opacity)
            }

            if showDebugOverlay {
                DebugOverlayView()
                    .padding(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
                    onCancel: { createSpaceRequest = nil }
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
        .animation(.easeInOut(duration: 0.15), value: worktreeOrchestrator.isCreating)
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
            Task {
                let repoURL: URL?
                let configRepo: URL
                if let repoRootPath = try? await WorktreeService.resolveRepoRoot(from: wd) {
                    repoURL = URL(filePath: repoRootPath)
                    configRepo = repoURL!
                } else {
                    repoURL = nil
                    configRepo = URL(filePath: wd.isEmpty ? NSHomeDirectory() : wd)
                }
                let configURL = WorktreeService.resolveConfigFile(repoRoot: configRepo)
                let config: WorktreeConfig
                if let configURL, let parsed = try? WorktreeConfigParser.parse(fileURL: configURL) {
                    config = parsed
                } else {
                    config = WorktreeConfig()
                }
                createSpaceRequest = CreateSpaceRequest(
                    workspace: workspace,
                    repoRoot: repoURL,
                    worktreeDir: config.worktreeDir
                )
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
