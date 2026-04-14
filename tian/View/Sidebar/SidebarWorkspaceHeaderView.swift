import SwiftUI

struct SidebarWorkspaceHeaderView: View {
    let workspace: Workspace
    let isExpanded: Bool
    let isActive: Bool
    let isKeyboardSelected: Bool
    let isCreatingWorktree: Bool
    let onToggleDisclosure: () -> Void
    let onAddSpace: () -> Void
    let onNewWorktreeSpace: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)

            InlineRenameView(
                text: workspace.name,
                isRenaming: $isRenaming,
                onCommit: { workspace.name = $0 }
            )
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)

            Spacer()

            if isCreatingWorktree {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }

            Button(action: onNewWorktreeSpace) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.4, opacity: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("new-worktree-space-\(workspace.id)")
            .accessibilityLabel("New worktree space in \(workspace.name)")

            Button(action: onAddSpace) {
                Text("+")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.4, opacity: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-space-\(workspace.id)")
            .accessibilityLabel("New space in \(workspace.name)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .onHover { isHovering = $0 }
        .background {
            if isKeyboardSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onToggleDisclosure() }
        .draggable(WorkspaceDragItem(workspaceID: workspace.id))
        .contextMenu {
            Button("Rename") { isRenaming = true }
            Divider()
            DefaultDirectoryMenu(
                name: workspace.name,
                currentDirectory: workspace.defaultWorkingDirectory,
                onSet: onSetDirectory
            )
            Divider()
            Button("New Worktree Space...", action: onNewWorktreeSpace)
            Divider()
            Button("Close Workspace", action: onClose)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workspace-header-\(workspace.id)")
        .accessibilityLabel("\(workspace.name), \(workspace.spaceCollection.spaces.count) spaces, \(isExpanded ? "expanded" : "collapsed")")
        .accessibilityHint("Double-tap to expand or collapse")
    }
}
