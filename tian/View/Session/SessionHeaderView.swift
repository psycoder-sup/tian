import AppKit
import SwiftUI

/// Slim chrome header pinned to the top of a Session's Claude region. Replaces
/// the former Claude section tab bar's leading header (FR-26): a git-branch
/// glyph, the session name, and the session's current branch.
///
/// The window hides its titlebar and draws content up under the traffic
/// lights, so this header also serves as intentional chrome behind them. The
/// terminal panel gets no header — its dock/reset controls live on the
/// terminal-toggle status-bar button.
struct SessionHeaderView: View {
    /// Layout height of the header, in points.
    static let height: CGFloat = 44

    @Bindable var session: Session

    /// Extra leading/trailing padding applied to the header's content (not its
    /// background) so the text clears the traffic lights and inspect-panel rail
    /// when the Claude region meets those window edges. The background stays
    /// full-bleed so the chrome reads as continuous behind the traffic lights.
    var leadingContentInset: CGFloat = 0
    var trailingContentInset: CGFloat = 0

    /// The primary branch to display, matching the sidebar's pane-first order:
    /// the Claude pane's own worktree status first — which distinguishes sibling
    /// worktrees sharing a `GitRepoID` — falling back to the first pinned repo's
    /// branch.
    private var branchName: String? {
        if let paneID = session.claudePaneID,
           let branch = session.gitContext.status(forPane: paneID)?.branchName {
            return branch
        }
        if let repoID = session.gitContext.pinnedRepoOrder.first {
            return session.gitContext.repoStatuses[repoID]?.branchName
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.chromeForeground.opacity(0.9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(session.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.chromeForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(branchName ?? "—")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(red: 180/255, green: 188/255, blue: 200/255).opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, 12 + leadingContentInset)
        .padding(.trailing, 12 + trailingContentInset)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.displayName)\(branchName.map { ", branch \($0)" } ?? "")")
    }

    /// Opaque fill matching the terminal/Claude pane background (so the header
    /// reads as part of the pane chrome rather than a floating bar), grounded by
    /// a hairline separator along its bottom edge.
    private var headerBackground: some View {
        Color(nsColor: .terminalBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
            }
    }
}
