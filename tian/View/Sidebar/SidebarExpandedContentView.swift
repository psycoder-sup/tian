import SwiftUI

struct SidebarExpandedContentView: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator
    let sidebarState: SidebarState

    @State private var selectedIndex: Int?
    @State private var disclosedWorkspaces: Set<UUID> = []
    /// The insertion slot the currently-dragged workspace would land in
    /// (0...`workspaces.count`), or `nil` when no workspace drag is in progress.
    /// Drives the reorder insertion indicator. Uses "insert before the hovered
    /// row" semantics; `count` is the end-of-list slot.
    @State private var workspaceDropSlot: Int?
    /// The workspace being reordered via the header drag gesture, or `nil` when
    /// idle. Only this row lifts and follows the cursor.
    @State private var draggingWorkspaceID: UUID?
    /// The dragged row's live vertical offset from its resting position.
    @State private var dragOffsetY: CGFloat = 0
    /// Each workspace group's frame in the `sidebarReorder` coordinate space,
    /// keyed by workspace id. Feeds the pointer-Y → slot math.
    @State private var workspaceFrames: [UUID: CGRect] = [:]

    private var flatItems: [SidebarItem] {
        var items: [SidebarItem] = []
        for workspace in workspaceCollection.workspaces {
            items.append(.workspaceHeader(workspace))
            if disclosedWorkspaces.contains(workspace.id) {
                // Use the same hierarchical ordering as the render so arrow-key
                // selection indices stay in lockstep with the drawn rows.
                for entry in workspace.sessionCollection.hierarchicalOrder() {
                    items.append(.sessionRow(workspace, entry.session))
                }
            }
        }
        return items
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(workspaceCollection.workspaces.enumerated()), id: \.element.id) { rowIndex, workspace in
                    // Wrap the header and its disclosed sessions in one container so
                    // the whole group lifts together while its header is dragged.
                    VStack(alignment: .leading, spacing: 0) {
                        SidebarWorkspaceHeaderView(
                            workspace: workspace,
                            isExpanded: disclosedWorkspaces.contains(workspace.id),
                            isActive: workspace.id == workspaceCollection.activeWorkspaceID,
                            isKeyboardSelected: selectedIndex == flatIndex(for: .workspaceHeader(workspace)),
                            isDropTargetAbove: workspaceDropSlot == rowIndex,
                            onToggleDisclosure: { toggleDisclosure(workspace.id) },
                            onAddSession: { addSession(to: workspace) },
                            onSelectWorkspace: { selectWorkspace(workspace) },
                            onSetDirectory: { url in
                                workspace.setDefaultWorkingDirectory(url)
                            },
                            onClose: { workspaceCollection.removeWorkspace(id: workspace.id) }
                        )
                        // Vertical-only reorder drag lives on the header so drags
                        // over the session area don't reorder. `minimumDistance: 5`
                        // lets a click still fall through to the header's tap.
                        .gesture(workspaceReorderGesture(for: workspace))

                        if disclosedWorkspaces.contains(workspace.id) {
                            // Zero inter-row spacing so the per-row connector rail
                            // segments abut into one continuous vertical line.
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(workspace.sessionCollection.hierarchicalOrder(), id: \.session.id) { entry in
                                    SidebarSessionRowView(
                                        session: entry.session,
                                        isActive: workspace.id == workspaceCollection.activeWorkspaceID
                                            && entry.session.id == workspace.sessionCollection.activeSessionID,
                                        isChild: entry.isChild,
                                        isOrchestrator: entry.isOrchestrator,
                                        isKeyboardSelected: selectedIndex == flatIndex(for: .sessionRow(workspace, entry.session)),
                                        setupProgress: worktreeOrchestrator.setupProgress?.sessionID == entry.session.id
                                            ? worktreeOrchestrator.setupProgress
                                            : nil,
                                        onSelect: { selectSession(workspace: workspace, sessionID: entry.session.id) },
                                        onSetDirectory: { url in
                                            entry.session.defaultWorkingDirectory = url
                                        },
                                        onClose: { closeSession(entry.session, in: workspace) }
                                    )
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.top, 2)
                            .padding(.bottom, 4)
                        }
                    }
                    // Measure this group's frame in the reorder coordinate space so
                    // the drag can map pointer-Y to an insertion slot.
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: WorkspaceFramePreferenceKey.self,
                                value: [workspace.id: proxy.frame(in: .named("sidebarReorder"))]
                            )
                        }
                    }
                    // The dragged group floats and follows the cursor 1:1; every
                    // other group slides by `shuffleOffset` to open a gap at the
                    // target slot. The animation is scoped per row: the dragged row
                    // gets `nil` so it never lags the pointer, while the shuffling
                    // rows ease into place as the slot changes.
                    .offset(y: draggingWorkspaceID == workspace.id ? dragOffsetY : shuffleOffset(forRowAt: rowIndex))
                    .animation(
                        draggingWorkspaceID == workspace.id ? nil : .easeOut(duration: 0.12),
                        value: workspaceDropSlot
                    )
                    .zIndex(draggingWorkspaceID == workspace.id ? 1 : 0)
                    .opacity(draggingWorkspaceID == workspace.id ? 0.85 : 1)
                }

                // End-of-list indicator host: shows where a workspace dropped past
                // the last row (slot == count) will land. No drop target — the
                // header drag gesture drives the reorder directly.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 12)
                    .overlay(alignment: .top) {
                        if workspaceDropSlot == workspaceCollection.workspaces.count {
                            WorkspaceDropIndicator()
                        }
                    }
            }
            .coordinateSpace(name: "sidebarReorder")
            .onPreferenceChange(WorkspaceFramePreferenceKey.self) { workspaceFrames = $0 }
        }
        .overlay {
            SidebarKeyboardResponder(
                isActive: sidebarState.focusTarget == .sidebar,
                onArrowUp: handleArrowUp,
                onArrowDown: handleArrowDown,
                onArrowLeft: handleArrowLeft,
                onArrowRight: handleArrowRight,
                onActivate: handleActivate,
                onEscape: handleEscape
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        }
        .onAppear {
            discloseActiveWorkspace()
        }
        .onChange(of: sidebarState.focusTarget) { _, newTarget in
            if newTarget == .sidebar {
                selectedIndex = 0
            } else {
                selectedIndex = nil
            }
        }
        // Auto-expand the active workspace when focus lands in it — on
        // cross-workspace jumps (⌘⇧↑/↓, ⌘1–9, clicks) and within-workspace
        // session switches. Expand-only: never collapses other workspaces.
        .onChange(of: workspaceCollection.activeWorkspaceID) { _, _ in
            discloseActiveWorkspace()
        }
        .onChange(of: workspaceCollection.activeWorkspace?.activeSessionID) { _, _ in
            discloseActiveWorkspace()
        }
    }

    // MARK: - Index Lookup

    private func flatIndex(for target: SidebarItem) -> Int? {
        flatItems.firstIndex(where: { $0.id == target.id })
    }

    // MARK: - Workspace Reorder

    /// Vertical-only reorder drag for a workspace header. `minimumDistance: 5`
    /// distinguishes a reorder from a click (which still toggles disclosure via
    /// the header's own tap). Reads pointer-Y in the `sidebarReorder` space and
    /// maps it to an insertion slot against each group's measured midpoint.
    private func workspaceReorderGesture(for workspace: Workspace) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("sidebarReorder"))
            .onChanged { value in
                if draggingWorkspaceID == nil {
                    draggingWorkspaceID = workspace.id
                }
                dragOffsetY = value.translation.height
                workspaceDropSlot = currentDropSlot(for: workspace, value: value)
            }
            .onEnded { value in
                guard draggingWorkspaceID != nil else { return }
                let slot = currentDropSlot(for: workspace, value: value)
                if let source = workspaceCollection.workspaces.firstIndex(where: { $0.id == workspace.id }) {
                    let dest = WorkspaceCollection.reorderDestinationIndex(source: source, targetSlot: slot)
                    workspaceCollection.reorderWorkspace(from: source, to: dest)
                }
                draggingWorkspaceID = nil
                dragOffsetY = 0
                workspaceDropSlot = nil
            }
    }

    /// The insertion slot the dragged workspace currently targets, derived from its
    /// visual center against the measured row midpoints. Shared by `onChanged` (to
    /// drive the live gap) and `onEnded` (to commit the drop) so both agree.
    private func currentDropSlot(for workspace: Workspace, value: DragGesture.Value) -> Int {
        WorkspaceReorderGeometry.insertionSlot(
            forY: draggedRowCenterY(for: workspace, value: value),
            rowMidYs: currentRowMidYs()
        )
    }

    /// The dragged row's current visual center in the `sidebarReorder` space:
    /// its measured resting midpoint plus the drag translation. Used for slot
    /// targeting so the drop tracks the row's body, not the grab point. Falls back
    /// to the raw pointer if the frame hasn't been measured yet.
    private func draggedRowCenterY(for workspace: Workspace, value: DragGesture.Value) -> CGFloat {
        if let midY = workspaceFrames[workspace.id]?.midY {
            return midY + value.translation.height
        }
        return value.location.y
    }

    /// Each workspace's measured vertical midpoint in display order. Rows that
    /// haven't reported a frame yet fall back to `.greatestFiniteMagnitude`, sorting
    /// them below any real pointer position so an unmeasured row never counts as
    /// "above" the pointer and inflates the computed slot.
    private func currentRowMidYs() -> [CGFloat] {
        workspaceCollection.workspaces.map { workspaceFrames[$0.id]?.midY ?? .greatestFiniteMagnitude }
    }

    /// Vertical offset for a non-dragged workspace row at `index`, opening the
    /// reorder gap where the dragged group will land. Returns 0 when no drag is
    /// in progress or when the row sits outside the vacated-to-target span.
    private func shuffleOffset(forRowAt index: Int) -> CGFloat {
        guard let draggingID = draggingWorkspaceID,
              let slot = workspaceDropSlot,
              let source = workspaceCollection.workspaces.firstIndex(where: { $0.id == draggingID })
        else { return 0 }
        let h = workspaceFrames[draggingID]?.height ?? 0
        return WorkspaceReorderGeometry.reorderShuffleOffset(index: index, source: source, slot: slot, draggedHeight: h)
    }

    // MARK: - Disclosure

    /// Expand the workspace that owns the active session so its row is visible.
    /// Expand-only — mirrors the `.onAppear` insert; never collapses anything.
    private func discloseActiveWorkspace() {
        if let id = workspaceCollection.activeWorkspaceID {
            disclosedWorkspaces.insert(id)
        }
    }

    private func toggleDisclosure(_ id: UUID) {
        if disclosedWorkspaces.contains(id) {
            disclosedWorkspaces.remove(id)
        } else {
            disclosedWorkspaces.insert(id)
        }
        clampSelectedIndex()
    }

    // MARK: - Add Session

    private func addSession(to workspace: Workspace) {
        NotificationCenter.default.post(
            name: .showCreateSessionInput,
            object: workspaceCollection,
            userInfo: [
                Notification.createSessionWorkspaceIDKey: workspace.id
            ]
        )
        disclosedWorkspaces.insert(workspace.id)
    }

    // MARK: - Close Session

    private func closeSession(_ session: Session, in workspace: Workspace) {
        SessionCloseFlow.run(session: session, in: workspace, worktreeOrchestrator: worktreeOrchestrator)
    }

    // MARK: - Workspace Selection

    private func selectWorkspace(_ workspace: Workspace) {
        workspaceCollection.activateWorkspace(id: workspace.id)
    }

    // MARK: - Session Selection

    private func selectSession(workspace: Workspace, sessionID: UUID) {
        workspaceCollection.activateWorkspace(id: workspace.id)
        workspace.sessionCollection.activateSession(id: sessionID)
        sidebarState.focusTarget = .terminal
    }

    // MARK: - Keyboard Navigation

    private func clampSelectedIndex() {
        guard let index = selectedIndex else { return }
        let count = flatItems.count
        if count == 0 {
            selectedIndex = nil
        } else if index >= count {
            selectedIndex = count - 1
        }
    }

    private func handleArrowUp() {
        let items = flatItems
        guard !items.isEmpty else { return }
        guard let current = selectedIndex else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(items.count - 1, max(0, current - 1))
    }

    private func handleArrowDown() {
        let items = flatItems
        guard !items.isEmpty else { return }
        guard let current = selectedIndex else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(items.count - 1, current + 1)
    }

    private func handleArrowLeft() {
        guard let index = selectedIndex else { return }
        let items = flatItems
        guard index < items.count else { return }
        if case .workspaceHeader(let ws) = items[index] {
            disclosedWorkspaces.remove(ws.id)
        }
    }

    private func handleArrowRight() {
        guard let index = selectedIndex else { return }
        let items = flatItems
        guard index < items.count else { return }
        if case .workspaceHeader(let ws) = items[index] {
            disclosedWorkspaces.insert(ws.id)
        }
    }

    private func handleActivate() {
        guard let index = selectedIndex else { return }
        let items = flatItems
        guard index < items.count else { return }
        switch items[index] {
        case .workspaceHeader(let ws):
            selectWorkspace(ws)
        case .sessionRow(let ws, let session):
            selectSession(workspace: ws, sessionID: session.id)
        }
    }

    private func handleEscape() {
        sidebarState.focusTarget = .terminal
    }
}

