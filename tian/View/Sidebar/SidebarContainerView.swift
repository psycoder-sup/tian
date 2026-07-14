import Accessibility
import AppKit
import SwiftUI

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let focusSidebar = Notification.Name("focusSidebar")
    static let toggleDebugOverlay = Notification.Name("toggleDebugOverlay")
    static let showCreateSessionInput = Notification.Name("showCreateSessionInput")
    static let showCreateSSHWorkspaceInput = Notification.Name("showCreateSSHWorkspaceInput")
    static let toggleSessionOverview = Notification.Name("toggleSessionOverview")
    static let renameSession = Notification.Name("renameSession")
}

extension Notification {
    static let createSessionWorkspaceIDKey = "createSessionWorkspaceID"
    static let renameSessionIDKey = "renameSessionID"
}

struct SidebarContainerView: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator
    /// Bottom padding applied only to the session-content area so it leaves
    /// room for an overlapping status bar. The sidebar panel keeps its full
    /// height and visually extends over the status bar on the left.
    var bottomContentInset: CGFloat = 0

    @State private var sidebarState = SidebarState()
    /// Whether the Mission-Control-style session overview grid is overlaid on
    /// the session content. Toggled by `.toggleSessionOverview` (Cmd+Shift+O /
    /// sidebar button); cleared when a card is selected or the overlay dismissed.
    @State private var isOverviewVisible = false
    @State private var lastContainerSize: CGSize = .zero
    @State private var nsWindow: NSWindow?
    @State private var announcementsEnabled = false
    /// In-flight git-status fetch for the inspect panel. Cancelled on session
    /// switch or when a newer repoStatuses change fires — ensures stale results
    /// from a previous session never land in the current tree (FR-28a).
    @State private var inspectGitStatusTask: Task<Void, Never>?

    private var displayedSessionCollection: SessionCollection? {
        workspaceCollection.activeSessionCollection
    }

    private var activeWorkspace: Workspace? {
        workspaceCollection.activeWorkspace
    }

    private var activeSession: Session? {
        displayedSessionCollection?.activeSession
    }

    /// `true` when at least one session exists in ANY workspace of this window's
    /// collection. Drives the overview overlay's global (not per-workspace)
    /// auto-dismiss so deleting the active workspace's last card doesn't close the
    /// overview while other workspaces still have cards.
    private var hasAnySession: Bool {
        workspaceCollection.workspaces.contains { !$0.sessionCollection.sessions.isEmpty }
    }

    /// Top-gutter floor when the sidebar is collapsed: 80pt traffic-lights + 6pt
    /// spacing + ~18pt sidebar toggle + 6pt + ~18pt overview toggle.
    private let topGutterFloor: CGFloat = 130
    /// The single-button floor the bottom terminal-toggle aligns to (it has no
    /// second button): 80pt traffic-lights + 6pt + ~18pt toggle.
    private let bottomStripFloor: CGFloat = 104

    /// Leading inset that reserves room for the traffic lights + sidebar
    /// toggle + overview button when the sidebar is collapsed, and matches the
    /// sidebar width when expanded. Used to size the toggle button overlay frame.
    private var toggleGutterWidth: CGFloat {
        max(sidebarState.mode.width, topGutterFloor)
    }

    /// Inset applied to the leading edge of the session content so its header
    /// chrome doesn't slide under the sidebar toggle / overview button /
    /// traffic lights. Drops to zero when the sidebar is wide enough to swallow
    /// the buttons.
    private var windowLeadingInset: CGFloat {
        max(topGutterFloor - sidebarState.mode.width, 0)
    }

    /// Inset applied to the trailing edge of the session content so its header
    /// chrome doesn't slide under the inspect-panel rail. Zero when the panel is
    /// open (rail moves with the panel column).
    private var windowTrailingInset: CGFloat {
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
            sidebarState: sidebarState,
            isOverviewVisible: $isOverviewVisible
        ))
        .onChange(of: sidebarState.focusTarget) { _, newTarget in
            if newTarget == .terminal {
                returnFocusToActivePane()
            }
        }
        .onChange(of: isOverviewVisible) { _, isVisible in
            if !isVisible && sidebarState.focusTarget == .terminal {
                returnFocusToActivePane()
            }
        }
        .onChange(of: workspaceCollection.activeWorkspaceID) { _, _ in
            if announcementsEnabled, let name = workspaceCollection.activeWorkspace?.name {
                AccessibilityNotification.Announcement("Workspace: \(name)").post()
            }
            updateInspectPanelRoot()
            refreshInspectPanelStatus()
        }
        .onChange(of: displayedSessionCollection?.activeSessionID) { _, _ in
            if announcementsEnabled, let name = displayedSessionCollection?.activeSession?.displayName {
                AccessibilityNotification.Announcement("Session: \(name)").post()
            }
            updateInspectPanelRoot()
            refreshInspectPanelStatus()
        }
        .onChange(of: hasAnySession) { _, hasAny in
            // The overview overlay now sits above every branch of sessionContentStack,
            // so an active-workspace drain no longer unmounts it. Only auto-close when
            // NO workspace has any session (zero cards to show).
            if !hasAny { isOverviewVisible = false }
        }
        .modifier(InspectPanelWiringModifier(
            activeSession: activeSession,
            activeWorkspace: activeWorkspace,
            updateRoot: updateInspectPanelRoot,
            refreshStatus: refreshInspectPanelStatus
        ))
        .modifier(InspectPanelTabsWiringModifier(
            activeSession: activeSession,
            activeWorkspace: activeWorkspace,
            refreshDiff: refreshInspectPanelDiff,
            refreshBranch: refreshInspectPanelBranch,
            wireDiffCollapsePrune: wireDiffCollapsePrune
        ))
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

            sessionContentStack
                .padding(.leading, sidebarState.mode.width)
                .padding(.bottom, bottomContentInset)

            HStack(spacing: 6) {
                Color.clear.frame(width: 80)
                SidebarToggleButton(workspaceCollection: workspaceCollection)
                SidebarOverviewButton(workspaceCollection: workspaceCollection)
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
                spaceName: activeSession?.displayName ?? workspace.name,
                onOpenFile: { path in
                    if HtmlFileType.isHtml(path: path) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        return
                    }
                    guard let session = activeSession else { return }
                    if MarkdownFileType.isMarkdown(path: path) {
                        session.readerState.openMarkdown(filePath: path)
                    } else if ImageFileType.isImage(path: path) {
                        session.readerState.openImage(filePath: path)
                    }
                }
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
    /// collapsed.
    @ViewBuilder
    private var inspectToggleOverlay: some View {
        // Single, always-visible toggle anchored at the window's top-trailing
        // corner. When the panel is open it sits visually over the empty
        // right side of the header row; when collapsed it floats alone in the
        // same spot — so the toggle never moves.
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
    /// the sidebar's visual edge. Hidden when no session is active.
    @ViewBuilder
    private var terminalToggleStatusBarOverlay: some View {
        if let session = activeSession, bottomContentInset > 0 {
            TerminalToggleStatusBarButton(session: session)
                .padding(.leading, max(sidebarState.mode.width, bottomStripFloor) + 4)
                .frame(height: bottomContentInset)
        }
    }

    /// Re-roots the workspace's inspect file tree to the active session's
    /// resolved working directory (FR-10). Called whenever the active
    /// workspace, active session, or either's working directory changes.
    private func updateInspectPanelRoot() {
        guard let workspace = activeWorkspace else { return }
        let newRoot = workspace.inspectPanelRoot(for: activeSession)
        if workspace.inspectFileTreeViewModel.rootDirectory != newRoot {
            workspace.inspectFileTreeViewModel.setRoot(newRoot)
        }
    }

    /// Fetches the full (uncapped) git diff for the active session's root and
    /// pushes the result into the inspect panel view model so file badges
    /// reflect the current git status (FR-19, FR-27).
    ///
    /// FR-22: Directories with no git repo skip the fetch; `updateStatus([])` is
    /// called to ensure stale badges from a previous session are cleared.
    ///
    /// Cancels any in-flight fetch before launching a new one so stale results
    /// from a slow git invocation never overwrite fresher data (FR-28a).
    private func refreshInspectPanelStatus() {
        guard let workspace = activeWorkspace else { return }
        let viewModel = workspace.inspectFileTreeViewModel

        // Resolved root for the current session — must match what the file tree shows.
        guard let root = workspace.inspectPanelRoot(for: activeSession) else {
            // No root at all: clear any lingering badges and bail.
            viewModel.updateStatus([])
            return
        }

        // FR-22: if the active session has no pinned git repos, the root is not
        // inside a git repo. Skip the fetch and clear any stale badges so the
        // tree renders without badges, matching the "local" context-suffix state.
        let hasRepo = !(activeSession?.gitContext.repoStatuses.isEmpty ?? true)
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
    /// session's working directory. Called on session switch, workspace switch,
    /// and on every `repoStatuses` change (FR-T18 — the view-model handles
    /// debounce + cancel-on-new). Clears state when the directory has no
    /// resolvable git repo so stale diffs don't survive a session switch.
    private func refreshInspectPanelDiff() {
        guard let workspace = activeWorkspace else { return }
        let diffVM = workspace.inspectTabState.diffViewModel

        guard let root = workspace.inspectPanelRoot(for: activeSession) else {
            diffVM.scheduleRefresh(directory: nil)
            return
        }
        // FR-T19: outside a git repo, the Diff body shows the no-repo
        // placeholder. Clear the view-model so we don't show stale data
        // when the user moves between repo and non-repo sessions.
        let hasRepo = !(activeSession?.gitContext.repoStatuses.isEmpty ?? true)
        guard hasRepo else {
            diffVM.scheduleRefresh(directory: nil)
            return
        }
        diffVM.scheduleRefresh(directory: root.path)
    }

    /// Schedules a refresh of `InspectBranchViewModel` against the active
    /// session's working directory + first pinned repo (FR-T28). Called on
    /// session/workspace switches and whenever `branchGraphDirty` changes for
    /// the active session. The Branch view-model clears the dirty flag on
    /// successful completion.
    private func refreshInspectPanelBranch() {
        guard let workspace = activeWorkspace else { return }
        let branchVM = workspace.inspectTabState.branchViewModel

        guard let root = workspace.inspectPanelRoot(for: activeSession) else {
            branchVM.scheduleRefresh(directory: nil, repoID: nil, in: nil)
            return
        }
        // FR-T19: outside a git repo, render no-repo placeholder.
        guard let session = activeSession,
              let repoID = session.gitContext.pinnedRepoOrder.first else {
            branchVM.scheduleRefresh(directory: nil, repoID: nil, in: nil)
            return
        }
        branchVM.scheduleRefresh(
            directory: root.path,
            repoID: repoID,
            in: session.gitContext
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

    // MARK: - Session Content

    @ViewBuilder
    private var sessionContentStack: some View {
        // The overview grid is applied as a single `.overlay` on the whole
        // branch `Group` (not an if/else swap) so it can sit above EVERY branch —
        // the empty-state, the populated ZStack, and the workspace-empty state.
        // The populated ZStack (and every session's live Metal terminal surface)
        // stays mounted beneath the overlay, keeping live state while it's open;
        // lifting the overlay here also lets Cmd+Shift+O open it from the empty
        // create-session page.
        Group {
            if let sessionCollection = displayedSessionCollection {
                if sessionCollection.sessions.isEmpty, let workspace = activeWorkspace {
                    // The workspace outlived its last session (closing the last
                    // session no longer closes the workspace). Offer a create-session
                    // action where the Claude pane would normally render.
                    SessionEmptyStateView(
                        workspaceCollection: workspaceCollection,
                        workspace: workspace
                    )
                } else {
                    ZStack {
                        ForEach(sessionCollection.sessions) { session in
                            let isActive = session.id == sessionCollection.activeSessionID
                            SessionContentView(
                                session: session,
                                isActive: isActive,
                                windowLeadingInset: windowLeadingInset,
                                windowTrailingInset: windowTrailingInset
                            )
                            .opacity(isActive ? 1 : 0)
                            .allowsHitTesting(isActive)
                            .environment(\.sessionIsVisible, isActive)
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
                    .onChange(of: sessionCollection.activeSessionID) { _, _ in
                        handleSessionChanged()
                    }
                }
            } else if workspaceCollection.workspaces.isEmpty {
                WorkspaceEmptyStateView(workspaceCollection: workspaceCollection)
            }
        }
        .modifier(SessionOverviewOverlayModifier(
            workspaceCollection: workspaceCollection,
            worktreeOrchestrator: worktreeOrchestrator,
            sidebarState: sidebarState,
            isOverviewVisible: $isOverviewVisible
        ))
    }

    // MARK: - Focus

    private func handleSessionChanged() {
        // TerminalContentView.updateNSView already claims first responder when
        // the region becomes visible, but that requires a SwiftUI rerender. Call
        // explicitly here to cover fast session switches where the rerender
        // order isn't guaranteed.
        returnFocusToActivePane()
    }

    /// Make the active session's focused-area active pane the window's first
    /// responder. Falls back to Claude when Terminal is hidden or empty (see
    /// `Session.effectiveFocusedPane`). Silently no-ops when the effective pane
    /// is the empty-Claude placeholder.
    private func returnFocusToActivePane() {
        guard let session = displayedSessionCollection?.activeSession else { return }
        // Reader overlay open → don't hand focus to the hidden live Claude
        // surface behind it; keystrokes must not misroute to the terminal.
        guard session.readerState.current == nil else { return }
        guard let pvm = session.effectiveFocusedPane,
              let surfaceView = pvm.focusedSurfaceView else { return }
        // nsWindow (via WindowAccessor binding) can lag during the first
        // renders; fall back to the surface view's own window.
        guard let window = nsWindow ?? surfaceView.window else { return }
        if window.firstResponder !== surfaceView {
            window.makeFirstResponder(surfaceView)
        }
    }

    // MARK: - Container Size

    /// Records the latest content size for the sidebar-animation settle. The
    /// per-region pane `containerSize` writes now happen inside
    /// `SessionContentView`, which measures its own regions.
    private func handleContainerSizeChange(_ size: CGSize) {
        lastContainerSize = size
    }
}

// MARK: - Sidebar Notification Modifier

/// Breaks out the two `onReceive` Notification handlers from the main body so
/// Swift's type checker doesn't time out on the long modifier chain.
private struct SidebarNotificationModifier: ViewModifier {
    let workspaceCollection: WorkspaceCollection
    let sidebarState: SidebarState
    @Binding var isOverviewVisible: Bool

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
            .onReceive(NotificationCenter.default.publisher(for: .toggleSessionOverview)) { notification in
                guard let obj = notification.object as? WorkspaceCollection,
                      obj === workspaceCollection else { return }
                // Don't turn the overview on in a window with nothing to show —
                // otherwise the flag desyncs and the grid pops up the instant a
                // session is later created. Still allow turning it back off.
                let hasSessions = workspaceCollection.workspaces
                    .contains { !$0.sessionCollection.sessions.isEmpty }
                guard hasSessions || isOverviewVisible else { return }
                isOverviewVisible.toggle()
            }
    }
}

// MARK: - Session Overview Overlay Modifier

/// Overlays the Mission-Control-style session overview grid on the always-mounted
/// session `ZStack`. Broken out into its own `ViewModifier` so the overlay closure
/// doesn't push `sessionContentStack` past Swift's type-check budget, mirroring the
/// other modifiers in this file. The `.overlay` keeps the underlying ZStack — and
/// every session's live terminal surface — mounted while the overview is visible.
private struct SessionOverviewOverlayModifier: ViewModifier {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator
    let sidebarState: SidebarState
    @Binding var isOverviewVisible: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isOverviewVisible {
                SessionOverviewGridView(
                    workspaceCollection: workspaceCollection,
                    worktreeOrchestrator: worktreeOrchestrator,
                    onSelect: { workspaceID, sessionID in
                        workspaceCollection.activateWorkspace(id: workspaceID)
                        workspaceCollection.workspaces
                            .first(where: { $0.id == workspaceID })?
                            .sessionCollection.activateSession(id: sessionID)
                        sidebarState.focusTarget = .terminal
                        isOverviewVisible = false
                    },
                    onDismiss: { isOverviewVisible = false }
                )
            }
        }
    }
}

// MARK: - Inspect Panel Wiring Modifier

/// Wires the inspect panel's root + status refresh triggers into a separate
/// ViewModifier so the main body stays within Swift's type-check budget.
///
/// Handles:
///   - `activeSession?.defaultWorkingDirectory` changes
///   - `activeSession?.worktreePath` changes
///   - `activeWorkspace?.defaultWorkingDirectory` changes
///   - `activeSession?.gitContext.repoStatuses` changes (FR-27 badge refresh)
private struct InspectPanelWiringModifier: ViewModifier {
    let activeSession: Session?
    let activeWorkspace: Workspace?
    let updateRoot: () -> Void
    let refreshStatus: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: activeSession?.defaultWorkingDirectory) { _, _ in
                updateRoot()
                refreshStatus()
            }
            .onChange(of: activeSession?.worktreePath) { _, _ in
                updateRoot()
                refreshStatus()
            }
            // Follow Claude's builtin EnterWorktree/ExitWorktree: when the
            // Claude pane moves into (or out of) its own worktree, `inspectPanelRoot`
            // now prefers `claudeWorktreeRoot`, so re-root + refresh badges.
            .onChange(of: activeSession?.claudeWorktreeRoot) { _, _ in
                updateRoot()
                refreshStatus()
            }
            .onChange(of: activeWorkspace?.defaultWorkingDirectory) { _, _ in
                updateRoot()
                refreshStatus()
            }
            // FR-27: badges refresh within 1 s of git status changes. `repoStatuses`
            // is the @Observable property on SessionGitContext that the FSEvents watcher
            // + RefreshScheduler update after every debounced git-status run. When it
            // changes for the active session we fetch the full (uncapped) diff and push
            // it into the view model so every changed file in the tree gets a badge.
            .onChange(of: activeSession?.gitContext.repoStatuses) { _, _ in
                refreshStatus()
            }
    }
}

