import Foundation

enum WorktreeKind: Sendable, Equatable {
    case linkedWorktree
    case mainCheckout
    case notARepo
    case noWorkingDirectory

    /// The lowercase suffix rendered in the header / subheader. `nil` when
    /// the panel should show the empty state instead of a context label.
    var label: String? {
        switch self {
        case .linkedWorktree: "worktree"
        case .mainCheckout:   "repo"
        case .notARepo:       "local"
        case .noWorkingDirectory: nil
        }
    }

    /// Classifies the directory by reusing `GitStatusService.detectRepo`.
    /// Pass `nil` when the active space has no resolvable working directory.
    static func classify(directory: String?) async -> WorktreeKind {
        guard let directory, !directory.isEmpty else { return .noWorkingDirectory }
        guard let location = await GitStatusService.detectRepo(directory: directory) else {
            return .notARepo
        }
        return location.isWorktree ? .linkedWorktree : .mainCheckout
    }
}
