import Foundation

/// One contiguous run of lines sharing a diff kind, used to render the markdown
/// reader's inline (in-place) diff: the document is rendered segment-by-segment,
/// added/removed runs tinted in place.
struct MarkdownDiffSegment: Equatable, Identifiable {
    enum Kind: Equatable { case unchanged, added, removed }
    let id: Int
    let kind: Kind
    /// The run's lines, rejoined with "\n" — fed to MarkdownUI as a sub-document.
    let text: String
}

/// Pure, synchronous line-level differ. Diffs a file's committed HEAD text
/// against its working-tree text and coalesces the unified result into
/// `MarkdownDiffSegment`s. No git, no I/O — trivially unit-testable.
enum MarkdownInlineDiff {

    static func segments(old: String, new: String) -> [MarkdownDiffSegment] {
        let oldLines = lines(of: old)
        let newLines = lines(of: new)

        // stdlib Myers diff. Removals carry offsets into `old`; insertions carry
        // offsets into `new`.
        let difference = newLines.difference(from: oldLines)
        var removedOld = Set<Int>()
        var insertedNew = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removedOld.insert(offset)
            case .insert(let offset, _, _): insertedNew.insert(offset)
            }
        }

        // Reconstruct the unified order: at a changed position, removed lines
        // come before added lines (conventional diff order).
        var ordered: [(MarkdownDiffSegment.Kind, String)] = []
        var oi = 0, ni = 0
        while oi < oldLines.count || ni < newLines.count {
            if oi < oldLines.count, removedOld.contains(oi) {
                ordered.append((.removed, oldLines[oi])); oi += 1
            } else if ni < newLines.count, insertedNew.contains(ni) {
                ordered.append((.added, newLines[ni])); ni += 1
            } else if oi < oldLines.count, ni < newLines.count {
                ordered.append((.unchanged, newLines[ni])); oi += 1; ni += 1
            } else if oi < oldLines.count {
                ordered.append((.removed, oldLines[oi])); oi += 1
            } else {
                ordered.append((.added, newLines[ni])); ni += 1
            }
        }

        return coalesce(ordered)
    }

    // MARK: - Helpers

    /// Splits into lines, normalizing a single trailing newline so a file that
    /// ends in "\n" doesn't read as a spurious trailing change against a git
    /// blob (which `runGit` returns with trailing newlines trimmed).
    private static func lines(of text: String) -> [String] {
        var t = text
        if t.hasSuffix("\n") { t.removeLast() }
        // Empty file → no lines (not a single empty line).
        return t.isEmpty ? [] : t.components(separatedBy: "\n")
    }

    /// Merges consecutive same-kind lines into one segment.
    private static func coalesce(
        _ ordered: [(MarkdownDiffSegment.Kind, String)]
    ) -> [MarkdownDiffSegment] {
        var segments: [MarkdownDiffSegment] = []
        var id = 0
        var idx = 0
        while idx < ordered.count {
            let kind = ordered[idx].0
            var run: [String] = []
            while idx < ordered.count, ordered[idx].0 == kind {
                run.append(ordered[idx].1); idx += 1
            }
            segments.append(MarkdownDiffSegment(
                id: id, kind: kind, text: run.joined(separator: "\n")
            ))
            id += 1
        }
        return segments
    }
}
