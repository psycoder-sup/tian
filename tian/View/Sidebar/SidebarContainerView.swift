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
    /// + ~18pt toggle button. Shared by both the toggle overlay and the
    /// content's leading padding so the overlay never covers content.
    private var toggleGutterWidth: CGFloat {
        max(sidebarState.mode.width, 104)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebarAndContent
                .overlay(alignment: .topTrailing) { inspectToggleOverlay }
            inspectColumn
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowAccessor(window: $nsWindow))
        .modifier(SidebarNotificationModifier(
            workspaceCollection: workspaceCollection,
            sidebarState: sidebarState
        ))
        .onChange(of: sidebarState.focusTarget) { _, newTarget in
            if newTarget == .terminal {
                returnFocusToTerminal()
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
        .onChange(of: displayedSpaceCollection?.activeSpace?.activeTabID) { _, _ in
            if announcementsEnabled, let name = displayedSpaceCollection?.activeSpace?.activeTab?.displayName {
                AccessibilityNotification.Announcement("Tab: \(name)").post()
            }
        }
        .task {
            updateInspectPanelRoot()
            refreshInspectPanelStatus()
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
                .padding(.leading, toggleGutterWidth)
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
        if let workspace = activeWorkspace, workspace.inspectPanelState.isVisible {
            InspectPanelView(
                panelState: workspace.inspectPanelState,
                viewModel: workspace.inspectFileTreeViewModel,
                spaceName: activeSpace?.name ?? workspace.name
            )
            .padding(.bottom, bottomContentInset)
        }
    }

    /// Floating toggle button shown at top-trailing of the content area when
    /// the inspect panel is collapsed.
    @ViewBuilder
    private var inspectToggleOverlay: some View {
        if let workspace = activeWorkspace, !workspace.inspectPanelState.isVisible {
            InspectPanelRail {
                workspace.inspectPanelState.isVisible = true
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
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

    // MARK: - Space Content

    @ViewBuilder
    private var spaceContentStack: some View {
        if let spaceCollection = displayedSpaceCollection {
            ZStack {
                ForEach(spaceCollection.spaces) { space in
                    let isActive = space.id == spaceCollection.activeSpaceID
                    SpaceContentView(
                        spaceModel: space,
                        resolveWorkingDirectory: { spaceCollection.resolveWorkingDirectory() }
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
        returnFocusToTerminal()
    }

    private func returnFocusToTerminal() {
        guard let space = displayedSpaceCollection?.activeSpace,
              let tab = space.activeTab else { return }
        let paneID = tab.paneViewModel.splitTree.focusedPaneID
        guard let surfaceView = tab.paneViewModel.surfaceView(for: paneID) else { return }
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

// MARK: - Window Accessor

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        window = nsView.window
    }
}
