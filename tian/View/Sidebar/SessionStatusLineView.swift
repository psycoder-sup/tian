import SwiftUI

/// Status area below the session name in the sidebar.
/// One row: git branch (worktree-aware) + change badge + PR indicator; plus an
/// optional free-form status label line beneath it.
struct SessionStatusLineView: View {
    let isActive: Bool
    /// Worktree-first git status backing the branch + diff / PR badges,
    /// precomputed by the parent row so the same walk isn't repeated for the
    /// row's accessibility string.
    let repoStatus: GitRepoStatus?
    /// Latest free-form Claude status label across the session's panes,
    /// precomputed by the parent row (mirror-based read).
    let latestStatus: PaneStatus?

    private var subtitleColor: Color {
        if isActive {
            Color(red: 0.35, green: 0.6, blue: 1.0).opacity(0.7)
        } else {
            Color(red: 0.45, green: 0.55, blue: 0.7).opacity(0.7)
        }
    }

    /// Non-empty branch name to render as the secondary label, else `nil`.
    private var resolvedBranch: String? {
        guard let branch = repoStatus?.branchName, !branch.isEmpty else { return nil }
        return branch
    }

    private var hasGitRow: Bool {
        guard let repoStatus else { return false }
        return !repoStatus.diffSummary.isEmpty || repoStatus.prStatus != nil
    }

    var body: some View {
        let status = repoStatus

        VStack(alignment: .leading, spacing: 2) {
            // Branch + diff/PR badges. Shown when there's a branch and/or repo
            // changes / PR.
            if resolvedBranch != nil || hasGitRow {
                HStack(spacing: 4) {
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

                    if let status, !status.diffSummary.isEmpty {
                        ChangeBadgeView(
                            diffSummary: status.diffSummary,
                            changedFiles: status.changedFiles
                        )
                    }

                    if let prStatus = status?.prStatus {
                        PRStatusIndicatorView(prStatus: prStatus)
                    }
                }
            }

            // Optional free-form status label (Claude "status" line).
            if let latestStatus {
                Text(String(latestStatus.label.prefix(50)))
                    .font(.system(size: 10))
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