// MARK: - Workspace Frame Preference

/// Collects each workspace group's frame (in the `sidebarReorder` coordinate
/// space) up the view tree, keyed by workspace id, so the reorder drag can map a
/// pointer-Y to an insertion slot.
private struct WorkspaceFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Sidebar Item

private enum SidebarItem {
    case workspaceHeader(Workspace)
    case sessionRow(Workspace, Session)

    var id: String {
        switch self {
        case .workspaceHeader(let ws): "header-\(ws.id)"
        case .sessionRow(_, let session): "session-\(session.id)"
        }
    }
}

// MARK: - Keyboard Responder

private struct SidebarKeyboardResponder: NSViewRepresentable {
    let isActive: Bool
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onArrowLeft: () -> Void
    let onArrowRight: () -> Void
    let onActivate: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.wasActive = isActive
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onArrowUp = onArrowUp
        nsView.onArrowDown = onArrowDown
        nsView.onArrowLeft = onArrowLeft
        nsView.onArrowRight = onArrowRight
        nsView.onActivate = onActivate
        nsView.onEscape = onEscape

        let becameActive = isActive && !nsView.wasActive
        nsView.wasActive = isActive
        if becameActive, let window = nsView.window {
            window.makeFirstResponder(nsView)
        }
    }

    final class KeyView: NSView {
        var onArrowUp: (() -> Void)?
        var onArrowDown: (() -> Void)?
        var onArrowLeft: (() -> Void)?
        var onArrowRight: (() -> Void)?
        var onActivate: (() -> Void)?
        var onEscape: (() -> Void)?
        var wasActive = false

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            switch event.keyCode {
            case 126 where flags.subtracting([.numericPad, .function]).isEmpty:
                onArrowUp?()
            case 125 where flags.subtracting([.numericPad, .function]).isEmpty:
                onArrowDown?()
            case 123 where flags.subtracting([.numericPad, .function]).isEmpty:
                onArrowLeft?()
            case 124 where flags.subtracting([.numericPad, .function]).isEmpty:
                onArrowRight?()
            case 36, 49 where flags.isEmpty:
                onActivate?()
            case 53 where flags.isEmpty:
                onEscape?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}
