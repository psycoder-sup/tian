import Foundation

/// Outcome of removing a worktree-backed Space, including any branch
/// deletion requested via `--delete-branch`. The worktree removal is the
/// primary action; branch deletion is a best-effort follow-up, so a kept
/// branch is reported rather than treated as a failure.
struct WorktreeRemovalResult: Sendable {
    /// The branch that backed the removed worktree, when branch deletion was
    /// requested and a branch name could be resolved. `nil` otherwise.
    let branchName: String?
    /// True when the branch was deleted as part of the removal.
    let branchDeleted: Bool
    /// When the branch was *not* deleted despite deletion being requested, a
    /// short reason: `"unmerged"`, `"not found"`, `"error"`, or `"no branch"`
    /// (the worktree had no branch checked out, e.g. detached HEAD). `nil`
    /// otherwise (including when deletion was not requested).
    let branchKeptReason: String?

    /// A removal that did not resolve or touch any branch (e.g. the default
    /// path without `--delete-branch`, or an early return).
    static let none = WorktreeRemovalResult(
        branchName: nil, branchDeleted: false, branchKeptReason: nil
    )
}
