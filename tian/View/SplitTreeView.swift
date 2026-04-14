import SwiftUI

/// Recursively renders a `PaneNode` tree as nested split views.
struct SplitTreeView: View {
    let node: PaneNode
    let viewModel: PaneViewModel

    var body: some View {
        switch node {
        case .leaf(let paneID, _):
            PaneView(paneID: paneID, viewModel: viewModel)
                .id(paneID)

        case .split(let id, let direction, let ratio, let first, let second):
            SplitContainerView(
                splitID: id,
                direction: direction,
                ratio: ratio,
                viewModel: viewModel
            ) {
                SplitTreeView(node: first, viewModel: viewModel)
            } second: {
                SplitTreeView(node: second, viewModel: viewModel)
            }
            .id(id)
        }
    }
}
