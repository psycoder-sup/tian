import Foundation

/// A `@MainActor` interval timer. Fires `action` every `interval` until
/// `stop()` (or deinit). Used where FSEvents can't watch the tree because it
/// lives on another host — remote git-context and file-tree refresh poll
/// instead of reacting to filesystem events.
///
/// The first fire happens one `interval` after `start()`; callers do their
/// initial load through the existing eager-refresh path, and the poller only
/// drives subsequent refreshes.
@MainActor
final class PollingRefresher {
    private let interval: Duration
    private let action: @MainActor () -> Void
    private var task: Task<Void, Never>?

    init(interval: Duration, action: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.action = action
    }

    /// Begins polling. Idempotent — a second call while already running is a
    /// no-op.
    func start() {
        guard task == nil else { return }
        task = Task { [interval, action] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                action()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
