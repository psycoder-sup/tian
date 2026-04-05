import SwiftUI

struct WorkspaceWindowContent: View {
    let workspaceCollection: WorkspaceCollection
    @State private var showDebugOverlay = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            SidebarContainerView(workspaceCollection: workspaceCollection)

            if showDebugOverlay {
                DebugOverlayView()
                    .padding(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showDebugOverlay)
        .onReceive(NotificationCenter.default.publisher(for: .toggleDebugOverlay)) { notification in
            guard let obj = notification.object as? WorkspaceCollection,
                  obj === workspaceCollection else { return }
            showDebugOverlay.toggle()
        }
    }
}
