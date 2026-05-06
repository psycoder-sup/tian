import Foundation
import SwiftUI

// MARK: - Identity

/// Canonical identity for a git repository, keyed by the absolute path from `git rev-parse --git-common-dir`.
/// Two panes in the same repo (even different worktrees) share the same `GitRepoID`.
struct GitRepoID: Hashable, Sendable {
    let path: String
}

// MARK: - Status

struct GitRepoStatus: Sendable, Equatable {
    let repoID: GitRepoID
    var branchName: String?
    var isDetachedHead: Bool
    var diffSummary: GitDiffSummary = .empty
    var changedFiles: [GitChangedFile] = []
    var prStatus: PRStatus?
    var lastUpdated: Date

    /// Equality intentionally excludes `lastUpdated` so that a no-op refresh
    /// (same content, newer timestamp) does not trigger Observable re-renders
    /// or SwiftUI `.onChange` callbacks.
    static func == (lhs: GitRepoStatus, rhs: GitRepoStatus) -> Bool {
        lhs.repoID == rhs.repoID
            && lhs.branchName == rhs.branchName
            && lhs.isDetachedHead == rhs.isDetachedHead
            && lhs.diffSummary == rhs.diffSummary
            && lhs.changedFiles == rhs.changedFiles
            && lhs.prStatus == rhs.prStatus
    }

}

struct GitDiffSummary: Sendable, Equatable {
    var modified: Int = 0
    var added: Int = 0
    var deleted: Int = 0
    var renamed: Int = 0
    var unmerged: Int = 0

    var isEmpty: Bool {
        modified == 0 && added == 0 && deleted == 0 && renamed == 0 && unmerged == 0
    }

    var totalCount: Int {
        modified + added + deleted + renamed + unmerged
    }

    static let empty = GitDiffSummary()
}

// MARK: - Changed Files

struct GitChangedFile: Sendable, Hashable {
    let status: GitFileStatus
    let path: String
}

enum GitFileStatus: String, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case unmerged = "U"

    var letter: String { rawValue }

    /// Used when aggregating descendant statuses onto a directory row.
    /// Higher value = more attention-grabbing; the highest among descendants
    /// wins.
    var severity: Int {
        switch self {
        case .unmerged: 5
        case .modified: 4
        case .renamed:  3
        case .deleted:  2
        case .added:    1
        }
    }

    var color: Color {
        switch self {
        case .modified: Color(red: 245/255, green: 158/255, blue: 11/255)
        case .added:    Color(red: 110/255, green: 225/255, blue: 154/255)
        case .deleted:  Color(red: 255/255, green: 154/255, blue: 154/255)
        case .renamed:  Color(red: 96/255,  green: 165/255, blue: 250/255)
        case .unmerged: Color(red: 251/255, green: 146/255, blue: 60/255)
        }
    }
}

// MARK: - PR

struct PRStatus: Sendable, Equatable {
    let number: Int
    let state: PRState
    let url: URL
}

enum PRState: String, Sendable {
    case open
    case draft
    case merged
    case closed
}

extension GitFileStatus {
    var accessibilityLabel: String {
        switch self {
        case .modified: "Modified"
        case .added: "Added"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .unmerged: "Unmerged"
        }
    }
}

// MARK: - Unified Diff

struct GitFileDiff: Sendable, Equatable {
    let path: String
    let status: GitFileStatus
    let additions: Int
    let deletions: Int
    let hunks: [GitDiffHunk]
    /// True when the file was skipped because it failed the 512 KB binary
    /// gate or `git diff` reported it as binary. `hunks` is empty in this
    /// case; `additions` / `deletions` reflect git's reported counts (or 0
    /// for the size-gated case).
    let isBinary: Bool
}

struct GitDiffHunk: Sendable, Equatable, Identifiable {
    let id: Int
    let header: String   // `@@ -A,B +C,D @@ optional context`
    let lines: [GitDiffLine]
    /// Set when the hunk's emitted line count was capped at 5 000. Renderer
    /// shows a muted `… N more lines` placeholder line below.
    let truncatedLines: Int
}

struct GitDiffLine: Sendable, Equatable, Identifiable {
    enum Kind: Sendable, Equatable { case context, added, deleted }
    let id: Int
    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}

// MARK: - Commit Graph (FR-T20 / FR-T20a / FR-T25)

struct GitCommitGraph: Sendable, Equatable {
    /// Ordered, HEAD's lane first; surplus lanes (FR-T20a) collapse into a
    /// single trailing lane with `id == GitLane.collapsedID`.
    let lanes: [GitLane]
    /// Newest → oldest, max 50 entries (FR-T20).
    let commits: [GitCommit]
    /// Number of branch tips folded into the trailing "other" lane. 0 when
    /// the cap was not hit.
    let collapsedLaneCount: Int
}

struct GitLane: Sendable, Equatable {
    let id: String         // branch ref name, or `GitLane.collapsedID`
    let label: String
    let colorIndex: Int    // resolved to a Color by the view from a fixed palette
    let isCollapsed: Bool  // true only for the "other" lane

    /// Magic lane ID used for the collapsed "other" lane that aggregates
    /// surplus branches beyond the 6-lane cap (FR-T20a).
    static let collapsedID = "__other__"
}

struct GitCommit: Sendable, Equatable {
    let sha: String        // 40-char
    let shortSha: String   // 7-char
    let laneIndex: Int     // index into `GitCommitGraph.lanes`
    let parentShas: [String]
    let author: String
    let when: Date
    let subject: String
    let isMerge: Bool
    let headRefs: [String] // e.g. ["feature-auth", "origin/main"]
    let tag: String?
}
