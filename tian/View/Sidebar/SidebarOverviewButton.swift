import SwiftUI

struct SidebarOverviewButton: View {
    let workspaceCollection: WorkspaceCollection

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .toggleSessionOverview,
                object: workspaceCollection
            )
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("session-overview-toggle")
        .accessibilityLabel("Session overview")
        .accessibilityHint("Opens the session overview grid")
        .help("Session Overview (⇧⌘O)")
    }
}
