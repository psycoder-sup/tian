import SwiftUI

/// Root inspect panel view (FR-01 / FR-02).
///
/// Always renders the full panel; visibility toggling (showing the 22 px rail
/// vs the full panel) is handled by the call site (`SidebarContainerView.inspectColumn`).
/// Full panel: leading resize handle + VStack { header · body · status strip }.
/// Body switches on view-model state:
///   - noWorkingDirectory  → `InspectPanelNoDirectoryView`
///   - initial scan, fast  → `InspectPanelLoadingView`
///   - initial scan, slow  → `InspectPanelSlowLoadingView`
///   - scan done, no rows  → `InspectPanelEmptyContentView`
///   - else                → `InspectPanelFileBrowser`.
struct InspectPanelView: View {
    @Bindable var panelState: InspectPanelState
    @Bindable var viewModel: InspectFileTreeViewModel
    let spaceName: String

    /// Tab-selection + diff/branch view-model state. Defaults to `.files`
    /// on first appearance. Task 10 will lift this to the call site so the
    /// active tab survives space switches.
    @State private var tabState = InspectTabState()

    // MARK: - Body

    var body: some View {
        fullPanel
    }

    // MARK: - Full panel

    private var fullPanel: some View {
        VStack(spacing: 0) {
            InspectPanelHeader(
                tabState: tabState,
                spaceName: spaceName,
                worktreeKind: viewModel.worktreeKind,
                isInitialScan: viewModel.isInitialScanInFlight,
                diffSummary: nil,   // wired in Task 10
                branchLabel: nil,   // wired in Task 10
                onHide: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        panelState.isVisible = false
                    }
                }
            )

            panelBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            InspectPanelStatusStrip(
                spaceName: spaceName,
                activeTab: tabState.activeTab
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 12, style: .continuous))
        .padding(4)
        .overlay(alignment: .leading) {
            InspectPanelResizeHandle(panelState: panelState)
        }
        .frame(width: panelState.width)
        .frame(maxHeight: .infinity)
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

#Preview("Hidden – toggle button") {
    Color.gray.opacity(0.2)
        .overlay(alignment: .topTrailing) {
            InspectPanelRail(action: {})
                .padding(.top, 10)
                .padding(.trailing, 10)
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
