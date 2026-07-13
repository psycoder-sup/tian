import AppKit
import SwiftUI

/// Per-window animation gate. True while the window is at least partially
/// visible on screen (not miniaturized, hidden, fully covered, or on another
/// Space). Decorative TimelineView animations read this via
/// `\.windowIsVisible` and pause when nobody can see them.
@MainActor @Observable
final class WindowVisibilityState {
    /// Defaults to visible so a delayed first occlusion callback can never
    /// leave a freshly shown window with frozen animations.
    private(set) var isVisible = true

    func update(from occlusionState: NSWindow.OcclusionState) {
        let visible = occlusionState.contains(.visible)
        if visible != isVisible { isVisible = visible }
    }
}

extension EnvironmentValues {
    /// Whether the hosting window is visible on screen. Set once at the
    /// window root (`WorkspaceWindowContent`); defaults to true.
    @Entry var windowIsVisible: Bool = true
    /// Whether the enclosing session is the active (opacity-1) session in its
    /// workspace. Inactive sessions stay mounted at opacity 0 to preserve
    /// their Metal surfaces; defaults to true.
    @Entry var sessionIsVisible: Bool = true
}
