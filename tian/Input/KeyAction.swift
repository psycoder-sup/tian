import AppKit

/// Actions that can be triggered by keyboard shortcuts.
/// In M6, these will be mapped to user-configurable key bindings.
enum KeyAction: Hashable {
    // Tab navigation
    case nextTab
    case previousTab
    case goToTab(Int) // 1-indexed
    case newTab

    // Space navigation
    case nextSpace
    case previousSpace
    case newSpace

    // Workspace navigation
    case nextWorkspace
    case previousWorkspace
    case newWorkspace
    case closeWorkspace
    // Sidebar
    case toggleSidebar
    case focusSidebar

    // Debug
    case toggleDebugOverlay
}
