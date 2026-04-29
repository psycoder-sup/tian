import Foundation

/// Errors that can occur during worktree operations.
enum WorktreeError: Error, CustomStringConvertible {
    /// The specified directory is not inside a git repository.
    case notAGitRepo(directory: String)
    /// Branch exists when trying to create a new one.
    case branchAlreadyExists(branchName: String)
    /// The worktree directory already exists on disk.
    case worktreePathExists(path: String)
    /// Unhandled git error with the full command and stderr.
    case gitError(command: String, stderr: String)
    /// Worktree has uncommitted changes (on remove without force).
    case uncommittedChanges(path: String)
    /// TOML config parsing failed.
    case configParseError(message: String)
    /// User cancelled setup commands.
    case setupCancelled
    /// A setup command exceeded the timeout.
    case setupTimeout(command: String)
    /// A worktree close is already in flight; the caller must wait.
    case closeInFlight

    var description: String {
        switch self {
        case .notAGitRepo(let directory):
            "'\(directory)' is not inside a git repository"
        case .branchAlreadyExists(let branchName):
            "Branch '\(branchName)' already exists. Use --existing to check out an existing branch."
        case .worktreePathExists(let path):
            "Worktree path already exists: \(path)"
        case .gitError(let command, let stderr):
            "Git command failed: \(command)\n\(stderr)"
        case .uncommittedChanges(let path):
            "Worktree at '\(path)' has uncommitted changes. Use --force to remove anyway."
        case .configParseError(let message):
            "Failed to parse .tian/config.toml: \(message)"
        case .setupCancelled:
            "Setup cancelled by user"
        case .setupTimeout(let command):
            "Setup command timed out: \(command)"
        case .closeInFlight:
            "Another worktree close is in progress. Try again in a moment."
        }
    }
}
