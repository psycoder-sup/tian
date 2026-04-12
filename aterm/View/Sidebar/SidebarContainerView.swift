import Accessibility
import AppKit
import SwiftUI

extension Notification.Name {
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let focusSidebar = Notification.Name("focusSidebar")
    static let toggleDebugOverlay = Notification.Name("toggleDebugOverlay")
    static let showWorktreeBranchInput = Notification.Name("showWorktreeBranchInput")
}

extension Notification {
    static let worktreeWorkingDirectoryKey = "workingDirectory"
    static let worktreeWorkspaceIDKey = "worktreeWorkspaceID"
}

struct SidebarContainerView: View {
    let workspaceCollection: WorkspaceCollection
    let worktreeOrchestrator: WorktreeOrchestrator

    @State private var sidebarState = SidebarState()
    @State private var lastContainerSize: CGSize = .zero
    @State private var nsWindow: NSWindow?
    @State private var announcementsEnabled = false

    private var displayedSpaceCollection: SpaceCollection? {
        workspaceCollection.activeSpaceCollection
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if sidebarState.isExpanded {
                SidebarPanelView(
                    workspaceCollection: workspaceCollection,
                    worktreeOrchestrator: worktreeOrchestrator,
                    sidebarState: sidebarState
                )
                .frame(width: sidebarState.mode.width)
            }

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Color.clear.frame(width: 80)
                        SidebarToggleButton(workspaceCollection: workspaceCollection)
                    }
                    .frame(width: max(sidebarState.mode.width, 104), alignment: .leading)

                    tabBar
                }
                .frame(height: 44)

                terminalZStack
                    .padding(.leading, sidebarState.mode.width)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowAccessor(window: $nsWindow))
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
        }
        .onChange(of: displayedSpaceCollection?.activeSpaceID) { _, _ in
            if announcementsEnabled, let name = displayedSpaceCollection?.activeSpace?.name {
                AccessibilityNotification.Announcement("Space: \(name)").post()
            }
        }
        .onChange(of: displayedSpaceCollection?.activeSpace?.activeTabID) { _, _ in
            if announcementsEnabled, let name = displayedSpaceCollection?.activeSpace?.activeTab?.displayName {
                AccessibilityNotification.Announcement("Tab: \(name)").post()
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            announcementsEnabled = true
        }
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        if let spaceCollection = displayedSpaceCollection,
           let space = spaceCollection.activeSpace {
            TabBarView(space: space) {
                let wd = spaceCollection.resolveWorkingDirectory()
                space.createTab(workingDirectory: wd)
            }
        } else {
            Color.clear.frame(height: 44)
        }
    }

    // MARK: - Terminal Panes

    @ViewBuilder
    private var terminalZStack: some View {
        if let spaceCollection = displayedSpaceCollection {
            ZStack {
                ForEach(spaceCollection.spaces) { space in
                    ForEach(space.tabs) { tab in
                        let isVisible = space.id == spaceCollection.activeSpaceID
                            && tab.id == space.activeTabID
                        SplitTreeView(
                            node: tab.paneViewModel.splitTree.root,
                            viewModel: tab.paneViewModel
                        )
                        .opacity(isVisible ? 1 : 0)
                        .allowsHitTesting(isVisible)
                    }
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
                spaceCollection.activeSpace?.activeTab?.paneViewModel.containerSize = lastContainerSize
            }
            .onChange(of: spaceCollection.activeSpaceID) { _, _ in
                spaceCollection.activeSpace?.activeTab?.paneViewModel.containerSize = lastContainerSize
            }
        } else if workspaceCollection.workspaces.isEmpty {
            WorkspaceEmptyStateView(workspaceCollection: workspaceCollection)
        }
    }

    // MARK: - Focus

    private func returnFocusToTerminal() {
        guard let window = nsWindow,
              let spaceCollection = displayedSpaceCollection,
              let space = spaceCollection.activeSpace,
              let tab = space.activeTab else { return }
        let focusedPaneID = tab.paneViewModel.splitTree.focusedPaneID
        if let surfaceView = tab.paneViewModel.surfaceView(for: focusedPaneID) {
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

// MARK: - Window Accessor

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        window = nsView.window
    }
}
