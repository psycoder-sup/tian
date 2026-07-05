import SwiftUI

/// A single Claude-session status dot. Drives the session row's leading
/// indicator in the sidebar.
struct SessionDotView: View {
    let state: ClaudeSessionState

    var body: some View {
        switch state {
        case .busy:
            BusyDotView()
        case .needsAttention, .failed, .active, .idle:
            Circle()
                .fill(state.solidStatusColor ?? .clear)
                .frame(width: 8, height: 8)
        case .inactive:
            EmptyView()
        }
    }
}
