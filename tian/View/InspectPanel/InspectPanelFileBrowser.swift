import SwiftUI

/// Files-tab body: scrollable LazyVStack of rows (FR-12 / FR-13).
///
/// v1's 24 px subheader (FR-11) has been removed — that context information
/// now lives in `InspectPanelInfoStrip` (FR-T09).
struct InspectPanelFileBrowser: View {
    @Bindable var viewModel: InspectFileTreeViewModel
    let spaceName: String

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.visibleRows) { node in
                    InspectPanelFileRow(
                        node: node,
                        depth: node.depth,
                        isExpanded: viewModel.expandedPaths.contains(node.id),
                        isSelected: viewModel.selectedPath == node.id,
                        status: viewModel.statusByRelativePath[node.relativePath],
                        isIgnored: viewModel.isIgnored(node.relativePath),
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

// MARK: - Preview

#Preview("File browser") {
    let vm = InspectFileTreeViewModel()
    // Manually inject preview state via allNodesForTest is not possible
    // since visibleRows are private; use a real-looking empty state instead.
    InspectPanelFileBrowser(viewModel: vm, spaceName: "tian")
        .frame(width: 320, height: 400)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
