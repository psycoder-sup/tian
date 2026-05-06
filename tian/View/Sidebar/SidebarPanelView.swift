import SwiftUI

struct SidebarPanelView: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator
    let sidebarState: SidebarState

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 40)
            SidebarExpandedContentView(
                workspaceCollection: workspaceCollection,
                worktreeOrchestrator: worktreeOrchestrator,
                sidebarState: sidebarState
            )
            Spacer()
            newWorkspaceButton
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))
        .padding(4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar-panel")
        .accessibilityLabel("Workspace sidebar")
    }

    private var newWorkspaceButton: some View {
        Button {
            WorkspaceCreationFlow.createWorkspace(in: workspaceCollection)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .medium))
                Text("New Workspace")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityIdentifier("new-workspace-button")
        .accessibilityLabel("New workspace")
    }
}
