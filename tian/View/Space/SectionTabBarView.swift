import SwiftUI

/// Per-section tab bar. Claude sections render a leading space-name +
/// branch header in place of the kind glyph; terminal sections keep the
/// `>_` glyph. The tab list and trailing "+" new-tab button follow.
/// Tabs reorder via a live in-bar drag: the grabbed pill slides along the
/// row (clamped to it) while siblings shuffle aside, and release commits
/// the arrangement. FR-22 (no cross-section moves) holds structurally —
/// the gesture can only reorder within its own section's bar.
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

    // MARK: Live reorder drag state

    /// Spacing between pills — shared by the layout and the slot math.
    private static let tabSpacing: CGFloat = 6

    @State private var dragTabID: UUID?
    @State private var dragSourceIndex = 0
    /// Clamped x-translation of the dragged pill. Never animated — the
    /// pill tracks the cursor raw.
    @State private var dragTranslation: CGFloat = 0
    /// Slot the dragged pill would land in if released now. Changed only
    /// inside an explicit `withAnimation` so sibling shuffles and the
    /// commit share one animation curve (mixing curves causes a visible
    /// wiggle at commit).
    @State private var proposedIndex: Int?
    /// Keeps the just-released pill above its neighbors until the commit
    /// animation finishes.
    @State private var settlingTabID: UUID?
    /// Set when a mid-drag tab-list mutation cancels the drag; stops the
    /// still-live gesture from re-seeding with a stale baseline.
    @State private var dragSessionCancelled = false
    /// True while a pill drag gesture is actively tracking. `@GestureState`
    /// resets even when the system cancels the gesture without calling
    /// onEnded, so its falling edge clears stuck drag state.
    @GestureState private var isDragGestureActive = false
    /// Measured width of the pill row, for slot math.
    @State private var rowWidth: CGFloat = 0

    /// Pills are equal width, so one slot = pill width + one spacing gap.
    private var slotWidth: CGFloat {
        let count = section.tabs.count
        guard count > 0, rowWidth > 0 else { return 0 }
        return (rowWidth + Self.tabSpacing) / CGFloat(count)
    }

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
                HStack(spacing: Self.tabSpacing) {
                    ForEach(Array(section.tabs.enumerated()), id: \.element.id) { index, tab in
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
                        .offset(x: offsetForTab(at: index, id: tab.id))
                        .zIndex(tab.id == dragTabID || tab.id == settlingTabID ? 1 : 0)
                        .contentShape(Rectangle())
                        .simultaneousGesture(reorderGesture(for: tab, at: index))
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            }
            .background(WindowDragBlocker())

            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: isCompact ? 12 : 14, weight: .medium))
                    .foregroundStyle(Color.chromeForeground.opacity(0.92))
            }
            .buttonStyle(.plain)
            .frame(width: isCompact ? 26 : 32, height: isCompact ? 26 : 32)
            // Before liquidGlassCircle so the blocker sits above its
            // material platform view in AppKit hit-testing.
            .background(WindowDragBlocker())
            .liquidGlassCircle()
            .accessibilityLabel("New \(section.kind == .claude ? "Claude" : "Terminal") tab")

            if let trailingToolbar {
                trailingToolbar
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height(for: section.kind))
        .contentShape(Rectangle())
        .onChange(of: section.tabs.map(\.id)) { _, _ in
            // A tab appeared or vanished mid-drag — indices and slot width
            // are stale, so cancel. Our own commit nils dragTabID in the
            // same transaction as the reorder, so it never reaches this.
            guard dragTabID != nil else { return }
            clearDragState()
            dragSessionCancelled = true
        }
        .onChange(of: isDragGestureActive) { _, active in
            // Normal releases clear dragTabID in onEnded before this fires;
            // if it's still set, the system cancelled the gesture mid-flight.
            guard !active, dragTabID != nil else { return }
            withAnimation(.smooth(duration: 0.2)) { clearDragState() }
            settlingTabID = nil
            dragSessionCancelled = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(section.kind == .claude ? "Claude" : "Terminal") tabs")
    }

    // MARK: Live reorder

    /// Resets all live-drag state. Callers choose the animation context.
    private func clearDragState() {
        dragTabID = nil
        proposedIndex = nil
        dragTranslation = 0
    }

    private func offsetForTab(at index: Int, id: UUID) -> CGFloat {
        guard let dragTabID, let proposedIndex else { return 0 }
        if id == dragTabID { return dragTranslation }
        return TabReorderMath.siblingOffset(
            index: index,
            sourceIndex: dragSourceIndex,
            proposedIndex: proposedIndex,
            slotWidth: slotWidth
        )
    }

    private func reorderGesture(for tab: TabModel, at index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($isDragGestureActive) { _, state, _ in state = true }
            .onChanged { value in
                guard !dragSessionCancelled else { return }
                if dragTabID == nil {
                    // Deliberately no activation here (Safari-style): activating
                    // swaps the visible pane content and steals first responder,
                    // which cancels this gesture mid-flight. Click still selects.
                    dragTabID = tab.id
                    dragSourceIndex = index
                    proposedIndex = index
                }
                dragTranslation = TabReorderMath.clampedTranslation(
                    value.translation.width,
                    sourceIndex: dragSourceIndex,
                    count: section.tabs.count,
                    slotWidth: slotWidth
                )
                let next = TabReorderMath.proposedIndex(
                    clampedTranslation: dragTranslation,
                    sourceIndex: dragSourceIndex,
                    count: section.tabs.count,
                    slotWidth: slotWidth
                )
                if next != proposedIndex {
                    withAnimation(.smooth(duration: 0.18)) { proposedIndex = next }
                }
            }
            .onEnded { _ in
                defer { dragSessionCancelled = false }
                guard let id = dragTabID, let dest = proposedIndex else { return }
                settlingTabID = id
                // One transaction for the model reorder and all offset
                // resets: sibling layout moves cancel their offset removal
                // exactly (net zero); the dragged pill animates only its
                // sub-slot residual.
                withAnimation(.smooth(duration: 0.2), completionCriteria: .logicallyComplete) {
                    if dest != dragSourceIndex {
                        section.reorderTab(from: dragSourceIndex, to: dest)
                    }
                    clearDragState()
                } completion: {
                    settlingTabID = nil
                }
            }
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
