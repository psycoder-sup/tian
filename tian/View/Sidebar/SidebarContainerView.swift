import Accessibility
import AppKit
import SwiftUI

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let focusSidebar = Notification.Name("focusSidebar")
    static let toggleDebugOverlay = Notification.Name("toggleDebugOverlay")
    static let showCreateSpaceInput = Notification.Name("showCreateSpaceInput")
}

extension Notification {
    static let createSpaceWorkspaceIDKey = "createSpaceWorkspaceID"
}

struct SidebarContainerView: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator
    /// Bottom padding applied only to the space-content area so it leaves
    /// room for an overlapping status bar. The sidebar panel keeps its full
    /// height and visually extends over the status bar on the left.
    var bottomContentInset: CGFloat = 0

    @State private var sidebarState = SidebarState()
    @State private var lastContainerSize: CGSize = .zero
    @State private var nsWindow: NSWindow?
    @State private var announcementsEnabled = false
    /// In-flight git-status fetch for the inspect panel. Cancelled on space
    /// switch or when a newer repoStatuses change fires — ensures stale results
    /// from a previous space never land in the current tree (FR-28a).
    @State private var inspectGitStatusTask: Task<Void, Never>?

    private var displayedSpaceCollection: SpaceCollection? {
        workspaceCollection.activeSpaceCollection
    }

    private var activeWorkspace: Workspace? {
        workspaceCollection.activeWorkspace
    }

    private var activeSpace: SpaceModel? {
        displayedSpaceCollection?.activeSpace
    }

    /// Leading inset that reserves room for the traffic lights + sidebar
    /// toggle when the sidebar is collapsed, and matches the sidebar width
    /// when expanded. 104pt = 80pt traffic-light gutter + 6pt HStack spacing
    /// + ~18pt toggle button. Used to size the toggle button overlay frame.
    private var toggleGutterWidth: CGFloat {
        max(sidebarState.mode.width, 104)
    }

    /// Inset applied to the leading edge of the leftmost section's tab bar
    /// so the bar doesn't slide under the sidebar toggle / traffic lights.
    /// Drops to zero when the sidebar is wide enough to swallow the toggle.
    private var sectionTabBarLeadingInset: CGFloat {
        max(104 - sidebarState.mode.width, 0)
    }

    /// Inset applied to the trailing edge of the rightmost section's tab
    /// bar so the bar doesn't slide under the inspect-panel rail. Zero
    /// when the panel is open (rail moves with the panel column).
    private var sectionTabBarTrailingInset: CGFloat {
        guard let workspace = activeWorkspace,
              !workspace.inspectPanelState.isVisible else { return 0 }
        return 26
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarAndContent
            inspectColumn
        }
        .overlay(alignment: .topTrailing) { inspectToggleOverlay }
        .overlay(alignment: .bottomLeading) { terminalToggleStatusBarOverlay }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowAccessor(window: $nsWindow))
        .modifier(SidebarNotificationModifier(
            workspaceCollection: workspaceCollection,
            sidebarState: sidebarState
        ))
        .onChange(of: sidebarState.focusTarget) { _, newTarget in
            if newTarget == .terminal {
                returnFocusToActivePane()
            }
        }
        .onChange(of: workspaceCollection.activeWorkspaceID) { _, _ in
            if let spaceCollection = displayedSpaceCollection {
                spaceCollection.activeSpace?.activeTab?.paneViewModel.containerSize = lastContainerSize
            }
            if announcementsEnabled, let name = workspaceCollection.activeWorkspace?.name {
                AccessibilityNotification.Announcement("Workspace: \(name)").post()
            }
            updateInspectPanelRoot()
            refreshInspectPanelStatus()
        }
        .onChange(of: displayedSpaceCollection?.activeSpaceID) { _, _ in
            if announcementsEnabled, let name = displayedSpaceCollection?.activeSpace?.name {
                AccessibilityNotification.Announcement("Space: \(name)").post()
            }
            updateInspectPanelRoot()
            refreshInspectPanelStatus()
        }
        .modifier(InspectPanelWiringModifier(
            activeSpace: activeSpace,
            activeWorkspace: activeWorkspace,
            updateRoot: updateInspectPanelRoot,
            refreshStatus: refreshInspectPanelStatus
        ))
        .modifier(InspectPanelTabsWiringModifier(
            activeSpace: activeSpace,
            activeWorkspace: activeWorkspace,
            refreshDiff: refreshInspectPanelDiff,
            refreshBranch: refreshInspectPanelBranch,
            wireDiffCollapsePrune: wireDiffCollapsePrune
        ))
        .onChange(of: displayedSpaceCollection?.activeSpace?.activeTabID) { _, _ in
            if announcementsEnabled, let name = displayedSpaceCollection?.activeSpace?.activeTab?.displayName {
                AccessibilityNotification.Announcement("Tab: \(name)").post()
            }
        }
        .task {
            updateInspectPanelRoot()
            refreshInspectPanelStatus()
            wireDiffCollapsePrune()
            refreshInspectPanelDiff()
            refreshInspectPanelBranch()
            try? await Task.sleep(for: .milliseconds(500))
            announcementsEnabled = true
        }
    }

    // MARK: - Layout

    private var sidebarAndContent: some View {
        ZStack(alignment: .topLeading) {
            if sidebarState.isExpanded {
                SidebarPanelView(
                    workspaceCollection: workspaceCollection,
                    worktreeOrchestrator: worktreeOrchestrator,
                    sidebarState: sidebarState
                )
                .frame(width: sidebarState.mode.width)
            }

            spaceContentStack
                .padding(.leading, sidebarState.mode.width)
                .padding(.bottom, bottomContentInset)

            HStack(spacing: 6) {
                Color.clear.frame(width: 80)
                SidebarToggleButton(workspaceCollection: workspaceCollection)
            }
            .frame(width: toggleGutterWidth, height: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var inspectColumn: some View {
        if let workspace = activeWorkspace {
            let panelState = workspace.inspectPanelState
            InspectPanelView(
                panelState: panelState,
                viewModel: workspace.inspectFileTreeViewModel,
                tabState: workspace.inspectTabState,
                spaceName: activeSpace?.name ?? workspace.name
            )
            // Animated width: 0 when hidden, panelState.width when visible.
            // .trailing alignment + .clipped() makes the panel slide in from
            // the window's trailing edge instead of fading or squashing.
            .frame(
                width: panelState.isVisible ? panelState.width : 0,
                alignment: .trailing
            )
            .clipped()
        }
    }

    /// Floating inspect-panel toggle. Anchored to the window's top-trailing
    /// corner (overlay on the outer HStack, not on `sidebarAndContent`) so
    /// its absolute position is identical whether the panel is open or
    /// collapsed. Vertical inset is tuned so the icon's center lines up
    /// with the section tab bar's button row (tab bar is 48 pt tall →
    /// button center at y = 24, icon of 22 pt with top inset 13 → center
    /// at y = 24).
    @ViewBuilder
    private var inspectToggleOverlay: some View {
        // Single, always-visible toggle anchored at the window's top-trailing
        // corner. When the panel is open it sits visually over the empty
        // right side of the tab row; when collapsed it floats alone in the
        // same spot — so the toggle never moves. The tab row no longer hosts
        // its own hide button.
        if let workspace = activeWorkspace {
            InspectPanelRail(
                action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        workspace.inspectPanelState.isVisible.toggle()
                    }
                },
                accessibilityTitle: workspace.inspectPanelState.isVisible
                    ? "Hide inspect panel"
                    : "Show inspect panel"
            )
            .padding(.top, 13)
            .padding(.trailing, 10)
        }
    }

    /// Inline show/hide-terminal toggle anchored to the bottom-leading
    /// corner so it sits inside the status-bar strip, just to the right of
    /// the sidebar's visual edge. Hidden when no space is active.
    @ViewBuilder
    private var terminalToggleStatusBarOverlay: some View {
        if let space = activeSpace, bottomContentInset > 0 {
            TerminalToggleStatusBarButton(space: space)
                .padding(.leading, toggleGutterWidth + 4)
                .frame(height: bottomContentInset)
        }
    }

    /// Re-roots the workspace's inspect file tree to the active space's
    /// resolved working directory (FR-10). Called whenever the active
    /// workspace, active space, or either's working directory changes.
    private func updateInspectPanelRoot() {
        guard let workspace = activeWorkspace else { return }
        let newRoot = workspace.inspectPanelRoot(for: activeSpace)
        if workspace.inspectFileTreeViewModel.rootDirectory != newRoot {
            workspace.inspectFileTreeViewModel.setRoot(newRoot)
        }
    }

    /// Fetches the full (uncapped) git diff for the active space's root and
    /// pushes the result into the inspect panel view model so file badges
    /// reflect the current git status (FR-19, FR-27).
    ///
    /// FR-22: Directories with no git repo skip the fetch; `updateStatus([])` is
    /// called to ensure stale badges from a previous space are cleared.
    ///
    /// Cancels any in-flight fetch before launching a new one so stale results
    /// from a slow git invocation never overwrite fresher data (FR-28a).
    private func refreshInspectPanelStatus() {
        guard let workspace = activeWorkspace else { return }
        let viewModel = workspace.inspectFileTreeViewModel

        // Resolved root for the current space — must match what the file tree shows.
        guard let root = workspace.inspectPanelRoot(for: activeSpace) else {
            // No root at all: clear any lingering badges and bail.
            viewModel.updateStatus([])
            return
        }

        // FR-22: if the active space has no pinned git repos, the root is not
        // inside a git repo. Skip the fetch and clear any stale badges so the
        // tree renders without badges, matching the "local" context-suffix state.
        let hasRepo = !(activeSpace?.gitContext.repoStatuses.isEmpty ?? true)
        guard hasRepo else {
            viewModel.updateStatus([])
            return
        }

        // Cancel the previous in-flight fetch before starting a new one.
        inspectGitStatusTask?.cancel()
        let rootPath = root.path
        inspectGitStatusTask = Task { [weak viewModel] in
            let result = await GitStatusService.diffStatusFull(directory: rootPath)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                viewModel?.updateStatus(result.files)
            }
        }
    }

    /// Schedules a refresh of `InspectDiffViewModel` against the active
    /// space's working directory. Called on space switch, workspace switch,
    /// and on every `repoStatuses` change (FR-T18 — the view-model handles
    /// debounce + cancel-on-new). Clears state when the directory has no
    /// resolvable git repo so stale diffs don't survive a space switch.
    private func refreshInspectPanelDiff() {
        guard let workspace = activeWorkspace else { return }
        let diffVM = workspace.inspectTabState.diffViewModel

        guard let root = workspace.inspectPanelRoot(for: activeSpace) else {
            diffVM.scheduleRefresh(directory: nil)
            return
        }
        // FR-T19: outside a git repo, the Diff body shows the no-repo
        // placeholder. Clear the view-model so we don't show stale data
        // when the user moves between repo and non-repo spaces.
        let hasRepo = !(activeSpace?.gitContext.repoStatuses.isEmpty ?? true)
        guard hasRepo else {
            diffVM.scheduleRefresh(directory: nil)
            return
        }
        diffVM.scheduleRefresh(directory: root.path)
    }

    /// Schedules a refresh of `InspectBranchViewModel` against the active
    /// space's working directory + first pinned repo (FR-T28). Called on
    /// space/workspace switches and whenever `branchGraphDirty` changes for
    /// the active space. The Branch view-model clears the dirty flag on
    /// successful completion.
    private func refreshInspectPanelBranch() {
        guard let workspace = activeWorkspace else { return }
        let branchVM = workspace.inspectTabState.branchViewModel

        guard let root = workspace.inspectPanelRoot(for: activeSpace) else {
            branchVM.scheduleRefresh(directory: nil, repoID: nil, in: nil)
            return
        }
        // FR-T19: outside a git repo, render no-repo placeholder.
        guard let space = activeSpace,
              let repoID = space.gitContext.pinnedRepoOrder.first else {
            branchVM.scheduleRefresh(directory: nil, repoID: nil, in: nil)
            return
        }
        branchVM.scheduleRefresh(
            directory: root.path,
            repoID: repoID,
            in: space.gitContext
        )
    }

    /// Installs the `onFilesRefreshed` hook on the active workspace's diff
    /// view-model (FR-T11). After every successful diff refresh, the closure
    /// prunes `inspectTabState.diffCollapse` to the new file set so collapse
    /// state for files that disappeared can't leak into a future diff.
    /// Idempotent — replaces any previously-installed closure.
    private func wireDiffCollapsePrune() {
        guard let workspace = activeWorkspace else { return }
        let tabState = workspace.inspectTabState
        let diffVM = tabState.diffViewModel
        diffVM.onFilesRefreshed = { [weak tabState] paths in
            guard let tabState else { return }
            tabState.diffCollapse = tabState.diffCollapse.filter { paths.contains($0.key) }
        }
    }

    // MARK: - Space Content

    @ViewBuilder
    private var spaceContentStack: some View {
        if let spaceCollection = displayedSpaceCollection {
            ZStack {
                ForEach(spaceCollection.spaces) { space in
                    let isActive = space.id == spaceCollection.activeSpaceID
                    SpaceContentView(
                        spaceModel: space,
                        resolveWorkingDirectory: { spaceCollection.resolveWorkingDirectory() },
                        isActive: isActive,
                        windowLeadingInset: sectionTabBarLeadingInset,
                        windowTrailingInset: sectionTabBarTrailingInset
                    )
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { handleContainerSizeChange(geo.size) }
                        .onChange(of: geo.size) { _, newSize in
                            lastContainerSize = newSize
                            if !sidebarState.isAnimating {
                                handleContainerSizeChange(newSize)
                            }
                        }
                }
            )
            .onChange(of: sidebarState.isAnimating) { wasAnimating, isAnimating in
                if wasAnimating && !isAnimating {
                    handleContainerSizeChange(lastContainerSize)
                }
            }
            .onChange(of: spaceCollection.activeSpace?.activeTabID) { _, _ in
                handleTabOrSpaceChanged()
            }
            .onChange(of: spaceCollection.activeSpaceID) { _, _ in
                handleTabOrSpaceChanged()
            }
        } else if workspaceCollection.workspaces.isEmpty {
            WorkspaceEmptyStateView(workspaceCollection: workspaceCollection)
        }
    }

    // MARK: - Focus

    private func handleTabOrSpaceChanged() {
        displayedSpaceCollection?.activeSpace?.activeTab?.paneViewModel.containerSize = lastContainerSize
        // TerminalContentView.updateNSView already claims first responder when
        // isTabVisible flips true, but that requires a SwiftUI rerender. Call
        // explicitly here to cover fast tab/space switches where the rerender
        // order isn't guaranteed.
        returnFocusToActivePane()
    }

    /// Make the active space's focused-section active pane the window's
    /// first responder. Falls back to Claude when Terminal is hidden or
    /// empty (see `SpaceModel.effectiveFocusedSection`).
    private func returnFocusToActivePane() {
        guard let space = displayedSpaceCollection?.activeSpace,
              let tab = space.effectiveFocusedSection.activeTab,
              let surfaceView = tab.paneViewModel.focusedSurfaceView else { return }
        // nsWindow (via WindowAccessor binding) can lag during the first
        // renders; fall back to the surface view's own window.
        guard let window = nsWindow ?? surfaceView.window else { return }
        if window.firstResponder !== surfaceView {
            window.makeFirstResponder(surfaceView)
        }
    }

    // MARK: - Container Size

    private func handleContainerSizeChange(_ size: CGSize) {
        lastContainerSize = size
        guard let spaceCollection = displayedSpaceCollection,
              let space = spaceCollection.activeSpace,
              let tab = space.activeTab else { return }
        tab.paneViewModel.containerSize = size
    }
}

