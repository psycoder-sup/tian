import SwiftUI

struct SidebarToggleButton: View {
    let workspaceCollection: WorkspaceCollection

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .toggleSidebar,
                object: workspaceCollection
            )
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar-toggle")
        .accessibilityLabel("Toggle sidebar")
        .accessibilityHint("Opens or closes the workspace sidebar")
    }
}
