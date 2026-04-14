import Foundation
import SwiftUI

// MARK: - Identity

/// Canonical identity for a git repository, keyed by the absolute path from `git rev-parse --git-common-dir`.
/// Two panes in the same repo (even different worktrees) share the same `GitRepoID`.
struct GitRepoID: Hashable, Sendable {
    let path: String
}

// MARK: - Status

struct GitRepoStatus: Sendable {
    let repoID: GitRepoID
    var branchName: String?
    var isDetachedHead: Bool
    var diffSummary: GitDiffSummary = .empty
    var changedFiles: [GitChangedFile] = []
    var prStatus: PRStatus?
    var lastUpdated: Date
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

    var color: Color {
        switch self {
        case .modified: .yellow
        case .added: .green
        case .deleted: .red
        case .renamed: .blue
        case .unmerged: .orange
        }
    }
}

// MARK: - PR

struct PRStatus: Sendable {
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
