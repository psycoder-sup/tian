import SwiftUI

/// Per-section tab bar. Claude sections render a leading space-name +
/// branch header in place of the kind glyph; terminal sections keep the
/// `>_` glyph. The tab list and trailing "+" new-tab button follow.
/// Cross-section drag-reorder is enforced in Phase 6; this phase only
/// allows reorder within a single section.
struct SectionTabBarView: View {
    /// Layout height of the section tab bar. Terminal sections use a denser
    /// row; Claude keeps the original height because it pairs with the
    /// space-name + branch header.
    static func height(for kind: SectionKind) -> CGFloat {
        kind == .terminal ? 36 : 48
    }

    let section: SectionModel
    let spaceModel: SpaceModel?
    let trailingToolbar: AnyView?
    var onNewTab: () -> Void = {}

    @Namespace private var tabNamespace

    private var isCompact: Bool { section.kind == .terminal }

    init(
        section: SectionModel,
        spaceModel: SpaceModel? = nil,
        onNewTab: @escaping () -> Void = {},
        @ViewBuilder trailingToolbar: () -> some View = { EmptyView() }
    ) {
        self.section = section
        self.spaceModel = spaceModel
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
            if section.kind == .claude, let spaceModel {
                ClaudeSectionHeaderView(spaceModel: spaceModel)
                    .padding(.leading, 4)
                    .padding(.trailing, 6)
            } else {
                SectionKindGlyph(kind: section.kind, size: isCompact ? 16 : 20)
                    .padding(.leading, 4)
                    .padding(.trailing, 2)
            }

            GlassEffectContainer {
                HStack(spacing: 6) {
                    ForEach(section.tabs) { tab in
                        TabBarItemView(
                            tab: tab,
                            isActive: tab.id == section.activeTabID,
                            isCompact: isCompact,
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
                    .font(.system(size: isCompact ? 12 : 14, weight: .medium))
                    .foregroundStyle(Color.chromeForeground.opacity(0.92))
            }
            .buttonStyle(.plain)
            .frame(width: isCompact ? 26 : 32, height: isCompact ? 26 : 32)
            .liquidGlassCircle()
            .accessibilityLabel("New \(section.kind == .claude ? "Claude" : "Terminal") tab")

            if let trailingToolbar {
                trailingToolbar
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height(for: section.kind))
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

/// Leading header for a Claude section tab bar — replaces the wordmark "C"
/// glyph (FR-26) with a git-branch icon, the space's name, and the primary
/// repo's branch (worktree repo when set, otherwise the first pinned repo).
private struct ClaudeSectionHeaderView: View {
    @Bindable var spaceModel: SpaceModel

    private var branchName: String? {
        guard let repoID = spaceModel.gitContext.pinnedRepoOrder.first else { return nil }
        return spaceModel.gitContext.repoStatuses[repoID]?.branchName
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.chromeForeground.opacity(0.9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(spaceModel.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.chromeForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(branchName ?? "—")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(red: 180/255, green: 188/255, blue: 200/255).opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(spaceModel.name)\(branchName.map { ", branch \($0)" } ?? "")")
    }
}
