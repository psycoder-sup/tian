import Foundation

/// Trailing-edge debouncer that coalesces rapid submissions per key.
/// Only the most recent `value` for a key within `interval` is delivered.
///
/// Used to smooth NotificationCenter posts driven by VT escape sequences
/// (title, pwd, bell) which arrive faster than the UI cares about.
@MainActor
final class EventCoalescer<Key: Hashable, Value> {
    typealias Handler = (Key, Value) -> Void

    private struct Entry {
        var value: Value
        var task: Task<Void, Never>
    }

    private let interval: Duration
    private let handler: Handler
    private var pending: [Key: Entry] = [:]

    init(interval: Duration, handler: @escaping Handler) {
        self.interval = interval
        self.handler = handler
    }

    /// Schedule `value` for delivery. Replaces any pending value for the same key.
    func submit(key: Key, value: Value) {
        pending[key]?.task.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.interval)
            guard !Task.isCancelled else { return }
            guard let entry = self.pending.removeValue(forKey: key) else { return }
            self.handler(key, entry.value)
        }
        pending[key] = Entry(value: value, task: task)
    }

    /// Cancel any pending delivery for `key` (e.g., on pane close).
    func cancel(key: Key) {
        pending.removeValue(forKey: key)?.task.cancel()
    }
}
