import SwiftUI

struct SidebarWorkspaceHeaderView: View {
    let workspace: Workspace
    let isExpanded: Bool
    let isActive: Bool
    let isKeyboardSelected: Bool
    /// When `true`, draws the drag-reorder insertion indicator along this row's
    /// top edge — i.e. "a workspace will be inserted *above* this row".
    var isDropTargetAbove: Bool = false
    let onToggleDisclosure: () -> Void
    let onAddSession: () -> Void
    let onSelectWorkspace: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggleDisclosure) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workspace-disclosure-\(workspace.id)")
            .accessibilityLabel(isExpanded ? "Collapse \(workspace.name)" : "Expand \(workspace.name)")

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

            Button(action: onAddSession) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(white: 0.4, opacity: 1))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-session-\(workspace.id)")
            .accessibilityLabel("New session in \(workspace.name)")
            .help("New session (⌘N)")
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
        .overlay(alignment: .top) {
            if isDropTargetAbove {
                WorkspaceDropIndicator()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelectWorkspace() }
        .contextMenu {
            Button("Rename") { isRenaming = true }
            Divider()
            DefaultDirectoryMenu(
                name: workspace.name,
                currentDirectory: workspace.defaultWorkingDirectory,
                onSet: onSetDirectory
            )
            Divider()
            Button("New Session...", action: onAddSession)
            Divider()
            Button("Close Workspace", action: onClose)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("workspace-header-\(workspace.id)")
        .accessibilityLabel("\(workspace.name), \(workspace.sessionCollection.sessions.count) sessions, \(isExpanded ? "expanded" : "collapsed")")
        .accessibilityHint("Double-tap to open this workspace")
        .accessibilityAction(named: Text(isExpanded ? "Collapse" : "Expand")) { onToggleDisclosure() }
    }
}

/// A thin accent-colored capsule marking the position a dragged workspace will
/// land during a sidebar reorder. Shared by the header rows (top edge = "insert
/// above this row") and the trailing end-of-list drop zone. Purely decorative.
struct WorkspaceDropIndicator: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 8)
            .accessibilityHidden(true)
    }
}
