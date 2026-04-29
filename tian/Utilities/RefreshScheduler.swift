import Foundation

/// Trailing-edge per-key debouncer with a global concurrency cap.
///
/// Routes storm-prone refresh triggers (FSEvents, OSC 7 directory churn)
/// through a per-key debounce window so multiple bursts within `debounce`
/// coalesce to a single delivery, then dispatches through an async semaphore
/// so at most `maxConcurrent` handlers run in parallel even when many keys
/// fire simultaneously.
///
/// Example: during an active dev server with N pinned git repos, FSEvents
/// fires per repo every ~2s. Without a cap, N concurrent `git status`/`gh`
/// pipelines saturate the host. With this scheduler, at most 2 pipelines
/// run in parallel and same-repo bursts collapse to one refresh.
@MainActor
final class RefreshScheduler<Key: Hashable & Sendable> {
    typealias Handler = @Sendable (Key) async -> Void

    private let debounce: Duration
    private let handler: Handler
    private let semaphore: AsyncSemaphore

    private var pending: [Key: Task<Void, Never>] = [:]

    init(debounce: Duration, maxConcurrent: Int, handler: @escaping Handler) {
        self.debounce = debounce
        self.handler = handler
        self.semaphore = AsyncSemaphore(limit: maxConcurrent)
    }

    /// Schedule a refresh for `key`. Cancels any prior pending task for the
    /// same key — only the trailing call within the debounce window fires.
    func schedule(key: Key) {
        pending[key]?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounce)
            guard !Task.isCancelled else { return }
            self.pending.removeValue(forKey: key)
            // `handler` is non-throwing (`async -> Void`), so a single
            // sequential acquire/release pair around it is sufficient —
            // no need to wrap in defer with an unstructured release Task.
            await self.semaphore.acquire()
            await self.handler(key)
            await self.semaphore.release()
        }
        pending[key] = task
    }

    /// Cancel any pending refresh for `key` (e.g., on repo unpin).
    func cancel(key: Key) {
        pending.removeValue(forKey: key)?.cancel()
    }

    /// Cancel every pending refresh. Called on Space teardown.
    func cancelAll() {
        for task in pending.values { task.cancel() }
        pending.removeAll()
    }
}

/// Counting semaphore for async/await. FIFO wait queue.
actor AsyncSemaphore {
    private let limit: Int
    private var inFlight: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        precondition(limit > 0)
        self.limit = limit
    }

    func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            // Hand the slot directly to the next waiter — `inFlight` stays
            // at `limit` since we neither decrement here nor increment in
            // `acquire`'s queued path.
            next.resume()
        } else {
            inFlight = max(0, inFlight - 1)
        }
    }
}
