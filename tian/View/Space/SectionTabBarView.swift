import SwiftUI

/// Per-section tab bar. Shows a leading section-kind glyph (FR-26), the
/// tab list, and a trailing "+" new-tab button. Reuses `TabBarItemView`
/// for individual tabs. Cross-section drag-reorder is enforced in
/// Phase 6; this phase only allows reorder within a single section.
struct SectionTabBarView: View {
    /// Layout height of the section tab bar.
    static let height: CGFloat = 48

    let section: SectionModel
    let trailingToolbar: AnyView?
    var onNewTab: () -> Void = {}

    @Namespace private var tabNamespace

    init(
        section: SectionModel,
        onNewTab: @escaping () -> Void = {},
        @ViewBuilder trailingToolbar: () -> some View = { EmptyView() }
    ) {
        self.section = section
        self.onNewTab = onNewTab
        let built = trailingToolbar()
        if built is EmptyView {
            self.trailingToolbar = nil
        } else {
            self.trailingToolbar = AnyView(built)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            SectionKindGlyph(kind: section.kind, size: 20)
                .padding(.leading, 4)
                .padding(.trailing, 2)

            GlassEffectContainer {
                HStack(spacing: 6) {
                    ForEach(section.tabs) { tab in
                        TabBarItemView(
                            tab: tab,
                            isActive: tab.id == section.activeTabID,
                            namespace: tabNamespace,
                            onSelect: {
                                withAnimation(.smooth(duration: 0.3)) {
                                    section.activateTab(id: tab.id)
                                }
                            },
                            onClose: {
                                CloseConfirmationDialog.confirmIfNeeded(
                                    processCount: ProcessDetector.runningProcessCount(in: tab),
                                    target: .tab,
                                    action: { section.removeTab(id: tab.id) }
                                )
                            },
                            onCloseOthers: {
                                let affected = section.tabs.filter { $0.id != tab.id }
                                CloseConfirmationDialog.confirmIfNeeded(
                                    processCount: ProcessDetector.runningProcessCount(in: affected),
                                    target: .tabs(count: affected.count),
                                    action: { section.closeOtherTabs(keepingID: tab.id) }
                                )
                            },
                            onCloseToRight: {
                                guard let idx = section.tabs.firstIndex(where: { $0.id == tab.id }) else { return }
                                let rightTabs = Array(section.tabs[(idx + 1)...])
                                guard !rightTabs.isEmpty else { return }
                                CloseConfirmationDialog.confirmIfNeeded(
                                    processCount: ProcessDetector.runningProcessCount(in: rightTabs),
                                    target: .tabs(count: rightTabs.count),
                                    action: { section.closeTabsToRight(ofID: tab.id) }
                                )
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .glassEffect(.regular, in: .circle)
            .accessibilityLabel("New \(section.kind == .claude ? "Claude" : "Terminal") tab")

            if let trailingToolbar {
                trailingToolbar
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .dropDestination(for: TabDragItem.self) { items, _ in
            guard let item = items.first else { return false }
            // FR-22 — reject drops that cross the section boundary.
            // Items without an explicit sectionKind (legacy payloads)
            // are treated conservatively: accept only when the tabID is
            // already in this section.
            if let srcKind = item.sectionKind {
                guard SectionTabBarDropCoordinator.canAccept(
                    sourceSectionKind: srcKind,
                    destinationSectionKind: section.kind,
                    tabID: item.tabID
                ) else { return false }
            }
            guard let sourceIndex = section.tabs.firstIndex(where: { $0.id == item.tabID }) else {
                return false
            }
            let destIndex = section.tabs.count - 1
            if sourceIndex != destIndex {
                section.reorderTab(from: sourceIndex, to: destIndex)
            }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.kind == .claude ? "Claude" : "Terminal") tabs")
    }
}
