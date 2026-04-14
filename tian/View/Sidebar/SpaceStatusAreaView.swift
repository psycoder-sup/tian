import SwiftUI

/// Status area below the space name in the sidebar.
/// Renders one line per pinned repo plus optional non-repo dot line.
struct SpaceStatusAreaView: View {
    let sessions: [(paneID: UUID, state: ClaudeSessionState)]
    let space: SpaceModel
    let isActive: Bool

    private let maxVisibleLines = 3

    private var subtitleColor: Color {
        if isActive {
            Color(red: 0.35, green: 0.6, blue: 1.0).opacity(0.7)
        } else {
            Color(red: 0.45, green: 0.55, blue: 0.7).opacity(0.7)
        }
    }

    private func groupSessionsByRepo() -> [GitRepoID?: [ClaudeSessionState]] {
        var grouped: [GitRepoID?: [ClaudeSessionState]] = [:]
        for session in sessions {
            let repoID = space.gitContext.paneRepoAssignments[session.paneID]
            grouped[repoID, default: []].append(session.state)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0 > $1 }
        }
        return grouped
    }

    var body: some View {
        let latestStatus = PaneStatusManager.shared.latestStatus(in: space)
        let repoOrder = space.gitContext.pinnedRepoOrder
        let sessionsByRepo = groupSessionsByRepo()
        let nonRepoDots = sessionsByRepo[nil] ?? []
        let hasRepoLines = !repoOrder.isEmpty
        let hasNonRepoDots = !nonRepoDots.isEmpty
        let hasSessions = !sessions.isEmpty

        VStack(alignment: .leading, spacing: 2) {
            if hasRepoLines {
                let visibleRepos = Array(repoOrder.prefix(maxVisibleLines))
                ForEach(visibleRepos, id: \.self) { repoID in
                    if let repoStatus = space.gitContext.repoStatuses[repoID] {
                        let repoDots = sessionsByRepo[repoID] ?? []
                        let prependedDots: [ClaudeSessionState] = (repoOrder.count == 1 && hasNonRepoDots) ? nonRepoDots : []

                        RepoStatusLineView(
                            repoStatus: repoStatus,
                            subtitleColor: subtitleColor,
                            claudeDots: repoDots,
                            prependedDots: prependedDots
                        )
                    }
                }

                if repoOrder.count > maxVisibleLines {
                    Text("+\(repoOrder.count - maxVisibleLines) more")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.45))
                }

                if repoOrder.count > 1 && hasNonRepoDots {
                    ClaudeSessionDotsView(states: nonRepoDots)
                }
            } else if hasSessions {
                ClaudeSessionDotsView(states: sessions.map(\.state).sorted { $0 > $1 })
            }

            if let status = latestStatus {
                Text(String(status.label.prefix(50)))
                    .font(.system(size: 10))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
