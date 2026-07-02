import SwiftUI

/// A single tab's status row in the sidebar.
/// Row 1: [active-tab bar] [session dot] [branch name (or tab title)]
/// Row 2: [change badge +/-] [PR badge] (only when the tab's repo has changes/PR)
struct TabStatusRowView: View {
    let state: ClaudeSessionState
    let branchLabel: String
    /// Repo status backing the diff / PR badges. `nil` for non-git tabs.
    var repoStatus: GitRepoStatus?
    let subtitleColor: Color
    /// Highlights this row as the space's currently-focused tab.
    var isActiveTab: Bool = false

    /// Leading indicator gutter (3) + spacing (6) + dot (8) + spacing (6):
    /// indents the badge row to sit under the branch text.
    private static let labelIndent: CGFloat = 23

    private var hasGitRow: Bool {
        guard let repoStatus else { return false }
        return !repoStatus.diffSummary.isEmpty || repoStatus.prStatus != nil
    }

    private var branchColor: Color {
        isActiveTab ? Color(white: 0.95) : subtitleColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Active-tab indicator. Reserves a fixed-width gutter on every
                // row (clear when inactive) so rows never shift horizontally.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActiveTab ? Color.accentColor : Color.clear)
                    .frame(width: 3, height: 12)

                SessionDotView(state: state)

                Text(branchLabel)
                    .font(.system(size: 10, weight: isActiveTab ? .semibold : .medium))
                    .foregroundStyle(branchColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let repoStatus, hasGitRow {
                HStack(spacing: 4) {
                    ChangeBadgeView(
                        diffSummary: repoStatus.diffSummary,
                        changedFiles: repoStatus.changedFiles
                    )

                    if let prStatus = repoStatus.prStatus {
                        PRStatusIndicatorView(prStatus: prStatus)
                    }
                }
                .padding(.leading, Self.labelIndent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActiveTab ? [.isSelected] : [])
    }
}
