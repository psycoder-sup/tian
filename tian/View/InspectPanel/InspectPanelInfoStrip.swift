import SwiftUI

/// 26 px info strip beneath the tab row (FR-T01 / FR-T06 / FR-T07 / FR-T08).
///
/// Content switches per the active tab:
///   - Files  → `{spaceName} · {worktreeKindLabel}` (FR-T06)
///   - Diff   → `{N} files +{add} −{del}` chips, or `No changes` (FR-T07)
///   - Branch → `{branch} · graph`, hidden in no-repo (FR-T08)
///
/// No-repo / no-data states per FR-T19.
///
/// Data is injected via value types so this view is pure and previewable
/// without a live view-model. Callers pass live data from
/// `InspectDiffViewModel` / `InspectBranchViewModel`.
struct InspectPanelInfoStrip: View {
    static let height: CGFloat = 26

    let activeTab: InspectTab
    let filesContext: FilesContext
    let diffSummary: DiffSummary?
    /// Current branch label or short SHA (detached HEAD). `nil` → no-repo.
    let branchLabel: String?
    let isNoRepo: Bool

    // MARK: - Supporting data shapes

    struct FilesContext {
        let spaceName: String
        /// e.g. "worktree", "repo", "local". `nil` → no working directory.
        let worktreeKindLabel: String?
    }

    struct DiffSummary {
        let fileCount: Int
        let additions: Int
        let deletions: Int
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch activeTab {
            case .files:  filesContent
            case .diff:   diffContent
            case .branch: branchContent
            }
        }
        .padding(.leading, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 0.5)
        }
    }

    // MARK: - Files content (FR-T06)

    @ViewBuilder
    private var filesContent: some View {
        let label = filesContext.worktreeKindLabel
        let text  = label.map { "\(filesContext.spaceName) · \($0)" } ?? filesContext.spaceName
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.35))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    // MARK: - Diff content (FR-T07)

    @ViewBuilder
    private var diffContent: some View {
        if isNoRepo {
            // No-repo: Diff tab is still selectable but strip shows nothing (FR-T19).
            EmptyView()
        } else if let summary = diffSummary, summary.fileCount > 0 {
            HStack(spacing: 6) {
                Text("\(summary.fileCount) file\(summary.fileCount == 1 ? "" : "s")")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.4))

                Text("+\(summary.additions)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DiffColors.added.opacity(0.85))

                Text("−\(summary.deletions)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DiffColors.deleted.opacity(0.85))
            }
        } else {
            // Empty diff or data not yet loaded (FR-T07).
            Text("No changes")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.25))
        }
    }

    // MARK: - Branch content (FR-T08)

    @ViewBuilder
    private var branchContent: some View {
        if isNoRepo {
            // Hidden in no-repo (FR-T08).
            EmptyView()
        } else if let branch = branchLabel {
            HStack(spacing: 4) {
                Text("\(branch)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("· graph")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.2))
            }
        } else {
            // Branch label not loaded yet — show nothing.
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("Info strip – Files / worktree") {
    InspectPanelInfoStrip(
        activeTab: .files,
        filesContext: .init(spaceName: "tian", worktreeKindLabel: "worktree"),
        diffSummary: nil,
        branchLabel: nil,
        isNoRepo: false
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Info strip – Files / local") {
    InspectPanelInfoStrip(
        activeTab: .files,
        filesContext: .init(spaceName: "my-project", worktreeKindLabel: "local"),
        diffSummary: nil,
        branchLabel: nil,
        isNoRepo: false
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Info strip – Diff / with changes") {
    InspectPanelInfoStrip(
        activeTab: .diff,
        filesContext: .init(spaceName: "tian", worktreeKindLabel: "repo"),
        diffSummary: .init(fileCount: 7, additions: 142, deletions: 38),
        branchLabel: "main",
        isNoRepo: false
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Info strip – Diff / no changes") {
    InspectPanelInfoStrip(
        activeTab: .diff,
        filesContext: .init(spaceName: "tian", worktreeKindLabel: "repo"),
        diffSummary: .init(fileCount: 0, additions: 0, deletions: 0),
        branchLabel: "main",
        isNoRepo: false
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Info strip – Branch") {
    InspectPanelInfoStrip(
        activeTab: .branch,
        filesContext: .init(spaceName: "tian", worktreeKindLabel: "repo"),
        diffSummary: nil,
        branchLabel: "feat/inspect-panel-tabs",
        isNoRepo: false
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Info strip – Diff / no-repo") {
    InspectPanelInfoStrip(
        activeTab: .diff,
        filesContext: .init(spaceName: "scripts", worktreeKindLabel: nil),
        diffSummary: nil,
        branchLabel: nil,
        isNoRepo: true
    )
    .frame(width: 320)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
