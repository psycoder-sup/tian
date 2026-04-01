import SwiftUI

/// Full-screen overlay for fuzzy-searching and switching between workspaces.
/// Activated by Cmd+Shift+W. Supports keyboard navigation, enter-to-switch,
/// and drag-and-drop reordering of workspace rows.
struct WorkspaceSwitcherOverlay: View {
    @Binding var isPresented: Bool
    let workspaceCollection: WorkspaceCollection

    @State private var query = ""
    @State private var selectedIndex = 0

    var body: some View {
        ZStack {
            // Dimmed backdrop — click to dismiss
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // Search field
                SwitcherSearchField(
                    text: $query,
                    onArrowDown: { moveSelection(by: 1) },
                    onArrowUp: { moveSelection(by: -1) },
                    onReturn: { confirmSelection() },
                    onEscape: { dismiss() }
                )
                .padding(12)

                Divider()

                // Results list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredWorkspaces.enumerated()), id: \.element.id) { index, workspace in
                                WorkspaceSwitcherRow(
                                    workspace: workspace,
                                    isSelected: index == selectedIndex,
                                    isActive: workspace.id == workspaceCollection.activeWorkspaceID
                                )
                                .id(workspace.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    switchToWorkspace(workspace.id)
                                }
                                .draggable(WorkspaceDragItem(workspaceID: workspace.id))
                                .accessibilityLabel("Workspace: \(workspace.name), \(workspace.spaces.count) spaces")
                                .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                            }
                            .dropDestination(for: WorkspaceDragItem.self) { items, location in
                                handleDrop(items: items, location: location)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: selectedIndex) { _, newIndex in
                        let workspaces = filteredWorkspaces
                        if newIndex >= 0 && newIndex < workspaces.count {
                            proxy.scrollTo(workspaces[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 400)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Workspace Switcher")
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    // MARK: - Filtered Results

    private var filteredWorkspaces: [Workspace] {
        let workspaces = workspaceCollection.workspaces
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return workspaces
        }

        return workspaces
            .compactMap { workspace -> (Workspace, Int)? in
                guard let result = FuzzyMatch.score(query: query, candidate: workspace.name) else {
                    return nil
                }
                return (workspace, result.score)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        let count = filteredWorkspaces.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    private func confirmSelection() {
        let workspaces = filteredWorkspaces
        guard selectedIndex >= 0 && selectedIndex < workspaces.count else { return }
        switchToWorkspace(workspaces[selectedIndex].id)
    }

    private func switchToWorkspace(_ id: UUID) {
        workspaceCollection.activateWorkspace(id: id)
        dismiss()
    }

    private func dismiss() {
        isPresented = false
    }

    private func handleDrop(items: [WorkspaceDragItem], location: CGPoint) -> Bool {
        guard let item = items.first,
              let sourceIndex = workspaceCollection.workspaces.firstIndex(where: { $0.id == item.workspaceID }) else {
            return false
        }
        // Drop at end by default
        let destinationIndex = workspaceCollection.workspaces.count - 1
        workspaceCollection.reorderWorkspace(from: sourceIndex, to: destinationIndex)
        return true
    }
}

// MARK: - Workspace Row

private struct WorkspaceSwitcherRow: View {
    let workspace: Workspace
    let isSelected: Bool
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)

                Text("\(workspace.spaces.count) space\(workspace.spaces.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.8) : Color.clear)
                .padding(.horizontal, 4)
        )
    }
}

// MARK: - Search Field (NSViewRepresentable)

/// AppKit-backed search field for reliable first-responder behavior.
private struct SwitcherSearchField: NSViewRepresentable {
    @Binding var text: String
    var onArrowDown: () -> Void
    var onArrowUp: () -> Void
    var onReturn: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search workspaces..."
        field.isBordered = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16)
        field.delegate = context.coordinator

        // Become first responder after view is installed
        DispatchQueue.main.async { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: SwitcherSearchField

        init(parent: SwitcherSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onArrowDown()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onArrowUp()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onReturn()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }
}
