import SwiftUI

/// A single collapsible file's diff group in the Diff body
/// (FR-T11 / FR-T12 / FR-T13 / FR-T14).
///
/// Layout:
///   - 28 px header row: chevron, status dot, path, status word, +/− counts.
///     Tapping the row toggles `isCollapsed` (the parent owns this binding so
///     the collapse map survives tab switches per FR-T30).
///   - When expanded: per-hunk header bar followed by a per-line grid of
///     `[old #][new #][marker][text]`. Truncated hunks show a muted
///     `… N more lines` placeholder (FR-T13).
///   - Binary or oversize-gated files render a single italic
///     "Binary or large file" line in place of hunks (FR-T14).
struct GitDiffFileGroup: View {
    let file: GitFileDiff
    @Binding var isCollapsed: Bool

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isCollapsed.toggle()
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(headerA11yLabel)
                .accessibilityAddTraits(.isButton)

            if !isCollapsed {
                if file.isBinary {
                    Text("Binary or large file")
                        .font(.system(size: 11, design: .monospaced).italic())
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                        hunkBlock(hunk)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header (FR-T11)

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.55))
                .frame(width: 10, alignment: .center)

            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            Text(file.path)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(statusWord)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.35))

            Spacer(minLength: 4)

            if file.additions > 0 {
                Text("+\(file.additions)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DiffColors.added.opacity(0.85))
            }
            if file.deletions > 0 {
                Text("−\(file.deletions)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DiffColors.deleted.opacity(0.85))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.white.opacity(0.02))
    }

    // MARK: - Hunk block (FR-T12 / FR-T13)

    @ViewBuilder
    private func hunkBlock(_ hunk: GitDiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color(red: 147/255, green: 197/255, blue: 253/255).opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.08))

            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                DiffLineRow(line: line)
            }

            if hunk.truncatedLines > 0 {
                Text("… \(hunk.truncatedLines) more line\(hunk.truncatedLines == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Tokens

    private var statusColor: Color { file.status.color }

    private var statusWord: String {
        switch file.status {
        case .added:    return "ADDED"
        case .modified: return "MODIFIED"
        case .deleted:  return "DELETED"
        case .renamed:  return "RENAMED"
        case .unmerged: return "UNMERGED"
        }
    }

    private var headerA11yLabel: String {
        var s = "\(file.path), \(statusWord.lowercased())"
        if file.additions > 0 { s += ", \(file.additions) addition\(file.additions == 1 ? "" : "s")" }
        if file.deletions > 0 { s += ", \(file.deletions) deletion\(file.deletions == 1 ? "" : "s")" }
        return s
    }
}

// MARK: - Diff line row

/// Single diff line with `[old #][new #][marker][text]` columns (FR-T12).
struct DiffLineRow: View {
    let line: GitDiffLine

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(Color.primary.opacity(0.3))

            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.trailing, 6)

            Text(marker)
                .frame(width: 12, alignment: .center)
                .foregroundStyle(markerColor)

            Text(line.text.isEmpty ? " " : line.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(textColor)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.vertical, 1)
        .padding(.trailing, 8)
        .background(rowBackground)
    }

    private var marker: String {
        switch line.kind {
        case .added:   return "+"
        case .deleted: return "−"
        case .context: return " "
        }
    }

    private var markerColor: Color {
        switch line.kind {
        case .added:   return DiffColors.added.opacity(0.85)
        case .deleted: return DiffColors.deleted.opacity(0.85)
        case .context: return Color.primary.opacity(0.3)
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .added, .deleted: return Color.primary.opacity(0.85)
        case .context:         return Color.primary.opacity(0.55)
        }
    }

    private var rowBackground: Color {
        switch line.kind {
        case .added:   return DiffColors.added.opacity(0.07)
        case .deleted: return DiffColors.deleted.opacity(0.08)
        case .context: return Color.clear
        }
    }
}

// MARK: - Previews

#Preview("Diff group – modified, expanded") {
    let file = GitFileDiff(
        path: "tian/View/InspectPanel/InspectPanelView.swift",
        status: .modified,
        additions: 12,
        deletions: 4,
        hunks: [
            GitDiffHunk(
                header: "@@ -10,4 +10,12 @@ struct InspectPanelView",
                lines: [
                    GitDiffLine(kind: .context, oldLineNumber: 10, newLineNumber: 10, text: "    var body: some View {"),
                    GitDiffLine(kind: .deleted, oldLineNumber: 11, newLineNumber: nil, text: "        oldStuff()"),
                    GitDiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 11, text: "        newStuff()"),
                    GitDiffLine(kind: .added, oldLineNumber: nil, newLineNumber: 12, text: "        moreStuff()"),
                    GitDiffLine(kind: .context, oldLineNumber: 12, newLineNumber: 13, text: "    }")
                ],
                truncatedLines: 0
            )
        ],
        isBinary: false
    )
    return GitDiffFileGroup(file: file, isCollapsed: .constant(false))
        .frame(width: 480)
        .padding()
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Diff group – binary, expanded") {
    let file = GitFileDiff(
        path: "assets/logo.png",
        status: .modified,
        additions: 0,
        deletions: 0,
        hunks: [],
        isBinary: true
    )
    return GitDiffFileGroup(file: file, isCollapsed: .constant(false))
        .frame(width: 480)
        .padding()
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Diff group – collapsed") {
    let file = GitFileDiff(
        path: "tian/Pane/PaneViewModel.swift",
        status: .added,
        additions: 240,
        deletions: 0,
        hunks: [],
        isBinary: false
    )
    return GitDiffFileGroup(file: file, isCollapsed: .constant(true))
        .frame(width: 480)
        .padding()
        .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
