import Foundation

enum WorktreeKind: Sendable, Equatable {
    case linkedWorktree
    case mainCheckout
    case notARepo
    case noWorkingDirectory
}
