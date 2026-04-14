import SwiftUI

/// Row of colored dots representing Claude session states, sorted by priority (highest first).
struct ClaudeSessionDotsView: View {
    let sessions: [(id: UUID, state: ClaudeSessionState)]

    /// Convenience: render dots from a pre-sorted state array (no pane IDs needed).
    init(states: [ClaudeSessionState]) {
        self.sessions = states.enumerated().map { index, state in
            (id: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index))")!, state: state)
        }
    }

    init(sessions: [(id: UUID, state: ClaudeSessionState)]) {
        self.sessions = sessions
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(sessions, id: \.id) { session in
                dotView(for: session.state)
            }
        }
    }

    @ViewBuilder
    private func dotView(for state: ClaudeSessionState) -> some View {
        switch state {
        case .busy:
            BusyDotView()
        case .needsAttention:
            Circle()
                .fill(Color(red: 1.0, green: 0.624, blue: 0.039))
                .frame(width: 8, height: 8)
        case .active:
            Circle()
                .fill(Color(red: 0.204, green: 0.78, blue: 0.349))
                .frame(width: 8, height: 8)
        case .idle:
            Circle()
                .fill(Color(red: 0.557, green: 0.557, blue: 0.576))
                .frame(width: 8, height: 8)
        case .inactive:
            EmptyView()
        }
    }
}
