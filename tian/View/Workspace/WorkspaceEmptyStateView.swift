import SwiftUI

/// Apple-style empty-state view shown in the main content area when a
/// WorkspaceCollection has no workspaces. Offers a single prominent action
/// to launch the directory picker and create the first workspace.
struct WorkspaceEmptyStateView: View {
    let workspaceCollection: WorkspaceCollection

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

            Text("No Workspaces")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a workspace to get started.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button {
                WorkspaceCreationFlow.createWorkspace(in: workspaceCollection)
            } label: {
                Label("New Workspace", systemImage: "plus")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("No workspaces. Create a workspace to get started.")
        .accessibilityIdentifier("workspace-empty-state")
    }
}
