import SwiftUI

/// Root inspect panel view (FR-01 / FR-02).
///
/// Switches between the collapsed 22 px rail (FR-07) and the full panel.
/// Full panel: leading resize handle + VStack { header · body · status strip }.
/// Body switches on view-model state:
///   - noWorkingDirectory  → `InspectPanelNoDirectoryView`
///   - initial scan, fast  → `InspectPanelLoadingView`
///   - initial scan, slow  → `InspectPanelSlowLoadingView`
///   - scan done, no rows  → `InspectPanelEmptyContentView`
///   - else                → `InspectPanelFileBrowser`
///
/// No live wire-up to a workspace/space yet — task 7 plugs in `spaceName`
/// and `viewModel`. Pass them via init parameters for now.
struct InspectPanelView: View {
    @Bindable var panelState: InspectPanelState
    @Bindable var viewModel: InspectFileTreeViewModel
    let spaceName: String

    // MARK: - Body

    var body: some View {
        if panelState.isVisible {
            fullPanel
        } else {
            InspectPanelRail {
                panelState.isVisible = true
            }
        }
    }

    // MARK: - Full panel

    private var fullPanel: some View {
        HStack(spacing: 0) {
            InspectPanelResizeHandle(panelState: panelState)

            VStack(spacing: 0) {
                InspectPanelHeader(
                    spaceName: spaceName,
                    worktreeKind: viewModel.worktreeKind,
                    onClose: { panelState.isVisible = false }
                )

                panelBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                InspectPanelStatusStrip(spaceName: spaceName)
            }
        }
        .frame(width: panelState.width)
        .frame(maxHeight: .infinity)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255).opacity(0.55))
    }

    // MARK: - Body content switch

    @ViewBuilder
    private var panelBody: some View {
        if viewModel.worktreeKind == .noWorkingDirectory
           && !viewModel.isInitialScanInFlight {
            InspectPanelNoDirectoryView()
        } else if viewModel.isInitialScanInFlight && viewModel.isInitialScanSlow {
            InspectPanelSlowLoadingView()
        } else if viewModel.isInitialScanInFlight {
            InspectPanelLoadingView()
        } else if viewModel.visibleRows.isEmpty {
            InspectPanelEmptyContentView()
        } else {
            InspectPanelFileBrowser(viewModel: viewModel, spaceName: spaceName)
        }
    }
}

// MARK: - Previews

#Preview("Visible – with data (empty tree)") {
    let panelState = InspectPanelState(isVisible: true, width: 320)
    let vm = InspectFileTreeViewModel()
    InspectPanelView(panelState: panelState, viewModel: vm, spaceName: "tian")
        .frame(height: 600)
        .background(Color.black)
}

#Preview("Loading") {
    let panelState = InspectPanelState(isVisible: true, width: 320)
    // Manually set loading state is not directly possible through public API
    // without triggering setRoot; show the loading view directly.
    let vm = InspectFileTreeViewModel()
    InspectPanelView(panelState: panelState, viewModel: vm, spaceName: "tian")
        .frame(height: 600)
        .background(Color.black)
}

#Preview("Empty – no directory") {
    let panelState = InspectPanelState(isVisible: true, width: 320)
    let vm = InspectFileTreeViewModel()
    // worktreeKind starts as .noWorkingDirectory (default), isInitialScanInFlight = false
    InspectPanelView(panelState: panelState, viewModel: vm, spaceName: "untitled")
        .frame(height: 600)
        .background(Color.black)
}

#Preview("Hidden – rail") {
    let panelState = InspectPanelState(isVisible: false, width: 320)
    let vm = InspectFileTreeViewModel()
    HStack(spacing: 0) {
        Color.gray.opacity(0.2).frame(maxWidth: .infinity)
        InspectPanelView(panelState: panelState, viewModel: vm, spaceName: "tian")
    }
    .frame(height: 600)
    .background(Color.black)
}

#Preview("Empty – no content") {
    let panelState = InspectPanelState(isVisible: true, width: 320)
    let vm = InspectFileTreeViewModel()
    // visibleRows is empty and scan is not in flight — shows "Nothing to show."
    // worktreeKind needs to be non-.noWorkingDirectory; we can't set it without
    // driving the view-model through setRoot. The preview shows noWorkingDirectory state.
    InspectPanelView(panelState: panelState, viewModel: vm, spaceName: "empty-space")
        .frame(height: 600)
        .background(Color.black)
}
