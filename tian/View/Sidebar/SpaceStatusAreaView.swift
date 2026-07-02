import SwiftUI

/// Status area below the space name in the sidebar.
/// Renders one row per tab that has a Claude session — each showing the tab's
/// status dot, its tab name, and its own branch name (worktree-aware) — plus
/// the optional free-form status label line.
struct SpaceStatusAreaView: View {
    let space: SpaceModel
    let isActive: Bool

    private var subtitleColor: Color {
        if isActive {
            Color(red: 0.35, green: 0.6, blue: 1.0).opacity(0.7)
        } else {
            Color(red: 0.45, green: 0.55, blue: 0.7).opacity(0.7)
        }
    }

    /// One display row per Claude-task tab, highest-priority state first.
    private struct TabRow: Identifiable {
        let id: UUID
        let state: ClaudeSessionState
        let tabName: String
        /// Git branch for this tab. `nil` for non-git tabs.
        let branchName: String?
        let repoStatus: GitRepoStatus?
        /// True for the space's currently-focused tab (active tab of the
        /// focused section) — drives the active-tab indicator.
        let isActiveTab: Bool
    }

    /// The id of the space's currently-focused tab: the active tab of whichever
    /// section (Claude / Terminal) currently holds focus.
    private var focusedTabID: UUID {
        switch space.focusedSectionKind {
        case .claude: space.claudeSection.activeTabID
        case .terminal: space.terminalSection.activeTabID
        }
    }

    /// Builds the per-tab rows. A tab contributes a row only when one of its
    /// panes has an active (non-inactive) Claude session; the row is driven by
    /// the highest-priority such pane, and its branch resolves worktree-first so
    /// sibling worktrees of one repo stay distinct.
    private func tabRows() -> [TabRow] {
        let focusedID = focusedTabID
        var rows: [TabRow] = []
        for tab in space.allTabs {
            guard let top = PaneStatusManager.shared.topSessionPane(in: tab) else { continue }

            // Prefer the pane's own worktree status (branch + diff + PR), so
            // sibling worktrees sharing a GitRepoID show independent badges.
            // Fall back to the shared repo status only until the worktree status
            // resolves.
            let repoID = space.gitContext.paneRepoAssignments[top.paneID]
            let repoStatus = space.gitContext.status(forPane: top.paneID)
                ?? repoID.flatMap { space.gitContext.repoStatuses[$0] }

            rows.append(TabRow(
                id: tab.id,
                state: top.state,
                tabName: tab.displayName,
                branchName: repoStatus?.branchName,
                repoStatus: repoStatus,
                isActiveTab: tab.id == focusedID
            ))
        }
        // Active tab first, then by session priority (highest-priority state first).
        return rows.sorted { lhs, rhs in
            if lhs.isActiveTab != rhs.isActiveTab { return lhs.isActiveTab }
            return lhs.state > rhs.state
        }
    }

    var body: some View {
        let latestStatus = PaneStatusManager.shared.latestStatus(in: space)
        let rows = tabRows()

        VStack(alignment: .leading, spacing: 2) {
            ForEach(rows) { row in
                TabStatusRowView(
                    state: row.state,
                    tabName: row.tabName,
                    branchName: row.branchName,
                    repoStatus: row.repoStatus,
                    subtitleColor: subtitleColor,
                    isActiveTab: row.isActiveTab
                )
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
