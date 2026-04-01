import Foundation
import Observation

/// App-level coordinator for workspace tracking. Tracks which workspace
/// is globally active (in the key window) for menu bar commands.
@MainActor @Observable
final class WorkspaceManager {
    var activeWorkspaceID: UUID?

    init() {
        self.activeWorkspaceID = nil
    }
}
