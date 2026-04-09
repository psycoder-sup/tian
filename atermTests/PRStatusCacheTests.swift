import Foundation
import Testing
@testable import aterm

@MainActor
struct PRStatusCacheTests {

    @Test func getMissingEntryReturnsMiss() {
        let cache = PRStatusCache()
        let result = cache.get(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(result == .miss)
    }

    @Test func setThenGetWithinTTLReturnsCachedValue() {
        nonisolated(unsafe) var currentTime = Date(timeIntervalSince1970: 1000)
        let cache = PRStatusCache(now: { currentTime })

        let pr = PRStatus(state: .open, url: URL(string: "https://github.com/test/pr/1")!)
        cache.set(repoID: GitRepoID(path: "/repo"), branch: "main", status: pr)

        currentTime = Date(timeIntervalSince1970: 1059)
        let result = cache.get(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(result == .hit(pr))
    }

    @Test func getAfterTTLExpiryReturnsMiss() {
        nonisolated(unsafe) var currentTime = Date(timeIntervalSince1970: 1000)
        let cache = PRStatusCache(now: { currentTime })

        let pr = PRStatus(state: .open, url: URL(string: "https://github.com/test/pr/1")!)
        cache.set(repoID: GitRepoID(path: "/repo"), branch: "main", status: pr)

        currentTime = Date(timeIntervalSince1970: 1061)
        let result = cache.get(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(result == .miss)
    }

    @Test func setNilPRStatusCachesAsNoPR() {
        let cache = PRStatusCache()
        cache.set(repoID: GitRepoID(path: "/repo"), branch: "main", status: nil)

        let result = cache.get(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(result == .hit(nil))
    }

    @Test func markPendingReturnsTrueFirstCall() {
        let cache = PRStatusCache()
        let first = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(first == true)
    }

    @Test func markPendingReturnsFalseSecondCall() {
        let cache = PRStatusCache()
        _ = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        let second = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(second == false)
    }

    @Test func setRemovesFromPending() {
        let cache = PRStatusCache()
        _ = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        cache.set(repoID: GitRepoID(path: "/repo"), branch: "main", status: nil)

        let again = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(again == true)
    }

    @Test func clearPendingAllowsRetry() {
        let cache = PRStatusCache()
        _ = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        cache.clearPending(repoID: GitRepoID(path: "/repo"), branch: "main")

        let again = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(again == true)
    }

    @Test func evictAllClearsEverything() {
        let cache = PRStatusCache()
        let pr = PRStatus(state: .merged, url: URL(string: "https://github.com/test/pr/2")!)
        cache.set(repoID: GitRepoID(path: "/repo"), branch: "main", status: pr)
        _ = cache.markPending(repoID: GitRepoID(path: "/repo2"), branch: "dev")

        cache.evictAll()

        #expect(cache.get(repoID: GitRepoID(path: "/repo"), branch: "main") == .miss)
        let canMark = cache.markPending(repoID: GitRepoID(path: "/repo2"), branch: "dev")
        #expect(canMark == true)
    }
}
