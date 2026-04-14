/// Lifecycle state of a single terminal pane.
enum PaneState: Sendable, Equatable {
    /// Shell is running normally.
    case running
    /// Shell exited with a non-zero code; pane is kept open showing the overlay.
    case exited(code: UInt32)
    /// Shell failed to spawn (ghostty_surface_new returned nil).
    case spawnFailed
}