// MARK: - Sidebar Notification Modifier

/// Breaks out the two `onReceive` Notification handlers from the main body so
/// Swift's type checker doesn't time out on the long modifier chain.
private struct SidebarNotificationModifier: ViewModifier {
    let workspaceCollection: WorkspaceCollection
    let sidebarState: SidebarState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { notification in
                guard let obj = notification.object as? WorkspaceCollection,
                      obj === workspaceCollection else { return }
                sidebarState.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusSidebar)) { notification in
                guard let obj = notification.object as? WorkspaceCollection,
                      obj === workspaceCollection else { return }
                if !sidebarState.isExpanded {
                    sidebarState.toggle()
                }
                sidebarState.focusTarget = .sidebar
            }
    }
}

// MARK: - Inspect Panel Wiring Modifier

/// Wires the inspect panel's root + status refresh triggers into a separate
/// ViewModifier so the main body stays within Swift's type-check budget.
///
/// Handles:
///   - `activeSpace?.defaultWorkingDirectory` changes
///   - `activeSpace?.worktreePath` changes
///   - `activeWorkspace?.defaultWorkingDirectory` changes
///   - `activeSpace?.gitContext.repoStatuses` changes (FR-27 badge refresh)
private struct InspectPanelWiringModifier: ViewModifier {
    let activeSpace: SpaceModel?
    let activeWorkspace: Workspace?
    let updateRoot: () -> Void
    let refreshStatus: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: activeSpace?.defaultWorkingDirectory) { _, _ in
                updateRoot()
                refreshStatus()
            }
            .onChange(of: activeSpace?.worktreePath) { _, _ in
                updateRoot()
                refreshStatus()
            }
            .onChange(of: activeWorkspace?.defaultWorkingDirectory) { _, _ in
                updateRoot()
                refreshStatus()
            }
            // FR-27: badges refresh within 1 s of git status changes. `repoStatuses`
            // is the @Observable property on SpaceGitContext that the FSEvents watcher
            // + RefreshScheduler update after every debounced git-status run. When it
            // changes for the active space we fetch the full (uncapped) diff and push
            // it into the view model so every changed file in the tree gets a badge.
            .onChange(of: activeSpace?.gitContext.repoStatuses) { _, _ in
                refreshStatus()
            }
    }
}

