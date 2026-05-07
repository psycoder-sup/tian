import SwiftUI

struct TabBarItemView: View {
    @Bindable var tab: TabModel
    let isActive: Bool
    /// Compact pill (smaller height + tighter padding). Used by terminal
    /// section tab bars; Claude keeps the original full-size pill.
    var isCompact: Bool = false
    let namespace: Namespace.ID
    let onSelect: () -> Void
    let onClose: () -> Void
    let onCloseOthers: () -> Void
    let onCloseToRight: () -> Void

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var lastClickTime: Date?

    /// Gated on `isActive` so inactive tabs don't observe the status
    /// dictionary — the aurora only shows on the active pill anyway,
    /// and reading `PaneStatusManager.shared.sessionStates` subscribes
    /// the whole dictionary for change tracking.
    private var hasBusyPane: Bool {
        guard isActive, tab.sectionKind == .claude else { return false }
        return PaneStatusManager.shared.hasSessionState(.busy, in: tab)
    }

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
            .draggable(TabDragItem(tabID: tab.id, sectionKind: tab.sectionKind))
            .contextMenu {
                Button("Rename") { isRenaming = true }
                Divider()
                Button("Close Tab", action: onClose)
                Button("Close Other Tabs", action: onCloseOthers)
                Button("Close Tabs to the Right", action: onCloseToRight)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(tab.displayName)
            .accessibilityValue(isActive ? "selected" : "not selected")
            .accessibilityHint("Double-tap to switch. Double-tap and hold to rename.")
    }

    @ViewBuilder
    private var tabContent: some View {
        let tint = tab.sectionKind.tint
        let showAurora = isActive && hasBusyPane
        let inner = HStack(spacing: 8) {
            InlineRenameView(
                text: tab.displayName,
                isRenaming: $isRenaming,
                onCommit: { tab.customName = $0 }
            )
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(isActive ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isActive || isHovering {
                Button(action: onClose) {
                    Text("\u{00D7}")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                        .opacity(isActive ? 0.9 : 0.5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab \(tab.displayName)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, isCompact ? 11 : 14)
        .frame(height: isCompact ? 24 : 30)
        .contentShape(Capsule())
        .overlay(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.22),
                            tint.opacity(0.06),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(false)
        )
        .overlay {
            if showAurora {
                AuroraCapsuleFill()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showAurora)

        if isActive {
            inner
                .glassEffect(.regular.tint(tint.opacity(0.12)).interactive(), in: .capsule)
                .glassEffectID("activeTab", in: namespace)
        } else {
            inner
                .background {
                    Capsule()
                        .fill(Color.primary.opacity(isHovering ? 0.045 : 0.025))
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                }
        }
    }
}
