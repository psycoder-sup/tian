import SwiftUI
import AppKit

struct SidebarExpandedContentView: View {
    let workspaceCollection: WorkspaceCollection
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
                ForEach(Array(flatItems.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case .workspaceHeader(let workspace):
                        SidebarWorkspaceHeaderView(
                            workspace: workspace,
                            isExpanded: disclosedWorkspaces.contains(workspace.id),
                            isActive: workspace.id == workspaceCollection.activeWorkspaceID,
                            isKeyboardSelected: selectedIndex == index,
                            onToggleDisclosure: { toggleDisclosure(workspace.id) },
                            onAddSpace: { addSpace(to: workspace) }
                        )

                    case .spaceRow(let workspace, let space):
                        SidebarSpaceRowView(
                            space: space,
                            isActive: workspace.id == workspaceCollection.activeWorkspaceID
                                && space.id == workspace.spaceCollection.activeSpaceID,
                            isKeyboardSelected: selectedIndex == index,
                            onSelect: { selectSpace(workspace: workspace, spaceID: space.id) }
                        )
                    }
                }
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
            disclosedWorkspaces.insert(workspaceCollection.activeWorkspaceID)
        }
        .onChange(of: sidebarState.focusTarget) { _, newTarget in
            if newTarget == .sidebar {
                selectedIndex = 0
            } else {
                selectedIndex = nil
            }
        }
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