// MARK: - Inspect Panel Tabs Wiring Modifier

/// Wires the Diff and Branch tab view-models to the active space's
/// `SpaceGitContext` signals. Lifted out of the main body to keep Swift's
/// type-checker within budget and isolate the per-tab refresh triggers from
/// the v1 file-tree refresh wiring above.
///
/// Handles:
///   - Active workspace / space changes → re-arm collapse-prune hook +
///     fire one diff and one branch refresh against the new directory.
///   - `activeSpace?.gitContext.repoStatuses` (FR-T18) → diff refresh. The
///     view-model debounces and cancels in-flight diffs internally.
///   - `activeSpace?.gitContext.branchGraphDirty` (FR-T28) → branch refresh
///     when the active repo's dirty flag flips on. The view-model clears
///     the flag on successful completion.
///   - `activeSpace?.worktreePath` and `activeWorkspace?.defaultWorkingDirectory`
///     → diff + branch refresh (the resolved root may have changed).
private struct InspectPanelTabsWiringModifier: ViewModifier {
    let activeSpace: SpaceModel?
    let activeWorkspace: Workspace?
    let refreshDiff: () -> Void
    let refreshBranch: () -> Void
    let wireDiffCollapsePrune: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: activeWorkspace?.id) { _, _ in
                wireDiffCollapsePrune()
                refreshDiff()
                refreshBranch()
            }
            .onChange(of: activeSpace?.id) { _, _ in
                refreshDiff()
                refreshBranch()
            }
            .onChange(of: activeSpace?.defaultWorkingDirectory) { _, _ in
                refreshDiff()
                refreshBranch()
            }
            .onChange(of: activeSpace?.worktreePath) { _, _ in
                refreshDiff()
                refreshBranch()
            }
            .onChange(of: activeWorkspace?.defaultWorkingDirectory) { _, _ in
                refreshDiff()
                refreshBranch()
            }
            // FR-T18: every git-status change → diff refresh.
            .onChange(of: activeSpace?.gitContext.repoStatuses) { _, _ in
                refreshDiff()
            }
            // FR-T28: HEAD / local-ref change → branch refresh.
            .onChange(of: activeSpace?.gitContext.branchGraphDirty) { _, newValue in
                guard let newValue,
                      let space = activeSpace,
                      let repoID = space.gitContext.pinnedRepoOrder.first,
                      newValue.contains(repoID)
                else { return }
                refreshBranch()
            }
            // Tab activation kicker: when the user switches to Branch and we
            // don't yet have a graph, fire a one-shot fetch. (Diff handles
            // its own initial load via `refreshDiff` on space switch.)
            .onChange(of: activeWorkspace?.inspectTabState.activeTab) { _, newTab in
                guard newTab == .branch,
                      activeWorkspace?.inspectTabState.branchViewModel.graph == nil
                else { return }
                refreshBranch()
            }
    }
}

