import Foundation

/// Abstraction over workspace access for testability.
///
/// `WorktreeOrchestrator` depends on this protocol instead of `WindowCoordinator`
/// directly, allowing tests to inject a mock workspace provider without needing
/// real windows or controllers.
@MainActor
protocol WorkspaceProviding: AnyObject {
    /// All workspace collections across all windows.
    var allWorkspaceCollections: [WorkspaceCollection] { get }
    /// The active workspace in the current key window, if any.
    func activeWorkspaceForKeyWindow() -> Workspace?
}
