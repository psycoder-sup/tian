import Foundation
import CoreServices
import OSLog

/// Watches a single working-tree root for filesystem changes via FSEventStream
/// and fires a trailing-debounced `onChange` callback. Used by the Inspect panel
/// to refresh the tree when files are touched outside git operations (e.g. a
/// fresh dotfile in a non-repo dir, or rapid edits during a Vite rebuild).
///
/// Trailing debounce coalesces event storms into a single callback per quiet
/// window (default 250 ms) — necessary because dev servers can emit 100+ events
/// per second.
///
/// Thread safety: All mutable state is guarded by `queue`. The FSEventStream
/// callback fires on `queue`, debounce work runs on `queue`, and `stop()`
/// dispatches synchronously to `queue` to prevent races between teardown and
/// in-flight debounce ticks.
final class WorkingTreeWatcher: @unchecked Sendable {

    let root: String
    private let debounce: Duration
    private let onChange: @Sendable () -> Void
    private let queue: DispatchQueue
    private var streamRef: FSEventStreamRef?     // guarded by queue
    private var pendingTimer: DispatchSourceTimer?  // guarded by queue
    private var isStopped: Bool = false           // guarded by queue

    /// Reference-counted box holding our `Self` pointer. The FSEventStream
    /// retains/releases via context callbacks, so the watcher cannot be
    /// freed while the stream is still firing events.
    private final class Box: @unchecked Sendable {
        weak var watcher: WorkingTreeWatcher?
        init(_ watcher: WorkingTreeWatcher) { self.watcher = watcher }
    }

    init(root: String,
         debounce: Duration = .milliseconds(250),
         onChange: @escaping @Sendable () -> Void) {
        self.root = root
        self.debounce = debounce
        self.onChange = onChange
        self.queue = DispatchQueue(label: "com.tian.working-tree-watcher", qos: .utility)
        startStream()
    }

    deinit {
        queue.sync { stopOnQueue() }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    /// Must be called on `queue`.
    private func stopOnQueue() {
        guard !isStopped else { return }
        isStopped = true
        if let timer = pendingTimer {
            timer.cancel()
            pendingTimer = nil
        }
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
        Log.git.debug("WorkingTreeWatcher stopped for: \(self.root)")
    }

    private func startStream() {
        let pathsToWatch = [root] as CFArray
        let box = Box(self)
        let raw = Unmanaged.passRetained(box).toOpaque()

        var context = FSEventStreamContext(
            version: 0,
            info: raw,
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Box>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Box>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let streamCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            box.watcher?.scheduleDebouncedFire()
        }

        // 0.1s native FSEvents latency — debounce coalesces beyond that.
        guard let stream = FSEventStreamCreate(
            nil,
            streamCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else {
            Unmanaged<Box>.fromOpaque(raw).release()
            Log.git.error("Failed to create FSEventStream for: \(self.root)")
            return
        }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        Log.git.debug("WorkingTreeWatcher started for: \(self.root)")
    }

    /// Schedules (or rearms) the trailing-debounce timer. Each FSEvents batch
    /// resets the timer; the callback fires once per quiet window.
    /// Called from the FSEvents callback, which runs on `queue`.
    private func scheduleDebouncedFire() {
        // Already on queue (FSEventStreamSetDispatchQueue). Safe to touch state.
        guard !isStopped else { return }

        if let existing = pendingTimer {
            existing.cancel()
            pendingTimer = nil
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        let nanos = nanosecondsFromDuration(debounce)
        timer.schedule(deadline: .now() + .nanoseconds(nanos))

        let onChange = self.onChange
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // Re-check stopped on the queue before firing — `stop()` may have
            // landed between the timer scheduling and its handler running.
            guard !self.isStopped else { return }
            self.pendingTimer = nil
            onChange()
        }
        pendingTimer = timer
        timer.resume()
    }

    /// `Duration.components` returns `(seconds, attoseconds)` — convert to
    /// nanoseconds. Clamps to non-negative.
    private func nanosecondsFromDuration(_ duration: Duration) -> Int {
        let parts = duration.components
        let secondsNanos = Int(parts.seconds) * 1_000_000_000
        let attosNanos = Int(parts.attoseconds / 1_000_000_000)
        return max(0, secondsNanos + attosNanos)
    }
}
