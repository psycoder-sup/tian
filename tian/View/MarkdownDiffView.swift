import SwiftUI
import MarkdownUI

/// The "Diff" face of the markdown reader. Renders the open file's working-tree
/// content as rendered markdown, with changed regions marked **in place**:
/// added runs get a green change-bar + tint, removed runs (the old HEAD lines)
/// get a red change-bar + tint and are struck through. Fidelity is line/block
/// level — a modified line shows as the old line followed by the new line —
/// because MarkdownUI can't mark individual words inside a rendered paragraph.
///
/// The diff data + load lifecycle live on `MarkdownDocument` (tab-lived, cached
/// across tab switches). This view renders the current snapshot; the reader
/// drives `refreshDiffIfNeeded()`.
struct MarkdownDiffView: View {
    let document: MarkdownDocument

    /// Above this many total lines, skip segmentation and render plain to bound
    /// the per-segment `Markdown` view count.
    private static let segmentLineCap = 5_000

    /// Pre-parsed segments, cached so a body re-evaluation doesn't re-parse.
    @State private var rendered: [Rendered] = []

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { rebuild() }
            .onChange(of: document.diffOutcome) { _, _ in rebuild() }
    }

    @ViewBuilder
    private var content: some View {
        switch document.diffOutcome {
        case nil:
            banner("Loading…")
        case .notInRepo:
            plainDoc(banner: "Not in a git repository — nothing to diff.")
        case .segments(let segments):
            if segments.allSatisfy({ $0.kind == .unchanged }) {
                plainDoc(banner: "No changes against HEAD.")
            } else if lineCount(segments) > Self.segmentLineCap {
                plainDoc(banner: nil)
            } else {
                diffScroll
            }
        }
    }

    // MARK: - Diff rendering

    private var diffScroll: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rendered) { segment in
                    segmentRow(segment)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func segmentRow(_ segment: Rendered) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(barColor(segment.kind))
                .frame(width: 3)

            Markdown(segment.content)
                .markdownTheme(segment.kind == .removed ? .tianReaderRemoved : .tianReader)
                .textSelection(.enabled)
                .padding(.leading, 9)
                .padding(.trailing, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(tint(segment.kind))
        .opacity(segment.kind == .removed ? 0.8 : 1)
    }

    private func barColor(_ kind: MarkdownDiffSegment.Kind) -> Color {
        switch kind {
        case .added:     return DiffColors.added
        case .removed:   return DiffColors.deleted
        case .unchanged: return .clear
        }
    }

    private func tint(_ kind: MarkdownDiffSegment.Kind) -> Color {
        switch kind {
        case .added:     return DiffColors.added.opacity(0.08)
        case .removed:   return DiffColors.deleted.opacity(0.08)
        case .unchanged: return .clear
        }
    }

    // MARK: - Fallbacks

    /// Renders the file plainly (the normal reader face), optionally with a
    /// muted banner above — used for not-in-repo, no-changes, and the
    /// large-file guard.
    private func plainDoc(banner text: String?) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                if let text { bannerLabel(text) }
                Markdown(document.content)
                    .markdownTheme(.tianReader)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func banner(_ text: String) -> some View {
        bannerLabel(text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
    }

    private func bannerLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    // MARK: - Cache

    private struct Rendered: Identifiable {
        let id: Int
        let kind: MarkdownDiffSegment.Kind
        let content: MarkdownContent
    }

    private func rebuild() {
        guard case .segments(let segments) = document.diffOutcome else {
            rendered = []
            return
        }
        rendered = segments.map {
            Rendered(id: $0.id, kind: $0.kind, content: MarkdownContent($0.text))
        }
    }

    private func lineCount(_ segments: [MarkdownDiffSegment]) -> Int {
        segments.reduce(0) { $0 + $1.text.components(separatedBy: "\n").count }
    }
}
