import SwiftUI

struct WorkspaceIndicatorView: View {
    let workspace: Workspace

    var body: some View {
        let spaceName = workspace.activeSpace?.name ?? ""

        HStack(spacing: 4) {
            Text(workspace.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("›")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Text(spaceName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(workspace.name), \(spaceName)")
    }
}
