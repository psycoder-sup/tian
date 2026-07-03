import Foundation

/// Information about a surface with a running foreground process.
struct RunningProcessInfo: Sendable {
    let workspaceName: String
    let sessionName: String
    let paneID: UUID
}

/// Detects foreground processes across all terminal surfaces using ghostty's built-in
/// `ghostty_surface_needs_confirm_quit` API.
@MainActor
enum ProcessDetector {

    /// Returns info about every surface that has a running foreground process.
    static func detectRunningProcesses(
        in collections: [WorkspaceCollection]
    ) -> [RunningProcessInfo] {
        var results: [RunningProcessInfo] = []

        for collection in collections {
            for workspace in collection.workspaces {
                for session in workspace.sessionCollection.sessions {
                    for pane in session.allPanes {
                        for (paneID, terminalSurface) in pane.surfaces {
                            guard let surface = terminalSurface.surface,
                                  ghostty_surface_needs_confirm_quit(surface) else { continue }
                            results.append(RunningProcessInfo(
                                workspaceName: workspace.name,
                                sessionName: session.displayName,
                                paneID: paneID
                            ))
                        }
                    }
                }
            }
        }

        return results
    }

    /// Quick check: returns true if any surface needs quit confirmation.
    static func needsConfirmation(
        in collections: [WorkspaceCollection]
    ) -> Bool {
        !detectRunningProcesses(in: collections).isEmpty
    }

    // MARK: - Scoped Checks

    /// Check a single surface for a running foreground process.
    static func needsConfirmation(surface: GhosttyTerminalSurface) -> Bool {
        guard let s = surface.surface else { return false }
        return ghostty_surface_needs_confirm_quit(s)
    }

    /// Count running processes across a single pane's surfaces.
    static func runningProcessCount(in pane: PaneViewModel) -> Int {
        pane.surfaces.values.filter { needsConfirmation(surface: $0) }.count
    }

    /// Count running processes across multiple panes.
    static func runningProcessCount(in panes: [PaneViewModel]) -> Int {
        panes.reduce(0) { $0 + runningProcessCount(in: $1) }
    }
}
