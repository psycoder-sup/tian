import Foundation

/// Codable persisted shape of a workspace's SSH target. Stored as an optional
/// field on `WorkspaceState` (added in schema v8), so pre-v8 records — which
/// have no `remote` key — decode as `nil` (a local workspace) without migration.
struct RemoteConnectionState: Codable, Sendable, Equatable {
    let host: String
    let remoteDirectory: String

    init(host: String, remoteDirectory: String) {
        self.host = host
        self.remoteDirectory = remoteDirectory
    }

    init(_ remote: RemoteConnection) {
        self.host = remote.host
        self.remoteDirectory = remote.remoteDirectory
    }

    var remoteConnection: RemoteConnection {
        RemoteConnection(host: host, remoteDirectory: remoteDirectory)
    }
}
