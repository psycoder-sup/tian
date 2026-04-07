import SwiftUI

struct WorkspaceWindowContent: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator

    @State private var showDebugOverlay = false
    @State private var branchInputContext: BranchInputContext?

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
            if let ctx = branchInputContext {
                BranchNameInputView(
                    repoRoot: ctx.repoRoot,
                    worktreeDir: ctx.worktreeDir,
                    onSubmit: { branch, existing in
                        branchInputContext = nil
                        Task {
                            _ = try? await worktreeOrchestrator.createWorktreeSpace(
                                branchName: branch, existingBranch: existing
                            )
                        }
                    },
                    onCancel: { branchInputContext = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showDebugOverlay)
        .animation(.easeInOut(duration: 0.15), value: branchInputContext != nil)
        .animation(.easeInOut(duration: 0.15), value: worktreeOrchestrator.isCreating)
        .onReceive(NotificationCenter.default.publisher(for: .toggleDebugOverlay)) { notification in
            guard let obj = notification.object as? WorkspaceCollection,
                  obj === workspaceCollection else { return }
            showDebugOverlay.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWorktreeBranchInput)) { notification in
            guard let obj = notification.object as? WorkspaceCollection,
                  obj === workspaceCollection else { return }
            let wd = notification.userInfo?[Notification.worktreeWorkingDirectoryKey] as? String ?? ""
            Task {
                guard let repoRoot = try? await WorktreeService.resolveRepoRoot(from: wd) else {
                    return
                }
                let repoURL = URL(filePath: repoRoot)
                let configURL = WorktreeService.resolveConfigFile(repoRoot: repoURL)
                let config: WorktreeConfig
                if let configURL, let parsed = try? WorktreeConfigParser.parse(fileURL: configURL) {
                    config = parsed
                } else {
                    config = WorktreeConfig()
                }
                branchInputContext = BranchInputContext(
                    repoRoot: repoURL, worktreeDir: config.worktreeDir
                )
            }
        }
    }
}

// MARK: - Branch Input Context

private struct BranchInputContext {
    let repoRoot: URL
    let worktreeDir: String
}
