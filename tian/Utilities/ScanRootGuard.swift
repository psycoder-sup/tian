import Foundation

/// Refuses roots that are too broad to recursively scan or watch.
///
/// Background: the Inspect panel used to put a recursive FSEventStream on a
/// session's working directory and rescan the whole tree on every event. A
/// session rooted at `$HOME` never goes quiet within the watcher's debounce
/// window — Claude Code alone rewrites `~/.claude/projects/*.jsonl`
/// continuously — so refreshes fired roughly once a second, each kicking off
/// a full recursive walk of home. The walks piled up faster than they could
/// finish: 600% CPU, 5.4 GB RSS in five minutes, app hang.
///
/// `ScanRootGuard` is the single place that decides a root is "too broad."
/// Both the scanner/view-model layer and `WorkingTreeWatcher` consult it
/// (defense in depth) so a future caller can't reintroduce the runaway by
/// forgetting to check in one of the two places.
enum ScanRootGuard {

    /// True for roots we refuse to recursively scan or watch: the user's
    /// home directory itself, `/`, `/Users`, `/Volumes` (and volume roots
    /// `/Volumes/<name>`), and `/System/Volumes/Data` (the APFS data volume
    /// mounted over `/` — same physical tree, different path). False for
    /// ordinary project directories, including subdirectories of home — only
    /// the container directory *itself* is refused, not everything under it.
    static func isTooBroad(_ url: URL) -> Bool {
        let candidate = standardizedPath(url)

        let refusedPaths: [String] = [
            standardizedPath(FileManager.default.homeDirectoryForCurrentUser),
            standardizedPath(URL(filePath: NSHomeDirectory())),
            "/",
            "/Users",
            "/Volumes",
            "/System/Volumes/Data",
        ]
        if refusedPaths.contains(candidate) {
            return true
        }

        // Volume roots: /Volumes/<name> itself, but not subdirectories under it.
        if isVolumeRoot(candidate) {
            return true
        }

        return false
    }

    /// Resolves symlinks and standardizes the path so `/Users/x`,
    /// `/Users/x/`, and a symlinked `/private/...` form all compare equal.
    private static func standardizedPath(_ url: URL) -> String {
        var path = url.resolvingSymlinksInPath().standardizedFileURL.path
        // Root ("/") is its own standardized form; only strip a trailing
        // slash from non-root paths so "/" doesn't become "".
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    private static func isVolumeRoot(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return components.count == 2 && components[0] == "Volumes"
    }
}
