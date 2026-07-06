import AppKit

/// Actions that can be triggered by keyboard shortcuts.
/// In M6, these will be mapped to user-configurable key bindings.
enum KeyAction: Hashable {
    // Session navigation
    case newSession
    case nextSession
    case previousSession
    case goToSession(Int) // 1-indexed into hierarchicalOrder()

    // Workspace navigation
    case nextWorkspace
    case previousWorkspace
    case newWorkspace
    case closeWorkspace
    // Sidebar
    case toggleSidebar
    case focusSidebar

    // Session rename
    case renameSession

    // Session overview grid
    case toggleSessionOverview

    // Session panes (Claude / terminal areas)
    case toggleTerminalPanel
    case cycleFocusArea

    // Debug
    case toggleDebugOverlay
}
