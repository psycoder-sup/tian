import SwiftUI

/// 64 px header for the Inspect panel (FR-T01).
///
/// Composed of two rows:
///   - 38 px `InspectPanelTabRow`  — FR-T01 / FR-T02 / FR-T03
///   - 26 px `InspectPanelInfoStrip` — FR-T06 / FR-T07 / FR-T08
///
/// Callers pass the `InspectTabState` binding; the header owns no local
/// selection state. The floating `InspectPanelRail` (in `SidebarContainerView`)
/// handles the *re-open* case — the in-row `onHide` callback covers *hide*.
struct InspectPanelHeader: View {
    static let height: CGFloat = InspectPanelTabRow.height + InspectPanelInfoStrip.height

    @Bindable var tabState: InspectTabState
    let spaceName: String
    let worktreeKind: WorktreeKind
    /// `true` during initial file-tree scan (FR-T16a — mutes Diff / Branch tabs).
    let isInitialScan: Bool
    /// Info-strip data for the Diff tab. Passed through from the call site;
    /// `nil` shows "No changes".
    let diffSummary: InspectPanelInfoStrip.DiffSummary?
    /// Active branch label or short SHA for detached HEAD.
    let branchLabel: String?
    /// Fires when the user taps the in-row hide button.
    let onHide: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            InspectPanelTabRow(
                tabState: tabState,
                isInitialScan: isInitialScan,
                onHide: onHide
            )

            InspectPanelInfoStrip(
                activeTab: tabState.activeTab,
                filesContext: .init(
                    spaceName: spaceName,
                    worktreeKindLabel: worktreeKind.label
                ),
                diffSummary: diffSummary,
                branchLabel: branchLabel,
                isNoRepo: worktreeKind == .notARepo || worktreeKind == .noWorkingDirectory
            )
        }
    }
}

// MARK: - Previews

#Preview("Header – Files / worktree") {
    let state = InspectTabState()
    InspectPanelHeader(
        tabState: state,
        spaceName: "tian",
        worktreeKind: .linkedWorktree,
        isInitialScan: false,
        diffSummary: nil,
        branchLabel: "main",
        onHide: {}
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Header – Diff / with changes") {
    let state = InspectTabState(activeTab: .diff)
    InspectPanelHeader(
        tabState: state,
        spaceName: "my-project",
        worktreeKind: .mainCheckout,
        isInitialScan: false,
        diffSummary: .init(fileCount: 3, additions: 54, deletions: 12),
        branchLabel: "feat/new-ui",
        onHide: {}
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Header – Branch") {
    let state = InspectTabState(activeTab: .branch)
    InspectPanelHeader(
        tabState: state,
        spaceName: "tian",
        worktreeKind: .linkedWorktree,
        isInitialScan: false,
        diffSummary: nil,
        branchLabel: "feat/inspect-panel-tabs",
        onHide: {}
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Header – initial scan") {
    let state = InspectTabState()
    InspectPanelHeader(
        tabState: state,
        spaceName: "tian",
        worktreeKind: .mainCheckout,
        isInitialScan: true,
        diffSummary: nil,
        branchLabel: nil,
        onHide: {}
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Header – no working dir") {
    let state = InspectTabState()
    InspectPanelHeader(
        tabState: state,
        spaceName: "untitled",
        worktreeKind: .noWorkingDirectory,
        isInitialScan: false,
        diffSummary: nil,
        branchLabel: nil,
        onHide: {}
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
