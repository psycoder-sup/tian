import SwiftUI

struct SidebarWorkspaceHeaderView: View {
    let workspace: Workspace
    let isExpanded: Bool
    let isActive: Bool
    let isKeyboardSelected: Bool
    let onToggleDisclosure: () -> Void
    let onAddSpace: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.easeInOut(duration: 0.15), value: isExpanded)

            InlineRenameView(
                text: workspace.name,
                isRenaming: $isRenaming,
                onCommit: { workspace.name = $0 }
            )
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isActive ? .primary : .secondary)

            Spacer()

            if isHovering || isKeyboardSelected {
                Button(action: onAddSpace) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("add-space-\(workspace.id)")
                .accessibilityLabel("New space in \(workspace.name)")
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
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
            Button("Close Workspace", action: onClose)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workspace-header-\(workspace.id)")
        .accessibilityLabel("\(workspace.name), \(workspace.spaceCollection.spaces.count) spaces, \(isExpanded ? "expanded" : "collapsed")")
        .accessibilityHint("Double-tap to expand or collapse")
    }
}
