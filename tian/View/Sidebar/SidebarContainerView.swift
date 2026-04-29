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

    private var displayedSpaceCollection: SpaceCollection? {
        workspaceCollection.activeSpaceCollection
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

// MARK: - Window Accessor

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        window = nsView.window
    }
}
