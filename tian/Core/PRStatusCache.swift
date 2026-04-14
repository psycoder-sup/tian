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
    private var pending: Set<CacheKey> = []

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func get(repoID: GitRepoID, branch: String) -> CacheResult {
        let key = CacheKey(repoPath: repoID.path, branch: branch)
        guard let entry = entries[key] else { return .miss }
        if now().timeIntervalSince(entry.fetchedAt) > ttl { return .miss }
        return .hit(entry.prStatus)
    }

    func set(repoID: GitRepoID, branch: String, status: PRStatus?) {
        let key = CacheKey(repoPath: repoID.path, branch: branch)
        entries[key] = CacheEntry(prStatus: status, fetchedAt: now())
        pending.remove(key)
    }

    func markPending(repoID: GitRepoID, branch: String) -> Bool {
        let key = CacheKey(repoPath: repoID.path, branch: branch)
        if pending.contains(key) { return false }
        pending.insert(key)
        return true
    }

    func clearPending(repoID: GitRepoID, branch: String) {
        pending.remove(CacheKey(repoPath: repoID.path, branch: branch))
    }

    func evictAll() {
        entries.removeAll()
        pending.removeAll()
    }
}
