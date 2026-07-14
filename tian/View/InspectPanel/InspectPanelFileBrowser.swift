import SwiftUI

/// Files-tab body: scrollable LazyVStack of rows (FR-12 / FR-13).
///
/// v1's 24 px subheader (FR-11) has been removed — that context information
/// now lives in `InspectPanelInfoStrip` (FR-T09).
struct InspectPanelFileBrowser: View {
    @Bindable var viewModel: InspectFileTreeViewModel
    let spaceName: String
    /// Invoked with a file's absolute path when it is opened (double-clicked).
    var onOpenFile: (String) -> Void = { _ in }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
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
                            },
                            onOpen: {
                                if !node.isDirectory { onOpenFile(node.id) }
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if case .truncated(let reason, let shown) = viewModel.scanOutcome {
                InspectPanelTruncationBanner(reason: reason, shown: shown)
            }
        }
    }
}

// MARK: - Truncation banner

/// Persistent footer strip shown when a bound cut the walk short
/// (`InspectScanOutcome.truncated`) — the tree above it is partial. The text
/// names the bound that was actually hit and the count actually rendered: a
/// depth-pruned tree of 300 files must not claim it's showing the first 20,000.
/// Matches the `InspectPanelStatusStrip` idiom: fixed height, hairline
/// divider, small monospaced label.
private struct InspectPanelTruncationBanner: View {
    let reason: InspectScanTruncation
    /// Paths actually in the tree above.
    let shown: Int

    static let height: CGFloat = 20

    private var message: String {
        switch reason {
        case .entryCap, .examinedCap:
            return "Showing first \(shown.formatted()) items — this directory is too large to index fully"
        case .depthCap(let depth):
            return "Showing \(shown.formatted()) items — folders nested deeper than \(depth) levels aren't indexed"
        }
    }

    var body: some View {
        Text(message)
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.35))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Self.height)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 0.5)
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
