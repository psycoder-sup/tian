import SwiftUI
import AppKit

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
                for space in workspace.spaceCollection.spaces {
                    items.append(.spaceRow(workspace, space))
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
                        isCreatingWorktree: worktreeOrchestrator.isCreating,
                        onToggleDisclosure: { toggleDisclosure(workspace.id) },
                        onAddSpace: { addSpace(to: workspace) },
                        onNewWorktreeSpace: {
                            NotificationCenter.default.post(
                                name: .showWorktreeBranchInput,
                                object: workspaceCollection,
                                userInfo: [
                                    Notification.worktreeWorkingDirectoryKey: workspace.spaceCollection.resolveWorkingDirectory(),
                                    Notification.worktreeWorkspaceIDKey: workspace.id
                                ]
                            )
                        },
                        onSetDirectory: { url in
                            workspace.setDefaultWorkingDirectory(url)
                        },
                        onClose: { workspaceCollection.removeWorkspace(id: workspace.id) }
                    )

                    if disclosedWorkspaces.contains(workspace.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(workspace.spaceCollection.spaces) { space in
                                SidebarSpaceRowView(
                                    space: space,
                                    isActive: workspace.id == workspaceCollection.activeWorkspaceID
                                        && space.id == workspace.spaceCollection.activeSpaceID,
                                    isKeyboardSelected: selectedIndex == flatIndex(for: .spaceRow(workspace, space)),
                                    onSelect: { selectSpace(workspace: workspace, spaceID: space.id) },
                                    onSetDirectory: { url in
                                        space.defaultWorkingDirectory = url
                                    },
                                    onClose: { closeSpace(space, in: workspace) }
                                )
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                        .padding(.bottom, 4)
                        .dropDestination(for: SpaceDragItem.self) { items, _ in
                            handleSpaceDrop(items: items, spaceCollection: workspace.spaceCollection)
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
            if let id = workspaceCollection.activeWorkspaceID {
                disclosedWorkspaces.insert(id)
            }
        }
        .onChange(of: sidebarState.focusTarget) { _, newTarget in
            if newTarget == .sidebar {
                selectedIndex = 0
            } else {
                selectedIndex = nil
            }
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

    private func handleSpaceDrop(items: [SpaceDragItem], spaceCollection: SpaceCollection) -> Bool {
        guard let item = items.first,
              let sourceIndex = spaceCollection.spaces.firstIndex(where: { $0.id == item.spaceID }) else {
            return false
        }
        let destinationIndex = spaceCollection.spaces.count - 1
        if sourceIndex != destinationIndex {
            spaceCollection.reorderSpace(from: sourceIndex, to: destinationIndex)
        }
        return true
    }

    // MARK: - Disclosure

    private func toggleDisclosure(_ id: UUID) {
        if disclosedWorkspaces.contains(id) {
            disclosedWorkspaces.remove(id)
        } else {
            disclosedWorkspaces.insert(id)
        }
        clampSelectedIndex()
    }

    // MARK: - Add Space

    private func addSpace(to workspace: Workspace) {
        let wd = workspace.spaceCollection.resolveWorkingDirectory()
        workspace.spaceCollection.createSpace(workingDirectory: wd)
        disclosedWorkspaces.insert(workspace.id)
    }

    // MARK: - Close Space

    private func closeSpace(_ space: SpaceModel, in workspace: Workspace) {
        guard let wtPath = space.worktreePath else {
            workspace.spaceCollection.removeSpace(id: space.id)
            return
        }
        guard let window = NSApp.keyWindow else { return }
        WorktreeCloseDialog.show(on: window, worktreePath: wtPath.path) { response in
            switch response {
            case .removeWorktreeAndClose:
                Task {
                    try? await worktreeOrchestrator.removeWorktreeSpace(
                        spaceID: space.id, force: false
                    )
                }
            case .closeOnly:
                workspace.spaceCollection.removeSpace(id: space.id)
            case .cancel:
                break
            }
        }
    }

    // MARK: - Space Selection

    private func selectSpace(workspace: Workspace, spaceID: UUID) {
        workspaceCollection.activateWorkspace(id: workspace.id)
        workspace.spaceCollection.activateSpace(id: spaceID)
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
        case .spaceRow(let ws, let space):
            selectSpace(workspace: ws, spaceID: space.id)
        }
    }

    private func handleEscape() {
        sidebarState.focusTarget = .terminal
    }
}

// MARK: - Sidebar Item

private enum SidebarItem {
    case workspaceHeader(Workspace)
    case spaceRow(Workspace, SpaceModel)

    var id: String {
        switch self {
        case .workspaceHeader(let ws): "header-\(ws.id)"
        case .spaceRow(_, let space): "space-\(space.id)"
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
