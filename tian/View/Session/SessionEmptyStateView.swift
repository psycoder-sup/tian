import SwiftUI

/// Apple-style empty-state view shown in a workspace's content area (where the
/// Claude session normally renders) when the workspace has no sessions — e.g.
/// right after the last session is closed. Closing the last session no longer
/// closes the workspace, so this offers a prominent action to start a new one.
///
/// The button reuses the same `.showCreateSessionInput` path as ⌘N and the
/// sidebar "New Session…" action, so `WorkspaceWindowContent` renders the shared
/// `CreateSessionView` modal (plain vs. worktree session).
struct SessionEmptyStateView: View {
    /// The window's collection — used as the notification `object` so
    /// `WorkspaceWindowContent`'s `object === workspaceCollection` guard matches.
    let workspaceCollection: WorkspaceCollection
    /// The workspace the new session should be created in.
    let workspace: Workspace

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

            Text("No Sessions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a session to get started.")
                .font(.body)
                .foregroundStyle(.secondary)

            Button(action: requestNewSession) {
                Label("New Session", systemImage: "plus")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("No sessions. Create a session to get started.")
        .accessibilityIdentifier("session-empty-state")
    }

    private func requestNewSession() {
        NotificationCenter.default.post(
            name: .showCreateSessionInput,
            object: workspaceCollection,
            userInfo: [
                Notification.createSessionWorkspaceIDKey: workspace.id
            ]
        )
    }
}
