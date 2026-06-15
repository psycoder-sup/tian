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
    /// When set (a markdown reader is the active tab), a git-diff toggle and a
    /// "copy all" button share the new-tab capsule, which morphs from circle to
    /// pill to hold them.
    let markdownReaderDocument: MarkdownDocument?
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
        markdownReaderDocument: MarkdownDocument? = nil,
        onNewTab: @escaping () -> Void = {},
        @ViewBuilder trailingToolbar: () -> some View = { EmptyView() }
    ) {
        self.section = section
        self.spaceModel = spaceModel
        self.markdownReaderDocument = markdownReaderDocument
        self.onNewTab = onNewTab
        let built = trailingToolbar()
        if built is EmptyView {
            self.trailingToolbar = nil
        } else {
            self.trailingToolbar = AnyView(built)
        }
    }

    /// New-tab "+" / copy-all share one capsule, sized `buttonSize` per cell.
    private var buttonSize: CGFloat { isCompact ? 26 : 32 }

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

            HStack(spacing: 4) {
                Button(action: onNewTab) {
                    Image(systemName: "plus")
                        .font(.system(size: isCompact ? 12 : 14, weight: .medium))
                        .foregroundStyle(Color.chromeForeground.opacity(0.92))
                        // Frame + contentShape inside the label so the whole
                        // cell is clickable, not just the glyph.
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassHoverHighlight()
                .accessibilityLabel("New \(section.kind == .claude ? "Claude" : "Terminal") tab")

                if let markdownReaderDocument {
                    MarkdownDiffToggleButton(document: markdownReaderDocument, size: buttonSize, iconSize: isCompact ? 12 : 14)
                        .glassHoverHighlight()
                        .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
                    MarkdownCopyButton(document: markdownReaderDocument, size: buttonSize, iconSize: isCompact ? 12 : 14)
                        .glassHoverHighlight()
                        .transition(.scale(scale: 0.4, anchor: .leading).combined(with: .opacity))
                }
            }
            // Before liquidGlassCapsule so the blocker sits above its
            // material platform view in AppKit hit-testing. The capsule hugs
            // its content — a circle for "+" alone, a pill once the reader
            // controls join.
            .background(WindowDragBlocker())
            .liquidGlassCapsule()
            .animation(.smooth(duration: 0.3), value: markdownReaderDocument != nil)

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

/// Git-diff toggle for a markdown reader. Flips the active reader tab between
/// rendered markdown and the file's line-by-line diff against HEAD. Shares the
/// new-tab capsule (so it carries no background of its own) and tints when the
/// diff face is showing. Lives here rather than with the reader because it's
/// rendered only as tab-bar chrome.
struct MarkdownDiffToggleButton: View {
    let document: MarkdownDocument
    var size: CGFloat = 32
    var iconSize: CGFloat = 14

    var body: some View {
        Button {
            document.showDiff.toggle()
        } label: {
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(document.showDiff
                    ? Color.accentColor
                    : Color.chromeForeground.opacity(0.92))
                // Frame + contentShape inside the label so the whole cell is
                // clickable, not just the glyph.
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(document.showDiff ? "Show rendered markdown" : "Show git diff")
        .accessibilityLabel("Toggle git diff")
        .accessibilityAddTraits(document.showDiff ? .isSelected : [])
    }
}

/// "Copy all" control for a markdown reader. A plain icon button that shares
/// the new-tab capsule (so it carries no background of its own) and copies the
/// document's verbatim source, flashing a checkmark to confirm. Lives here
/// rather than with the reader because it's rendered only as tab-bar chrome.
struct MarkdownCopyButton: View {
    let document: MarkdownDocument
    var size: CGFloat = 32
    var iconSize: CGFloat = 14

    @State private var didCopy = false
    /// Outstanding task that resets `didCopy`; cancelled if copied again first.
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        Button(action: copyAll) {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(didCopy ? Color.green : Color.chromeForeground.opacity(0.92))
                .contentTransition(.symbolEffect(.replace))
                // Frame + contentShape inside the label so the whole cell is
                // clickable, not just the glyph.
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(didCopy ? "Copied" : "Copy all")
        .accessibilityLabel("Copy all contents")
    }

    /// Copies the verbatim markdown source to the general pasteboard and shows
    /// a brief checkmark confirmation.
    private func copyAll() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(document.rawText, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { didCopy = false }
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
