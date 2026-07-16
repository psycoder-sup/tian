import Foundation

/// In-memory cache of git-repo detection results keyed by directory path.
///
/// Caches both positive (`RepoLocation`) and negative (not-a-repo, `nil`)
/// results with separate TTLs: negatives expire quickly (30s) so a directory
/// that later becomes a repo is picked up soon, while positives are stable
/// and kept much longer (300s / 5 minutes). This lets callers avoid
/// re-shelling `git rev-parse` on every OSC 7 cwd change.
@MainActor
final class DetectionCache {

    /// Result of a cache lookup.
    enum CacheResult: Equatable {
        case miss
        case hit(RepoLocation?)
    }

    private struct CacheEntry {
        let location: RepoLocation?
        let fetchedAt: Date
    }

    private let positiveTTL: TimeInterval = 300
    private let negativeTTL: TimeInterval = 30
    private let now: @Sendable () -> Date
    private var entries: [String: CacheEntry] = [:]

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// Looks up a cached detection result for `directory`. Returns `.miss`
    /// when there is no entry or the entry has expired (using the positive
    /// or negative TTL depending on whether the cached location is nil).
    func get(directory: String) -> CacheResult {
        guard let entry = entries[directory] else { return .miss }
        let ttl = entry.location == nil ? negativeTTL : positiveTTL
        if now().timeIntervalSince(entry.fetchedAt) > ttl { return .miss }
        return .hit(entry.location)
    }

    /// Records a detection result for `directory`. `location == nil` caches
    /// a negative (not-a-repo) result, subject to the shorter negative TTL.
    func set(directory: String, location: RepoLocation?) {
        entries[directory] = CacheEntry(location: location, fetchedAt: now())
    }

    /// Removes the cached entry for `directory`, if any.
    func invalidate(directory: String) {
        entries.removeValue(forKey: directory)
    }

    /// Removes every cached entry.
    func invalidateAll() {
        entries.removeAll()
    }
}
