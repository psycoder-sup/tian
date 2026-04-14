import SwiftUI

/// Displays a single git repo's status in the sidebar.
/// Row 1: [session dots] [separator] [branch name]
/// Row 2: [change badge +/-] [PR badge] (only if changes or PR exist)
struct RepoStatusLineView: View {
    let repoStatus: GitRepoStatus
    let subtitleColor: Color
    var claudeDots: [ClaudeSessionState] = []
    var prependedDots: [ClaudeSessionState] = []

    private var hasDots: Bool {
        !prependedDots.isEmpty || !claudeDots.isEmpty
    }

    private var hasGitRow: Bool {
        !repoStatus.diffSummary.isEmpty || repoStatus.prStatus != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if !prependedDots.isEmpty {
                    ClaudeSessionDotsView(states: prependedDots)
                }

                if !claudeDots.isEmpty {
                    ClaudeSessionDotsView(states: claudeDots)
                }

                if hasDots {
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color(white: 0.3))
                        .frame(width: 2, height: 1)
                }

                Text(repoStatus.branchName ?? "unknown")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if hasGitRow {
                HStack(spacing: 4) {
                    ChangeBadgeView(
                        diffSummary: repoStatus.diffSummary,
                        changedFiles: repoStatus.changedFiles
                    )

                    if let prStatus = repoStatus.prStatus {
                        PRStatusIndicatorView(prStatus: prStatus)
                    }
                }
            }
        }
    }
}
