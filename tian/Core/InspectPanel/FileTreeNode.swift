import Foundation

struct FileTreeNode: Identifiable, Hashable, Sendable {
    /// Canonical absolute path. Stable across refreshes; used as `Identifiable.id`.
    let id: String
    let name: String
    let kind: Kind
    /// Path relative to the tree root, used to look up `GitFileStatus` for badges.
    let relativePath: String
    /// Distance from the tree root: root children have depth 0, their children depth 1, etc.
    /// Pre-computed to avoid scanning `relativePath` characters on every row render.
    let depth: Int

    enum Kind: Sendable, Hashable {
        case directory(canRead: Bool)
        case file(ext: String?)
    }

    var isDirectory: Bool {
        if case .directory = kind { return true } else { return false }
    }
}
