import SwiftUI

/// Status area below the space name in the sidebar.
/// Phase 2: Shows Claude session dots and free-form status label.
/// Git repo lines will be added in Phase 3.
struct SpaceStatusAreaView: View {
    let sessions: [(paneID: UUID, state: ClaudeSessionState)]
    let space: SpaceModel
    let isActive: Bool

    private var statusColor: Color {
        if isActive {
            Color(red: 0.35, green: 0.6, blue: 1.0).opacity(0.7)
        } else {
            Color(red: 0.45, green: 0.55, blue: 0.7).opacity(0.7)
        }
    }

    var body: some View {
        let latestStatus = PaneStatusManager.shared.latestStatus(in: space)

        VStack(alignment: .leading, spacing: 2) {
            if !sessions.isEmpty {
                ClaudeSessionDotsView(sessions: sessions.map { (id: $0.paneID, state: $0.state) })
            }

            if let status = latestStatus {
                Text(String(status.label.prefix(50)))
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
