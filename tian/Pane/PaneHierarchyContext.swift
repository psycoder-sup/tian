import Foundation

/// Lightweight context carrying hierarchy IDs from the workspace chain
/// down to `PaneViewModel`, enabling environment variable injection
/// at surface creation time.
struct PaneHierarchyContext: Sendable {
    let socketPath: String
    let workspaceID: UUID
    let spaceID: UUID
    let tabID: UUID
    let cliPath: String
}
