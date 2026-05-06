import SwiftUI

/// One commit row in the Branch tab body (FR-T21).
///
/// Layout (38 px tall):
///   - Lane gutter spacer matching the gutter width drawn by
///     `BranchGraphCanvas` so the row's text column starts at the same x for
///     every commit.
///   - VStack:
///       * top line  — short SHA · subject · branch chips · tag chip (FR-T21)
///       * meta line — author · relative time · "merge" marker if applicable
///
/// HEAD-ring is drawn by the canvas overlay; the chip styling here is just
/// for branch refs / tags. Hover has no click action (FR-T24).
struct BranchCommitRow: View {
    let commit: GitCommit
    let lanes: [GitLane]
    /// Whether this commit is the current HEAD (renders a ring on the lane
    /// node — visible in the canvas overlay, not the row itself).
    let isHead: Bool
    /// Lane gutter width — matches `BranchGraphCanvas.gutterWidth(for:)` so
    /// the row's content sits flush with the right edge of the rails.
    let gutterWidth: CGFloat

    init(commit: GitCommit, lanes: [GitLane], isHead: Bool = false, gutterWidth: CGFloat) {
        self.commit = commit
        self.lanes = lanes
        self.isHead = isHead
        self.gutterWidth = gutterWidth
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Reserve room for the canvas-drawn lane gutter.
            Spacer()
                .frame(width: gutterWidth)

            VStack(alignment: .leading, spacing: 2) {
                topLine
                metaLine
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 38, alignment: .center)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(a11yLabel)
    }

    // MARK: - Top line

    private var topLine: some View {
        HStack(spacing: 6) {
            Text(commit.shortSha)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.45))

            Text(commit.subject)
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            if isHead {
                Text("HEAD")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color(red: 147/255, green: 197/255, blue: 253/255).opacity(0.22))
                    )
                    .foregroundStyle(Color.primary.opacity(0.85))
            }

            ForEach(commit.headRefs, id: \.self) { ref in
                branchChip(ref)
            }

            if let tag = commit.tag {
                tagChip(tag)
            }
        }
    }

    // MARK: - Meta line

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text(commit.author)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.tail)

            Text("·").foregroundStyle(Color.primary.opacity(0.25))

            Text(commit.when, style: .relative)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.4))

            if commit.isMerge {
                Text("·").foregroundStyle(Color.primary.opacity(0.25))
                Text("merge")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.45))
            }
        }
    }

    // MARK: - Chips

    private func branchChip(_ ref: String) -> some View {
        Text(ref)
            .font(.system(size: 9, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(Color(red: 96/255, green: 165/255, blue: 250/255).opacity(0.18))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(red: 96/255, green: 165/255, blue: 250/255).opacity(0.35), lineWidth: 0.5)
                    )
            )
            .foregroundStyle(Color.primary.opacity(0.8))
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill").font(.system(size: 8))
            Text(tag).font(.system(size: 9, design: .monospaced))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(
            Capsule()
                .fill(Color(red: 250/255, green: 204/255, blue: 21/255).opacity(0.18))
                .overlay(
                    Capsule()
                        .strokeBorder(Color(red: 250/255, green: 204/255, blue: 21/255).opacity(0.35), lineWidth: 0.5)
                )
        )
        .foregroundStyle(Color.primary.opacity(0.8))
    }

    // MARK: - A11y (FR-T34)

    private var a11yLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relativeTime = formatter.localizedString(for: commit.when, relativeTo: Date())
        var s = "\(commit.shortSha), \(commit.subject), by \(commit.author), \(relativeTime)"
        if commit.isMerge { s += ", merge" }
        return s
    }
}

// MARK: - Previews

#Preview("Commit row – simple") {
    let commit = GitCommit(
        sha: "0000000000000000000000000000000000000000",
        shortSha: "0000000",
        laneIndex: 0,
        parentShas: ["1111111111111111111111111111111111111111"],
        author: "psycoder",
        when: Date(timeIntervalSinceNow: -3600),
        subject: "feat(inspect-panel): wire diff + branch bodies",
        isMerge: false,
        headRefs: ["main"],
        tag: nil
    )
    let lanes = [GitLane(id: "main", label: "main", colorIndex: 0, isCollapsed: false)]
    return BranchCommitRow(commit: commit, lanes: lanes, isHead: true, gutterWidth: 28)
        .frame(width: 420)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Commit row – merge with tag") {
    let commit = GitCommit(
        sha: "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
        shortSha: "deadbee",
        laneIndex: 1,
        parentShas: ["aaaaaaa", "bbbbbbb"],
        author: "alice",
        when: Date(timeIntervalSinceNow: -86_400),
        subject: "Merge pull request #42 from feature/something",
        isMerge: true,
        headRefs: ["origin/main"],
        tag: "v0.4.2"
    )
    let lanes = [
        GitLane(id: "main", label: "main", colorIndex: 0, isCollapsed: false),
        GitLane(id: "feature/something", label: "feature/something", colorIndex: 1, isCollapsed: false)
    ]
    return BranchCommitRow(commit: commit, lanes: lanes, isHead: false, gutterWidth: 42)
        .frame(width: 480)
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
