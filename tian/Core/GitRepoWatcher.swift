import Foundation
import CoreServices
import OSLog

/// Watches git repository directories for changes via FSEventStream.
/// Fires a debounced callback when filesystem changes are detected in watched paths.
///
/// Thread safety: All mutable state is protected by `queue`. The FSEventStream callback
/// fires on `queue`, and `stop()` dispatches synchronously to `queue` to avoid races.
final class GitRepoWatcher: @unchecked Sendable {

    let watchPaths: [String]
    private var streamRef: FSEventStreamRef?  // guarded by queue
    private var _isRunning = false             // guarded by queue
    private let queue: DispatchQueue

    /// Reference-counted box holding the callback, preventing use-after-free
    /// in FSEventStream context. The stream retains/releases it via context callbacks.
    private final class CallbackBox: @unchecked Sendable {
        let handler: @Sendable ([String]) -> Void
        init(_ handler: @Sendable @escaping ([String]) -> Void) { self.handler = handler }
    }

    var isRunning: Bool {
        queue.sync { _isRunning }
    }

    /// Creates and starts an FSEventStream for the given paths. The callback
    /// receives the absolute paths reported by FSEvents for the current batch;
    /// callers can inspect them to decide whether a refs-affecting change
    /// (push, fetch, branch delete) warrants PR-cache invalidation.
    init(watchPaths: [String], latency: CFTimeInterval = 2.0, onChangeDetected: @Sendable @escaping ([String]) -> Void) {
        self.watchPaths = watchPaths
        self.queue = DispatchQueue(label: "com.tian.git-watcher", qos: .utility)
        startStream(latency: latency, callback: onChangeDetected)
    }

    deinit {
        queue.sync { stopOnQueue() }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    /// Must be called on `queue`.
    private func stopOnQueue() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
        _isRunning = false
        Log.git.debug("GitRepoWatcher stopped for: \(self.watchPaths)")
    }

    /// Determines which paths to monitor for a given repo location.
    ///
    /// The working tree is always included so that edits to tracked/untracked
    /// files propagate to the badge without requiring an OSC 7 or git-metadata
    /// event. FSEventStream is recursive, so for a regular repo `workingTree`
    /// alone covers `.git/` as well. Worktrees additionally need their own
    /// `gitDir` (under the main `.git/worktrees/NAME`) and the shared
    /// `commonDir/refs`, since those live outside the worktree root.
    static func resolveWatchPaths(for location: RepoLocation) -> [String] {
        guard location.isWorktree else { return [location.workingTree] }
        let refsPath = (location.commonDir as NSString).appendingPathComponent("refs")
        return [location.workingTree, location.gitDir, refsPath]
    }

    /// True if any event path indicates a remote-refs or packed-refs change —
    /// i.e. a `git push`, `git fetch`, or `gh pr merge --delete-branch` that
    /// likely invalidates a cached `gh pr view` result. Local branch tip moves
    /// (`refs/heads/*` on commit) and HEAD retargeting (branch switch) are
    /// deliberately excluded: commits don't change PR state on the remote, and
    /// branch switches produce a fresh cache key anyway.
    ///
    /// `canonicalCommonDir` must already be resolved via `canonicalizedPath`
    /// — FSEvents reports paths with macOS firmlinks resolved (e.g.
    /// `/private/var/folders/...`), while `commonDir` from `git rev-parse`
    /// keeps the unresolved `/var/folders/...` form. Canonicalizing once at
    /// watcher construction keeps `realpath(3)` off the FSEvents callback
    /// hot path.
    static func pathsAffectPRState(_ paths: [String], canonicalCommonDir: String) -> Bool {
        let remoteRefsPrefix = (canonicalCommonDir as NSString)
            .appendingPathComponent("refs/remotes") + "/"
        let packedRefs = (canonicalCommonDir as NSString)
            .appendingPathComponent("packed-refs")
        for path in paths {
            if path == packedRefs || path.hasPrefix(remoteRefsPrefix) {
                return true
            }
        }
        return false
    }

    /// Resolves symlinks and firmlinks via `realpath(3)`. Falls back to the
    /// input if the path can't be resolved (e.g. it was just deleted).
    /// Uses the heap-allocating form (`resolved_name = NULL`) so it doesn't
    /// depend on `PATH_MAX`. `URL.resolvingSymlinksInPath()` doesn't traverse
    /// the `/var` → `/private/var` firmlink on macOS, hence POSIX `realpath`.
    static func canonicalizedPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private func startStream(latency: CFTimeInterval, callback: @Sendable @escaping ([String]) -> Void) {
        let pathsToWatch = watchPaths as CFArray

        let box = CallbackBox(callback)
        let raw = Unmanaged.passRetained(box).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: raw,
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<CallbackBox>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<CallbackBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let streamCallback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()

            // With kFSEventStreamCreateFlagUseCFTypes, eventPaths is a CFArray
            // of CFStrings that bridges to [String].
            let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            let paths = (cfArray as? [String]) ?? []

            box.handler(paths)
        }

        guard let stream = FSEventStreamCreate(
            nil,
            streamCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            // Release the box since the stream won't manage it
            Unmanaged<CallbackBox>.fromOpaque(raw).release()
            Log.git.error("Failed to create FSEventStream for: \(self.watchPaths)")
            return
        }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        _isRunning = true
        Log.git.debug("GitRepoWatcher started for: \(self.watchPaths)")
    }
}
