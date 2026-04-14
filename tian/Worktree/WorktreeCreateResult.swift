import Foundation

/// Result of a worktree Space creation attempt.
struct WorktreeCreateResult: Sendable {
    /// The ID of the created or found Space.
    let spaceID: UUID
    /// True if an existing Space was focused instead of creating a new one.
    let existed: Bool
}