// MARK: - Terminal Toggle (status-bar inline)

/// Inline show/hide-terminal toggle that lives in the status-bar strip,
/// to the right of the workspace sidebar. Replaces the floating
/// liquid-glass disc that used to sit in the Claude section's tab bar.
private struct TerminalToggleStatusBarButton: View {
    @Bindable var space: SpaceModel

    @State private var isHovering = false

    private static let buttonWidth: CGFloat = 24
    private static let buttonHeight: CGFloat = 18

    var body: some View {
        Button {
            space.toggleTerminal()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(iconForeground)
                .frame(width: Self.buttonWidth, height: Self.buttonHeight)
                .background {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isHovering ? Color.white.opacity(0.07) : Color.clear)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(space.terminalVisible ? "Hide Terminal" : "Show Terminal")
        .accessibilityLabel(space.terminalVisible ? "Hide Terminal" : "Show Terminal")
        .accessibilityIdentifier("status-bar-terminal-toggle")
    }

    private var iconName: String {
        space.dockPosition == .bottom
            ? "rectangle.bottomhalf.inset.filled"
            : "rectangle.righthalf.inset.filled"
    }

    private var iconForeground: Color {
        space.terminalVisible
            ? Color.primary.opacity(0.85)
            : Color.secondary.opacity(0.55)
    }
}

// MARK: - Window Accessor

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        window = nsView.window
    }
}
