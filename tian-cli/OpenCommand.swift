import ArgumentParser
import Foundation

/// `tian open` — launch the tian app, or bring it to the front if already
/// running. Unlike the other subcommands this does not require `TIAN_SOCKET`:
/// it works from any shell, including when the app is not running yet.
struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Launch the tian app (or focus it if already running)."
    )

    func run() throws {
        let args: [String]
        if let appPath = Self.enclosingAppBundlePath() {
            // Open the exact bundle this CLI was shipped inside, so a dev build
            // focuses the dev app rather than whatever Launch Services prefers.
            args = [appPath]
        } else {
            // Standalone/dev run outside an .app — fall back to the bundle id.
            args = ["-b", "com.tian.app"]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = args
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw CLIError.general("Could not open the tian app (open exited \(process.terminationStatus)).")
        }
    }

    /// Walks up from this executable to the enclosing `.app` bundle, if any.
    /// The CLI ships at `<app>.app/Contents/Resources/tian`, so the bundle is
    /// three directories up. Returns nil when not running from inside a bundle.
    private static func enclosingAppBundlePath() -> String? {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            return nil
        }
        var dir = exe.deletingLastPathComponent()
        // Bound the walk; the bundle is at most a few levels up.
        for _ in 0..<5 {
            if dir.pathExtension == "app" {
                return dir.path
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }   // reached filesystem root
            dir = parent
        }
        return nil
    }
}
