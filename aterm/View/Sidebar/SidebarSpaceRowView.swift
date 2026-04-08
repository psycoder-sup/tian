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

    private func accessibilityDescription(sessions: [(paneID: UUID, state: ClaudeSessionState)]) -> String {
        var parts: [String] = [isActive ? "selected" : "not selected"]
        if !sessions.isEmpty {
            let descriptions = sessions.map { "\($0.state.rawValue)" }
            parts.append("Claude sessions: \(descriptions.joined(separator: ", "))")
        }
        return parts.joined(separator: ". ")
    }

    private var tabCountLabel: String {
        let count = space.tabs.count
        return count == 1 ? "1 tab" : "\(count) tabs"
    }

    var body: some View {
        let sessions = PaneStatusManager.shared.sessionStates(in: space)

        HStack(spacing: 8) {
            Circle()
                .fill(isActive ? Color.green : Color(white: 0.5, opacity: 0.4))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                InlineRenameView(
                    text: space.name,
                    isRenaming: $isRenaming,
                    onCommit: { space.name = $0 }
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Color(white: 0.9) : .secondary)

                SpaceStatusAreaView(sessions: sessions, space: space, isActive: isActive)
            }

            Spacer()

            Text(tabCountLabel)
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.45))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                    )
            } else if isHovering {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
            }
        }
        .overlay {
            if isKeyboardSelected {
                RoundedRectangle(cornerRadius: 8)
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
        .accessibilityValue(accessibilityDescription(sessions: sessions))
        .accessibilityHint("Double-tap to switch. Double-tap and hold to rename.")
    }
}
