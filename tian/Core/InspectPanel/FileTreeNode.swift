import Foundation

struct FileTreeNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let kind: Kind
    let relativePath: String

    enum Kind: Sendable, Hashable {
        case directory(canRead: Bool)
        case file(ext: String?)
    }

    var isDirectory: Bool {
        if case .directory = kind { return true } else { return false }
    }
}
