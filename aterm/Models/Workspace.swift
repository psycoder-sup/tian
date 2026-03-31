import Foundation
import Observation

/// Schema version for the workspace data model. Bumped when the
/// serialization format changes. Used by M5 persistence.
let workspaceSchemaVersion = 1

/// Serializable snapshot of a workspace's persisted fields.
/// Used for encoding (M4) and will be extended for full persistence in M5.
struct WorkspaceSnapshot: Sendable, Codable {
    let id: UUID
    let name: String
    let defaultWorkingDirectory: URL?
    let createdAt: Date
}

/// The top-level organizational unit in aterm's 4-level hierarchy
/// (Workspace > Space > Tab > Pane). Each workspace maps to a project
/// and owns a collection of spaces.
@MainActor @Observable
final class Workspace: Identifiable {
    let id: UUID
    var name: String
    var defaultWorkingDirectory: URL?
    let createdAt: Date

    let spaceCollection: SpaceCollection

    /// Called when the workspace's last space is closed.
    var onEmpty: (() -> Void)?

    // MARK: - Init

    convenience init(name: String, defaultWorkingDirectory: URL? = nil) {
        self.init(
            id: UUID(),
            name: name,
            defaultWorkingDirectory: defaultWorkingDirectory,
            createdAt: Date()
        )
    }

    private init(
        id: UUID,
        name: String,
        defaultWorkingDirectory: URL?,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.defaultWorkingDirectory = defaultWorkingDirectory
        self.createdAt = createdAt

        let workingDir = defaultWorkingDirectory?.path
            ?? ProcessInfo.processInfo.environment["HOME"]
            ?? "~"
        self.spaceCollection = SpaceCollection(workingDirectory: workingDir)

        self.spaceCollection.onEmpty = { [weak self] in
            self?.onEmpty?()
        }
    }

    // MARK: - Convenience Accessors

    var spaces: [SpaceModel] { spaceCollection.spaces }
    var activeSpaceID: UUID { spaceCollection.activeSpaceID }
    var activeSpace: SpaceModel? { spaceCollection.activeSpace }

    // MARK: - Lifecycle

    func cleanup() {
        for space in spaceCollection.spaces {
            for tab in space.tabs {
                tab.cleanup()
            }
        }
    }

    // MARK: - Serialization

    var snapshot: WorkspaceSnapshot {
        WorkspaceSnapshot(
            id: id,
            name: name,
            defaultWorkingDirectory: defaultWorkingDirectory,
            createdAt: createdAt
        )
    }

    static func from(snapshot: WorkspaceSnapshot) -> Workspace {
        Workspace(
            id: snapshot.id,
            name: snapshot.name,
            defaultWorkingDirectory: snapshot.defaultWorkingDirectory,
            createdAt: snapshot.createdAt
        )
    }
}
