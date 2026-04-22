import Foundation

/// In-memory cache for `gh pr view` results with 60-second TTL.
@MainActor @Observable
final class PRStatusCache {

    /// Result of a cache lookup.
    enum CacheResult: Equatable {
        case miss
        case hit(PRStatus?)

        static func == (lhs: CacheResult, rhs: CacheResult) -> Bool {
            switch (lhs, rhs) {
            case (.miss, .miss): return true
            case (.hit(let a), .hit(let b)):
                switch (a, b) {
                case (nil, nil): return true
                case (let x?, let y?): return x.state == y.state && x.url == y.url
                default: return false
                }
            default: return false
            }
        }
    }

    private struct CacheKey: Hashable {
        let repoPath: String
        let branch: String
    }

    private struct CacheEntry {
        let prStatus: PRStatus?
        let fetchedAt: Date
    }

    private let ttl: TimeInterval = 60
    private let now: @Sendable () -> Date
    private var entries: [CacheKey: CacheEntry] = [:]

    /// In-flight fetch markers keyed by (repo, branch). The value is the
    /// eviction generation captured when the marker was inserted, so a late
    /// `clearPending`/`set` from a pre-evict fetch can be distinguished from
    /// the marker of a fresh post-evict fetch and not trample it.
    private var pending: [CacheKey: Int] = [:]

    /// Per-repo eviction generation. Bumped by `evict`/`evictAll` so that
    /// in-flight fetches started before the eviction can be detected and
    /// discarded on `set`.
    private var generations: [String: Int] = [:]

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func get(repoID: GitRepoID, branch: String) -> CacheResult {
        let key = CacheKey(repoPath: repoID.path, branch: branch)
        guard let entry = entries[key] else { return .miss }
        if now().timeIntervalSince(entry.fetchedAt) > ttl { return .miss }
        return .hit(entry.prStatus)
    }

    /// Records a fetched PR status. `generation` is the snapshot returned by
    /// `markPending` when the fetch was initiated; if an `evict` has bumped
    /// the repo's generation since, the result is stale and the write is
    /// dropped *without* clearing `pending` (the marker may belong to a
    /// newer fetch). Callers that set directly (tests, eager seeding) can
    /// omit `generation` and clear pending unconditionally.
    func set(repoID: GitRepoID, branch: String, status: PRStatus?, generation: Int? = nil) {
        let key = CacheKey(repoPath: repoID.path, branch: branch)
        if let expected = generation {
            guard generations[repoID.path, default: 0] == expected else { return }
            if pending[key] == expected {
                pending.removeValue(forKey: key)
            }
        } else {
            pending.removeValue(forKey: key)
        }
        entries[key] = CacheEntry(prStatus: status, fetchedAt: now())
    }

    /// Marks a branch as having an in-flight fetch. Returns the repo's
    /// current eviction generation when newly pending, or `nil` if another
    /// fetch is already in flight for this key (caller should skip).
    /// The returned generation should be passed back to `set` and
    /// `clearPending` when the fetch completes so stale results can be
    /// discarded and marker clearing doesn't trample a post-evict fetch.
    func markPending(repoID: GitRepoID, branch: String) -> Int? {
        let key = CacheKey(repoPath: repoID.path, branch: branch)
        if pending[key] != nil { return nil }
        let gen = generations[repoID.path, default: 0]
        // Ensure the repo's generation entry exists so `evictAll`, which
        // bumps each key in `generations`, catches repos that have had a
        // pending fetch but no `set` yet.
        generations[repoID.path] = gen
        pending[key] = gen
        return gen
    }

    /// Clears the pending marker for a fetch, but only if it still belongs
    /// to the caller's `generation`. If an `evict` has since bumped the
    /// generation and a fresh fetch installed a new marker, that newer
    /// marker is left in place.
    func clearPending(repoID: GitRepoID, branch: String, generation: Int) {
        let key = CacheKey(repoPath: repoID.path, branch: branch)
        if pending[key] == generation {
            pending.removeValue(forKey: key)
        }
    }

    /// Removes all cached entries for `repoID` across every branch and
    /// invalidates any in-flight fetches for the repo: the generation is
    /// bumped (so their `set` writes are discarded and their `clearPending`
    /// is a no-op) and pending is cleared so the next refresh can
    /// immediately start a fresh fetch.
    func evict(repoID: GitRepoID) {
        entries = entries.filter { $0.key.repoPath != repoID.path }
        pending = pending.filter { $0.key.repoPath != repoID.path }
        generations[repoID.path, default: 0] += 1
    }

    func evictAll() {
        entries.removeAll()
        pending.removeAll()
        for path in Array(generations.keys) {
            generations[path, default: 0] += 1
        }
    }
}
