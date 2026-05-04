import SwiftUI

/// Files-tab body: subheader (FR-11) + scrollable LazyVStack of rows (FR-12 / FR-13).
struct InspectPanelFileBrowser: View {
    @Bindable var viewModel: InspectFileTreeViewModel
    let spaceName: String

    // MARK: - Subheader (FR-11)

    private var contextSuffix: String {
        viewModel.worktreeKind.label?.uppercased() ?? ""
    }

    private var subheader: some View {
        HStack(spacing: 0) {
            Image(systemName: "folder.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color(red: 96/255, green: 165/255, blue: 250/255))
                .frame(width: 14)

            Spacer().frame(width: 5)

            Text(spaceName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if !contextSuffix.isEmpty {
                Text(contextSuffix)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .padding(.trailing, 10)
            }
        }
        .frame(height: 24)
        .padding(.leading, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
        }
    }

    // MARK: - Depth helper

    /// Computes the display depth of a node from its relativePath slash count.
    private func depth(of node: FileTreeNode) -> Int {
        node.relativePath.filter { $0 == "/" }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            subheader

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.visibleRows) { node in
                        InspectPanelFileRow(
                            node: node,
                            depth: depth(of: node),
                            isExpanded: viewModel.expandedPaths.contains(node.id),
                            isSelected: viewModel.selectedPath == node.id,
                            status: viewModel.statusByRelativePath[node.relativePath],
                            onTap: {
                                if node.isDirectory {
                                    viewModel.toggle(node.id)
                                } else {
                                    viewModel.select(node.id)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("File browser") {
    let vm = InspectFileTreeViewModel()
    // Manually inject preview state via allNodesForTest is not possible
    // since visibleRows are private; use a real-looking empty state instead.
    InspectPanelFileBrowser(viewModel: vm, spaceName: "tian")
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
