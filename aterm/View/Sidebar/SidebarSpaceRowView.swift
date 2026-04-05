import SwiftUI

struct SidebarSpaceRowView: View {
    let space: SpaceModel
    let isActive: Bool
    let isKeyboardSelected: Bool
    let onSelect: () -> Void
    let onSetDirectory: (URL?) -> Void
    let onClose: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var lastClickTime: Date?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.accentColor : .clear)
                .frame(width: 4, height: 4)

            InlineRenameView(
                text: space.name,
                isRenaming: $isRenaming,
                onCommit: { space.name = $0 }
            )
            .font(.system(size: 11))
            .foregroundStyle(isActive ? .primary : .secondary)
        }
        .frame(height: 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.15))
            } else if isHovering {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
            }
        }
        .overlay {
            if isKeyboardSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let now = Date()
            if let last = lastClickTime, now.timeIntervalSince(last) < 0.3 {
                lastClickTime = nil
                isRenaming = true
            } else {
                lastClickTime = now
                onSelect()
            }
        }
        .onHover { isHovering = $0 }
        .draggable(SpaceDragItem(spaceID: space.id))
        .contextMenu {
            Button("Rename") { isRenaming = true }
            Divider()
            DefaultDirectoryMenu(
                name: space.name,
                currentDirectory: space.defaultWorkingDirectory,
                onSet: onSetDirectory
            )
            Divider()
            Button("Close Space", action: onClose)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("space-row-\(space.id)")
        .accessibilityLabel(space.name)
        .accessibilityValue(isActive ? "selected" : "not selected")
        .accessibilityHint("Double-tap to switch. Double-tap and hold to rename.")
    }
}
