import Foundation

/// Lock-protected bounded byte buffer for incremental pipe drain.
/// Concurrent reads across both stdout and stderr handlers go through
/// independent instances; the lock guards in-instance state.
final class LimitedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var truncated = false
    private let cap: Int

    init(cap: Int) { self.cap = cap }

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        if truncated { return }
        let space = cap - data.count
        let take = min(chunk.count, space)
        data.append(chunk.prefix(take))
        if take < chunk.count || take == space {
            truncated = true
        }
    }

    func snapshot() -> (Data, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, truncated)
    }
}
