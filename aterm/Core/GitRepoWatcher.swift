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
        let handler: @Sendable () -> Void
        init(_ handler: @Sendable @escaping () -> Void) { self.handler = handler }
    }

    var isRunning: Bool {
        queue.sync { _isRunning }
    }

    /// Creates and starts an FSEventStream for the given paths.
    init(watchPaths: [String], latency: CFTimeInterval = 2.0, onChangeDetected: @Sendable @escaping () -> Void) {
        self.watchPaths = watchPaths
        self.queue = DispatchQueue(label: "com.aterm.git-watcher", qos: .utility)
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

    /// Determines which paths to monitor based on git dir type.
    static func resolveWatchPaths(
        gitDir: String,
        commonDir: String,
        workingDirectory: String
    ) -> [String] {
        if gitDir.contains("/worktrees/") {
            let refsPath = (commonDir as NSString).appendingPathComponent("refs")
            return [gitDir, refsPath]
        } else if gitDir == ".git" {
            return [(workingDirectory as NSString).appendingPathComponent(".git")]
        } else if gitDir.hasSuffix("/.git") || gitDir.hasSuffix("/.git/") {
            return [gitDir]
        } else {
            return [gitDir]
        }
    }

    private func startStream(latency: CFTimeInterval, callback: @Sendable @escaping () -> Void) {
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

        let streamCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            box.handler()
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
