import Foundation

struct FileTreeNode: Identifiable, Hashable, Sendable {
    /// Canonical absolute path. Stable across refreshes; used as `Identifiable.id`.
    let id: String
    let name: String
    let kind: Kind
    /// Path relative to the tree root, used to look up `GitFileStatus` for badges.
    let relativePath: String

    enum Kind: Sendable, Hashable {
        case directory(canRead: Bool)
        case file(ext: String?)
    }

    var isDirectory: Bool {
        if case .directory = kind { return true } else { return false }
    }
}
