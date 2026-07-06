import SwiftUI

struct SidebarExpandedContentView: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator
    let sidebarState: SidebarState

    @State private var selectedIndex: Int?
    @State private var disclosedWorkspaces: Set<UUID> = []

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
                ForEach(workspaceCollection.workspaces) { workspace in
                    SidebarWorkspaceHeaderView(
                        workspace: workspace,
                        isExpanded: disclosedWorkspaces.contains(workspace.id),
                        isActive: workspace.id == workspaceCollection.activeWorkspaceID,
                        isKeyboardSelected: selectedIndex == flatIndex(for: .workspaceHeader(workspace)),
                        onToggleDisclosure: { toggleDisclosure(workspace.id) },
                        onAddSession: { addSession(to: workspace) },
                        onSetDirectory: { url in
                            workspace.setDefaultWorkingDirectory(url)
                        },
                        onClose: { workspaceCollection.removeWorkspace(id: workspace.id) }
                    )

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
                        .dropDestination(for: SessionDragItem.self) { items, _ in
                            handleSessionDrop(items: items, sessionCollection: workspace.sessionCollection)
                        }
                    }
                }
            }
            .dropDestination(for: WorkspaceDragItem.self) { items, _ in
                handleWorkspaceDrop(items: items)
            }
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

    // MARK: - Drag and Drop

    private func handleWorkspaceDrop(items: [WorkspaceDragItem]) -> Bool {
        guard let item = items.first,
              let sourceIndex = workspaceCollection.workspaces.firstIndex(where: { $0.id == item.workspaceID }) else {
            return false
        }
        let destinationIndex = workspaceCollection.workspaces.count - 1
        if sourceIndex != destinationIndex {
            workspaceCollection.reorderWorkspace(from: sourceIndex, to: destinationIndex)
        }
        return true
    }

    private func handleSessionDrop(items: [SessionDragItem], sessionCollection: SessionCollection) -> Bool {
        guard let item = items.first,
              let sourceIndex = sessionCollection.sessions.firstIndex(where: { $0.id == item.sessionID }) else {
            return false
        }
        let destinationIndex = sessionCollection.sessions.count - 1
        if sourceIndex != destinationIndex {
            sessionCollection.reorderSession(from: sourceIndex, to: destinationIndex)
        }
        return true
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
            toggleDisclosure(ws.id)
        case .sessionRow(let ws, let session):
            selectSession(workspace: ws, sessionID: session.id)
        }
    }

    private func handleEscape() {
        sidebarState.focusTarget = .terminal
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
