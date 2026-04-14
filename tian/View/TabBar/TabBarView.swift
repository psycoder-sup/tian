import SwiftUI

struct TabBarView: View {
    let space: SpaceModel
    var onNewTab: () -> Void = {}

    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: 8) {
            GlassEffectContainer {
                HStack(spacing: 0) {
                    ForEach(space.tabs) { tab in
                        TabBarItemView(
                            tab: tab,
                            isActive: tab.id == space.activeTabID,
                            namespace: tabNamespace,
                            onSelect: {
                                withAnimation(.smooth(duration: 0.3)) {
                                    space.activateTab(id: tab.id)
                                }
                            },
                            onClose: {
                                CloseConfirmationDialog.confirmIfNeeded(
                                    processCount: ProcessDetector.runningProcessCount(in: tab),
                                    target: .tab,
                                    action: { space.removeTab(id: tab.id) }
                                )
                            },
                            onCloseOthers: {
                                let affected = space.tabs.filter { $0.id != tab.id }
                                CloseConfirmationDialog.confirmIfNeeded(
                                    processCount: ProcessDetector.runningProcessCount(in: affected),
                                    target: .tabs(count: affected.count),
                                    action: { space.closeOtherTabs(keepingID: tab.id) }
                                )
                            },
                            onCloseToRight: {
                                guard let idx = space.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                                let rightTabs = Array(space.tabs[(idx + 1)...])
                                guard !rightTabs.isEmpty else { return }
                                CloseConfirmationDialog.confirmIfNeeded(
                                    processCount: ProcessDetector.runningProcessCount(in: rightTabs),
                                    target: .tabs(count: rightTabs.count),
                                    action: { space.closeTabsToRight(ofID: tab.id) }
                                )
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(4)
                .background(Color.gray.opacity(0.12), in: Capsule())
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel("New tab")
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .dropDestination(for: TabDragItem.self) { items, _ in
            guard let item = items.first,
                  let sourceIndex = space.tabs.firstIndex(where: { $0.id == item.tabID }) else {
                return false
            }
            let destIndex = space.tabs.count - 1
            if sourceIndex != destIndex {
                space.reorderTab(from: sourceIndex, to: destIndex)
            }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }
}
