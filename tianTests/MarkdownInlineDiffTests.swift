import Foundation
import Testing
@testable import tian

/// Pure, git-free tests for the line-level segmenter backing the markdown
/// reader's inline diff.
struct MarkdownInlineDiffTests {

    /// Encodes segments as `"kind:text"` strings so whole-sequence equality is
    /// expressible (arrays of tuples aren't `Equatable`).
    private func encode(_ segments: [MarkdownDiffSegment]) -> [String] {
        segments.map { "\($0.kind):\($0.text)" }
    }

    @Test func modifiedLineSplitsIntoRemovedThenAdded() {
        let segments = MarkdownInlineDiff.segments(old: "a\nb\nc", new: "a\nB\nc")
        #expect(encode(segments) == ["unchanged:a", "removed:b", "added:B", "unchanged:c"])
    }

    @Test func pureAddition() {
        let segments = MarkdownInlineDiff.segments(old: "a\nc", new: "a\nb\nc")
        #expect(encode(segments) == ["unchanged:a", "added:b", "unchanged:c"])
    }

    @Test func pureDeletion() {
        let segments = MarkdownInlineDiff.segments(old: "a\nb\nc", new: "a\nc")
        #expect(encode(segments) == ["unchanged:a", "removed:b", "unchanged:c"])
    }

    @Test func identicalIsOneUnchangedSegment() {
        let segments = MarkdownInlineDiff.segments(old: "a\nb\nc", new: "a\nb\nc")
        #expect(encode(segments) == ["unchanged:a\nb\nc"])
    }

    @Test func emptyBaselineIsAllAdded() {
        let segments = MarkdownInlineDiff.segments(old: "", new: "x\ny")
        #expect(encode(segments) == ["added:x\ny"])
    }

    @Test func trailingNewlineNormalizedAwayNoSpuriousChange() {
        let segments = MarkdownInlineDiff.segments(old: "a\nb", new: "a\nb\n")
        #expect(encode(segments) == ["unchanged:a\nb"])
    }

    @Test func consecutiveAddsCoalesceIntoOneSegment() {
        let segments = MarkdownInlineDiff.segments(old: "a\nd", new: "a\nb\nc\nd")
        #expect(encode(segments) == ["unchanged:a", "added:b\nc", "unchanged:d"])
    }

    @Test func segmentIDsAreUnique() {
        let segments = MarkdownInlineDiff.segments(old: "a\nb\nc", new: "a\nB\nc")
        #expect(Set(segments.map(\.id)).count == segments.count)
    }
}
