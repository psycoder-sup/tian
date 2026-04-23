import Foundation

/// Configures a fresh `TerminalSurfaceView` for the given section kind.
///
/// Keeps the `"claude\n"` literal in exactly one place — every pane-creation
/// call site routes through here to enforce FR-05 / FR-11.
enum SectionSpawner {
    /// - Parameters:
    ///   - view: the `TerminalSurfaceView` to configure. Must not yet be
    ///     attached to a window (debug-asserted); the initial-* fields are
    ///     read once during `GhosttyTerminalSurface.createSurface`.
    ///   - kind: which section the pane belongs to. Claude panes receive
    ///     `initialInput = "claude\n"`; Terminal panes get `nil`.
    ///   - workingDirectory: starting working directory for the shell.
    ///   - environmentVariables: pre-built TIAN_* env vars (computed by
    ///     the caller via `EnvironmentBuilder` / `PaneHierarchyContext`).
    @MainActor
    static func configure(
        view: TerminalSurfaceView,
        kind: SectionKind,
        workingDirectory: String,
        environmentVariables: [String: String]
    ) {
        assert(view.window == nil, "SectionSpawner.configure must be called before the view enters a window")

        view.initialWorkingDirectory = workingDirectory
        view.environmentVariables = environmentVariables
        switch kind {
        case .claude:
            view.initialInput = "claude\n"
        case .terminal:
            view.initialInput = nil
        }
    }
}
