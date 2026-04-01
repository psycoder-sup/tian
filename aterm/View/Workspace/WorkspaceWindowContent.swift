import SwiftUI

struct WorkspaceWindowContent: View {
    let workspaceCollection: WorkspaceCollection

    var body: some View {
        SidebarContainerView(workspaceCollection: workspaceCollection)
    }
}
