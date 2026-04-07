import Foundation

/// Information about a surface with a running foreground process.
struct RunningProcessInfo: Sendable {
    let workspaceName: String
    let spaceName: String
    let tabName: String
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
                for space in workspace.spaceCollection.spaces {
                    for tab in space.tabs {
                        for (paneID, terminalSurface) in tab.paneViewModel.surfaces {
                            guard let surface = terminalSurface.surface,
                                  ghostty_surface_needs_confirm_quit(surface) else { continue }
                            results.append(RunningProcessInfo(
                                workspaceName: workspace.name,
                                spaceName: space.name,
                                tabName: tab.displayName,
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

    /// Count running processes across a single tab's panes.
    static func runningProcessCount(in tab: TabModel) -> Int {
        tab.paneViewModel.surfaces.values.filter { needsConfirmation(surface: $0) }.count
    }

    /// Count running processes across multiple tabs.
    static func runningProcessCount(in tabs: [TabModel]) -> Int {
        tabs.reduce(0) { $0 + runningProcessCount(in: $1) }
    }
}