// MARK: - Inspect Panel Tabs Wiring Modifier

/// Wires the Diff and Branch tab view-models to the active session's
/// `SessionGitContext` signals. Lifted out of the main body to keep Swift's
/// type-checker within budget and isolate the per-tab refresh triggers from
/// the v1 file-tree refresh wiring above.
///
/// Handles:
///   - Active workspace / session changes → re-arm collapse-prune hook +
///     fire one diff and one branch refresh against the new directory.
///   - `activeSession?.gitContext.repoStatuses` (FR-T18) → diff refresh. The
///     view-model debounces and cancels in-flight diffs internally.
///   - `activeSession?.gitContext.branchGraphDirty` (FR-T28) → branch refresh
///     when the active repo's dirty flag flips on. The view-model clears
///     the flag on successful completion.
///   - `activeSession?.worktreePath` and `activeWorkspace?.defaultWorkingDirectory`
///     → diff + branch refresh (the resolved root may have changed).
private struct InspectPanelTabsWiringModifier: ViewModifier {
    let activeSession: Session?
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
            .onChange(of: activeSession?.id) { _, _ in
                refreshDiff()
                refreshBranch()
            }
            .onChange(of: activeSession?.defaultWorkingDirectory) { _, _ in
                refreshDiff()
                refreshBranch()
            }
            .onChange(of: activeSession?.worktreePath) { _, _ in
                refreshDiff()
                refreshBranch()
            }
            // Follow Claude's builtin EnterWorktree/ExitWorktree — the resolved
            // root prefers `claudeWorktreeRoot`, so the Diff/Branch tabs must
            // re-fetch against the new worktree when it changes.
            .onChange(of: activeSession?.claudeWorktreeRoot) { _, _ in
                refreshDiff()
                refreshBranch()
            }
            .onChange(of: activeWorkspace?.defaultWorkingDirectory) { _, _ in
                refreshDiff()
                refreshBranch()
            }
            // FR-T18: every git-status change → diff refresh.
            .onChange(of: activeSession?.gitContext.repoStatuses) { _, _ in
                refreshDiff()
            }
            // FR-T28: HEAD / local-ref change → branch refresh.
            .onChange(of: activeSession?.gitContext.branchGraphDirty) { _, newValue in
                guard let newValue,
                      let session = activeSession,
                      let repoID = session.gitContext.pinnedRepoOrder.first,
                      newValue.contains(repoID)
                else { return }
                refreshBranch()
            }
            // Tab activation kicker: when the user switches to Branch and we
            // don't yet have a graph, fire a one-shot fetch. (Diff handles
            // its own initial load via `refreshDiff` on session switch.)
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
/// to the right of the workspace sidebar. Its context menu carries the
/// dock-position + reset actions that previously lived in the section toolbar.
private struct TerminalToggleStatusBarButton: View {
    @Bindable var session: Session

    @State private var isHovering = false

    private static let buttonWidth: CGFloat = 24
    private static let buttonHeight: CGFloat = 18

    var body: some View {
        Button {
            session.toggleTerminal()
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
        .help(session.terminalVisible ? "Hide Terminal" : "Show Terminal")
        .accessibilityLabel(session.terminalVisible ? "Hide Terminal" : "Show Terminal")
        .accessibilityIdentifier("status-bar-terminal-toggle")
        .contextMenu {
            // Dock / reset actions are disabled mid divider-drag (FR-15).
            Button("Move to Bottom") { session.setDockPosition(.bottom) }
                .disabled(session.dockPosition == .bottom || session.dividerDragController.isDragging)
            Button("Move to Right") { session.setDockPosition(.right) }
                .disabled(session.dockPosition == .right || session.dividerDragController.isDragging)
            Divider()
            Button("Reset Terminal Panel", role: .destructive) {
                session.resetTerminalPanel()
            }
            .disabled(session.dividerDragController.isDragging)
        }
    }

    private var iconName: String {
        session.dockPosition == .bottom
            ? "rectangle.bottomhalf.inset.filled"
            : "rectangle.righthalf.inset.filled"
    }

    private var iconForeground: Color {
        session.terminalVisible
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
