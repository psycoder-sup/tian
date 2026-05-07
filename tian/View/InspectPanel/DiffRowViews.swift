import SwiftUI

// MARK: - File header row (FR-T11)

/// Collapsible per-file header (FR-T11). Owned by `InspectDiffBody`'s flat
/// row stream; tapping toggles the binding the parent maintains in
/// `InspectTabState.diffCollapse` so collapse survives a tab round-trip
/// (FR-T30).
struct DiffFileHeaderRow: View {
    let file: GitFileDiff
    @Binding var isCollapsed: Bool

    static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.55))
                .frame(width: 10, alignment: .center)

            Circle()
                .fill(file.status.color)
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
        .frame(height: Self.height)
        .background(Color.white.opacity(0.02))
        .contentShape(Rectangle())
        .onTapGesture {
            // No animation: animating collapse on a 5 000-line file forces
            // SwiftUI to interpolate the entire flat row list every frame.
            isCollapsed.toggle()
        }
        .accessibilityElement()
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var statusWord: String { file.status.accessibilityLabel.uppercased() }

    private var a11yLabel: String {
        var s = "\(file.path), \(file.status.accessibilityLabel)"
        if file.additions > 0 { s += ", \(file.additions) addition\(file.additions == 1 ? "" : "s")" }
        if file.deletions > 0 { s += ", \(file.deletions) deletion\(file.deletions == 1 ? "" : "s")" }
        return s
    }
}

// MARK: - Hunk header bar (FR-T12)

struct DiffHunkHeaderRow: View {
    let header: String

    static let height: CGFloat = 18

    var body: some View {
        Text(header)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Color(red: 147/255, green: 197/255, blue: 253/255).opacity(0.85))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: Self.height, alignment: .leading)
            .background(Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.08))
    }
}

// MARK: - Diff line row (FR-T13)

/// Single diff line with `[old #][new #][marker][text]` columns. Fixed-
/// height + single-line truncation: variable wrapping kills `LazyVStack`
/// virtualization on 5 000-line diffs (every row would have to be measured
/// to compute scroll offsets).
struct DiffLineRow: View {
    let line: GitDiffLine

    static let height: CGFloat = 16

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
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
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(textColor)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.trailing, 8)
        .frame(height: Self.height)
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

// MARK: - Truncated hunk placeholder

struct DiffTruncatedRow: View {
    let count: Int

    var body: some View {
        Text("… \(count) more line\(count == 1 ? "" : "s")")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(Color.primary.opacity(0.3))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
    }
}

// MARK: - Binary placeholder

struct DiffBinaryPlaceholderRow: View {
    let file: GitFileDiff

    var body: some View {
        Text("Binary or large file")
            .font(.system(size: 11, design: .monospaced).italic())
            .foregroundStyle(Color.primary.opacity(0.4))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("File header – modified, expanded") {
    DiffFileHeaderRow(
        file: GitFileDiff(
            path: "tian/View/InspectPanel/InspectPanelView.swift",
            status: .modified,
            additions: 12,
            deletions: 4,
            hunks: [],
            isBinary: false
        ),
        isCollapsed: .constant(false)
    )
    .frame(width: 480)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}

#Preview("Diff line rows") {
    VStack(spacing: 0) {
        DiffHunkHeaderRow(header: "@@ -10,4 +10,12 @@ struct InspectPanelView")
        DiffLineRow(line: GitDiffLine(id: 0, kind: .context, oldLineNumber: 10, newLineNumber: 10, text: "    var body: some View {"))
        DiffLineRow(line: GitDiffLine(id: 1, kind: .deleted, oldLineNumber: 11, newLineNumber: nil, text: "        oldStuff()"))
        DiffLineRow(line: GitDiffLine(id: 2, kind: .added, oldLineNumber: nil, newLineNumber: 11, text: "        newStuff()"))
        DiffLineRow(line: GitDiffLine(id: 3, kind: .context, oldLineNumber: 12, newLineNumber: 13, text: "    }"))
    }
    .frame(width: 480)
    .background(Color(red: 8/255, green: 11/255, blue: 18/255, opacity: 0.95))
}
