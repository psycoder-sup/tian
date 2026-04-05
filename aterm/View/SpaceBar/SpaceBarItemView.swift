import SwiftUI

struct SpaceBarItemView: View {
    @Bindable var space: SpaceModel
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isRenaming = false
    @State private var lastClickTime: Date?

    var body: some View {
        InlineRenameView(
            text: space.name,
            isRenaming: $isRenaming,
            onCommit: { space.name = $0 }
        )
        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
        .foregroundStyle(isActive ? .primary : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background {
            if isActive {
                Capsule()
                    .fill(.white.opacity(0.1))
            }
        }
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
        .contentShape(Capsule())
        .draggable(SpaceDragItem(spaceID: space.id))
        .contextMenu {
            Button("Rename") { isRenaming = true }
            Divider()
            DefaultDirectoryMenu(
                name: space.name,
                currentDirectory: space.defaultWorkingDirectory,
                onSet: { space.defaultWorkingDirectory = $0 }
            )
            Divider()
            Button("Close Space", action: onClose)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(space.name)
        .accessibilityValue(isActive ? "selected" : "not selected")
        .accessibilityHint("Double-tap to switch. Double-tap and hold to rename.")
    }
}
