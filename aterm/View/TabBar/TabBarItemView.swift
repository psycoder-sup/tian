import SwiftUI

struct TabBarItemView: View {
    @Bindable var tab: TabModel
    let isActive: Bool
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseToRight: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var lastClickTime: Date?

    var body: some View {
        tabContent
            .onHover { isHovering = $0 }
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
            .draggable(TabDragItem(tabID: tab.id))
            .contextMenu {
                Button("Rename") { isRenaming = true }
                Divider()
                Button("Close Tab", action: onClose)
                Button("Close Other Tabs", action: onCloseOthers)
                Button("Close Tabs to the Right", action: onCloseToRight)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(tab.name)
            .accessibilityValue(isActive ? "selected" : "not selected")
            .accessibilityHint("Double-tap to switch. Double-tap and hold to rename.")
    }

    @ViewBuilder
    private var tabContent: some View {
        let inner = HStack(spacing: 6) {
            InlineRenameView(
                text: tab.name,
                isRenaming: $isRenaming,
                onCommit: { tab.name = $0 }
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isActive ? .primary : .secondary)

            if isActive || isHovering {
                Button(action: onClose) {
                    Text("\u{00D7}")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab \(tab.name)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 8))
        .contentShape(Capsule())

        if isActive {
            inner
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("activeTab", in: namespace)
        } else {
            inner
        }
    }
}
