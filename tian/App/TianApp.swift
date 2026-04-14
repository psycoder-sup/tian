import SwiftUI

@main
struct TianApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: TianAppDelegate

    init() {
        // Set GHOSTTY_RESOURCES_DIR so ghostty can find bundled themes and shell-integration.
        // Use overwrite=1 to always prefer the bundled resources over any inherited env value.
        if let resourcesPath = Bundle.main.resourceURL?.appendingPathComponent("ghostty").path {
            setenv("GHOSTTY_RESOURCES_DIR", resourcesPath, 1)
        }

        // Initialize the ghostty singleton (triggers ghostty_init + app creation)
        _ = GhosttyApp.shared
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            WorkspaceCommands(windowCoordinator: appDelegate.windowCoordinator)
        }
    }
}
