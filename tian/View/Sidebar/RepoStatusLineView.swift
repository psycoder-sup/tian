import SwiftUI

/// A single tab's status row in the sidebar.
/// Row 1: [active-tab bar] [session dot] [tab name]
/// Row 2: [branch icon + name] [change badge +/-] [PR badge] (git tabs;
///        shown when there's a branch and/or repo changes/PR)
struct TabStatusRowView: View {
    let state: ClaudeSessionState
    /// Primary label: the tab's display name.
    let tabName: String
    /// Secondary muted label: the git branch. `nil`/empty for non-git tabs.
    let branchName: String?
    /// Repo status backing the diff / PR badges. `nil` for non-git tabs.
    var repoStatus: GitRepoStatus?
    let subtitleColor: Color
    /// Highlights this row as the space's currently-focused tab.
    var isActiveTab: Bool = false

    /// Leading indicator gutter (3) + spacing (6) + dot (8) + spacing (6):
    /// indents the badge row to sit under the tab name.
    private static let labelIndent: CGFloat = 23

    private var hasGitRow: Bool {
        guard let repoStatus else { return false }
        return !repoStatus.diffSummary.isEmpty || repoStatus.prStatus != nil
    }

    private var branchColor: Color {
        isActiveTab ? Color(white: 0.95) : subtitleColor
    }

    /// Non-empty branch name to render as the secondary label, else `nil`.
    private var resolvedBranch: String? {
        guard let branchName, !branchName.isEmpty else { return nil }
        return branchName
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

                // Primary: tab name.
                Text(tabName)
                    .font(.system(size: 10, weight: isActiveTab ? .semibold : .medium))
                    .foregroundStyle(branchColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Row 2: branch + diff/PR badges, indented under the tab name.
            // Shown for git tabs with a branch and/or repo changes/PR.
            if resolvedBranch != nil || hasGitRow {
                HStack(spacing: 4) {
                    // Secondary: git branch, always muted (branch is never the
                    // primary). Only shown for git tabs with a non-empty branch.
                    if let branch = resolvedBranch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 8))
                            Text(branch)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(subtitleColor)
                    }

                    if let repoStatus, !repoStatus.diffSummary.isEmpty {
                        ChangeBadgeView(
                            diffSummary: repoStatus.diffSummary,
                            changedFiles: repoStatus.changedFiles
                        )
                    }

                    if let prStatus = repoStatus?.prStatus {
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
