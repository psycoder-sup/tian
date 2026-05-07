import SwiftUI

/// Root inspect panel view (FR-01 / FR-02).
///
/// Always renders the full panel; visibility toggling (showing the 22 px rail
/// vs the full panel) is handled by the call site (`SidebarContainerView.inspectColumn`).
/// Full panel: leading resize handle + VStack { header · body · status strip }.
///
/// Body switches on `tabState.activeTab` and per-tab data:
///   - `.files`: usual file-tree empty/loading/content states (FR-10–FR-18a).
///   - `.diff`:  `InspectDiffBody` (FR-T16/T17/T19).
///   - `.branch`: `InspectBranchBody` (FR-T19/T26/T27).
///
/// During the initial file scan we force-render the Files body regardless of
/// `tabState.activeTab` (FR-T16a). The tab row also mutes the Diff/Branch
/// pills in this state so users can't switch into a tab whose data depends on
/// scan completion.
struct InspectPanelView: View {
    @Bindable var panelState: InspectPanelState
    @Bindable var viewModel: InspectFileTreeViewModel
    @Bindable var tabState: InspectTabState
    let spaceName: String

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
                diffSummary: liveDiffSummary,
                branchLabel: liveBranchLabel
            )

            panelBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            InspectPanelStatusStrip(
                spaceName: spaceName,
                activeTab: effectiveActiveTab
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

    /// FR-T16a: while the initial scan is in flight we render the Files body
    /// even if the user previously selected Diff or Branch — the data those
    /// tabs need isn't ready yet, and the tab row is muted accordingly.
    private var effectiveActiveTab: InspectTab {
        viewModel.isInitialScanInFlight ? .files : tabState.activeTab
    }

    @ViewBuilder
    private var panelBody: some View {
        switch effectiveActiveTab {
        case .files:
            filesBody
        case .diff:
            InspectDiffBody(
                viewModel: tabState.diffViewModel,
                tabState: tabState,
                isNoRepo: isNoRepo
            )
        case .branch:
            InspectBranchBody(
                viewModel: tabState.branchViewModel,
                isNoRepo: isNoRepo
            )
        }
    }

    @ViewBuilder
    private var filesBody: some View {
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

    // MARK: - Live header data

    /// True when there's no resolvable git repo for this space. The Diff and
    /// Branch tabs share this state to render their FR-T19 placeholder.
    private var isNoRepo: Bool {
        viewModel.worktreeKind == .notARepo
            || viewModel.worktreeKind == .noWorkingDirectory
    }

    private var liveDiffSummary: InspectPanelInfoStrip.DiffSummary? {
        let files = tabState.diffViewModel.files
        if files.isEmpty {
            return InspectPanelInfoStrip.DiffSummary(fileCount: 0, additions: 0, deletions: 0)
        }
        let additions = files.reduce(0) { $0 + $1.additions }
        let deletions = files.reduce(0) { $0 + $1.deletions }
        return .init(fileCount: files.count, additions: additions, deletions: deletions)
    }

    private var liveBranchLabel: String? {
        // First lane is HEAD's lane (FR-T20 / GitCommitGraph contract).
        tabState.branchViewModel.graph?.lanes.first?.label
    }
}

// MARK: - Previews

#Preview("Visible – with data (empty tree)") {
    let panelState = InspectPanelState(isVisible: true, width: 320)
    let vm = InspectFileTreeViewModel()
    let tabState = InspectTabState()
    InspectPanelView(panelState: panelState, viewModel: vm, tabState: tabState, spaceName: "tian")
        .frame(height: 600)
        .background(Color.black)
}

#Preview("Loading") {
    let panelState = InspectPanelState(isVisible: true, width: 320)
    let vm = InspectFileTreeViewModel()
    let tabState = InspectTabState()
    InspectPanelView(panelState: panelState, viewModel: vm, tabState: tabState, spaceName: "tian")
        .frame(height: 600)
        .background(Color.black)
}

#Preview("Empty – no directory") {
    let panelState = InspectPanelState(isVisible: true, width: 320)
    let vm = InspectFileTreeViewModel()
    let tabState = InspectTabState()
    InspectPanelView(panelState: panelState, viewModel: vm, tabState: tabState, spaceName: "untitled")
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
    let tabState = InspectTabState()
    InspectPanelView(panelState: panelState, viewModel: vm, tabState: tabState, spaceName: "empty-space")
        .frame(height: 600)
        .background(Color.black)
}

#Preview("Diff tab – no-repo") {
    let panelState = InspectPanelState(isVisible: true, width: 320)
    let vm = InspectFileTreeViewModel()
    let tabState = InspectTabState(activeTab: .diff)
    InspectPanelView(panelState: panelState, viewModel: vm, tabState: tabState, spaceName: "scripts")
        .frame(height: 600)
        .background(Color.black)
}

#Preview("Branch tab – no-repo") {
    let panelState = InspectPanelState(isVisible: true, width: 320)
    let vm = InspectFileTreeViewModel()
    let tabState = InspectTabState(activeTab: .branch)
    InspectPanelView(panelState: panelState, viewModel: vm, tabState: tabState, spaceName: "scripts")
        .frame(height: 600)
        .background(Color.black)
}
