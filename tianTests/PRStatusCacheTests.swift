import Foundation
import Testing
@testable import tian

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

        let pr = PRStatus(number: 1, state: .open, url: URL(string: "https://github.com/test/pr/1")!)
        cache.set(repoID: GitRepoID(path: "/repo"), branch: "main", status: pr)

        currentTime = Date(timeIntervalSince1970: 1059)
        let result = cache.get(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(result == .hit(pr))
    }

    @Test func getAfterTTLExpiryReturnsMiss() {
        nonisolated(unsafe) var currentTime = Date(timeIntervalSince1970: 1000)
        let cache = PRStatusCache(now: { currentTime })

        let pr = PRStatus(number: 1, state: .open, url: URL(string: "https://github.com/test/pr/1")!)
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

    @Test func markPendingReturnsGenerationOnFirstCall() {
        let cache = PRStatusCache()
        let first = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(first == 0)
    }

    @Test func markPendingReturnsNilWhenAlreadyPending() {
        let cache = PRStatusCache()
        _ = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        let second = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(second == nil)
    }

    @Test func setRemovesFromPending() {
        let cache = PRStatusCache()
        _ = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        cache.set(repoID: GitRepoID(path: "/repo"), branch: "main", status: nil)

        let again = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(again != nil)
    }

    @Test func clearPendingAllowsRetry() {
        let cache = PRStatusCache()
        guard let gen = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main") else {
            Issue.record("markPending should return a generation on first call")
            return
        }
        cache.clearPending(repoID: GitRepoID(path: "/repo"), branch: "main", generation: gen)

        let again = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(again != nil)
    }

    @Test func clearPendingWithStaleGenerationLeavesNewerMarkerIntact() {
        // A late `clearPending` from a pre-evict fetch must not trample the
        // marker a post-evict fetch just installed — otherwise `markPending`
        // would stop deduping, allowing a duplicate `gh pr view` subprocess.
        let cache = PRStatusCache()
        let repoID = GitRepoID(path: "/repo")

        guard let oldGen = cache.markPending(repoID: repoID, branch: "main") else {
            Issue.record("first markPending should return a generation")
            return
        }
        cache.evict(repoID: repoID)
        guard let newGen = cache.markPending(repoID: repoID, branch: "main") else {
            Issue.record("post-evict markPending should return a generation")
            return
        }
        #expect(oldGen != newGen)

        // Late clear from the old fetch — should be a no-op.
        cache.clearPending(repoID: repoID, branch: "main", generation: oldGen)

        // The new fetch's marker is still in place, so a concurrent refresh
        // is still deduplicated.
        let duplicate = cache.markPending(repoID: repoID, branch: "main")
        #expect(duplicate == nil)
    }

    @Test func setWithStaleGenerationLeavesNewerPendingMarkerIntact() {
        // When a pre-evict fetch's `set` call arrives late it must drop both
        // the write AND the pending-clear, so a fresh fetch's marker
        // survives.
        let cache = PRStatusCache()
        let repoID = GitRepoID(path: "/repo")
        let pr = PRStatus(number: 1, state: .open, url: URL(string: "https://github.com/test/pr/1")!)

        guard let oldGen = cache.markPending(repoID: repoID, branch: "main") else {
            Issue.record("first markPending should return a generation")
            return
        }
        cache.evict(repoID: repoID)
        _ = cache.markPending(repoID: repoID, branch: "main")

        // Late write from the pre-evict fetch.
        cache.set(repoID: repoID, branch: "main", status: pr, generation: oldGen)

        let duplicate = cache.markPending(repoID: repoID, branch: "main")
        #expect(duplicate == nil)
    }

    @Test func evictByRepoRemovesAllBranchesForThatRepo() {
        let cache = PRStatusCache()
        let pr1 = PRStatus(number: 1, state: .open, url: URL(string: "https://github.com/test/pr/1")!)
        let pr2 = PRStatus(number: 2, state: .open, url: URL(string: "https://github.com/test/pr/2")!)
        cache.set(repoID: GitRepoID(path: "/repo-a"), branch: "main", status: pr1)
        cache.set(repoID: GitRepoID(path: "/repo-a"), branch: "feature", status: pr1)
        cache.set(repoID: GitRepoID(path: "/repo-b"), branch: "main", status: pr2)

        cache.evict(repoID: GitRepoID(path: "/repo-a"))

        #expect(cache.get(repoID: GitRepoID(path: "/repo-a"), branch: "main") == .miss)
        #expect(cache.get(repoID: GitRepoID(path: "/repo-a"), branch: "feature") == .miss)
        // Other repos are untouched.
        #expect(cache.get(repoID: GitRepoID(path: "/repo-b"), branch: "main") == .hit(pr2))
    }

    @Test func evictByRepoClearsPendingMarkers() {
        // evict clears pending so the next refresh can start a fresh fetch
        // immediately after the remote-refs event that triggered the evict.
        // The pre-evict fetch's result is discarded via the generation check.
        let cache = PRStatusCache()
        _ = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")

        cache.evict(repoID: GitRepoID(path: "/repo"))

        let again = cache.markPending(repoID: GitRepoID(path: "/repo"), branch: "main")
        #expect(again != nil)
    }

    @Test func evictDiscardsStaleInFlightFetchWrite() {
        // A fetch started before a `git push`-driven evict reports pre-push
        // state. Without a generation check its `set` would write that stale
        // state with a fresh `fetchedAt`, masking the correct post-evict
        // state for up to 60 s.
        let cache = PRStatusCache()
        let repoID = GitRepoID(path: "/repo")
        let pr = PRStatus(number: 1, state: .open, url: URL(string: "https://github.com/test/pr/1")!)

        guard let fetchGen = cache.markPending(repoID: repoID, branch: "main") else {
            Issue.record("markPending should return a generation on first call")
            return
        }
        cache.evict(repoID: repoID)
        cache.set(repoID: repoID, branch: "main", status: pr, generation: fetchGen)

        #expect(cache.get(repoID: repoID, branch: "main") == .miss)
    }

    @Test func setWithMatchingGenerationWrites() {
        let cache = PRStatusCache()
        let repoID = GitRepoID(path: "/repo")
        let pr = PRStatus(number: 1, state: .open, url: URL(string: "https://github.com/test/pr/1")!)

        guard let fetchGen = cache.markPending(repoID: repoID, branch: "main") else {
            Issue.record("markPending should return a generation on first call")
            return
        }
        cache.set(repoID: repoID, branch: "main", status: pr, generation: fetchGen)

        #expect(cache.get(repoID: repoID, branch: "main") == .hit(pr))
    }

    @Test func evictAllClearsEverything() {
        let cache = PRStatusCache()
        let pr = PRStatus(number: 2, state: .merged, url: URL(string: "https://github.com/test/pr/2")!)
        cache.set(repoID: GitRepoID(path: "/repo"), branch: "main", status: pr)
        _ = cache.markPending(repoID: GitRepoID(path: "/repo2"), branch: "dev")

        cache.evictAll()

        #expect(cache.get(repoID: GitRepoID(path: "/repo"), branch: "main") == .miss)
        let canMark = cache.markPending(repoID: GitRepoID(path: "/repo2"), branch: "dev")
        #expect(canMark != nil)
    }

    @Test func evictAllDiscardsStaleInFlightFetchWrite() {
        // Teardown-time evictAll must also invalidate in-flight fetches so a
        // late set() can't repopulate the cache after shutdown cleanup.
        let cache = PRStatusCache()
        let repoID = GitRepoID(path: "/repo")
        let pr = PRStatus(number: 3, state: .open, url: URL(string: "https://github.com/test/pr/3")!)

        guard let fetchGen = cache.markPending(repoID: repoID, branch: "main") else {
            Issue.record("markPending should return a generation on first call")
            return
        }
        cache.evictAll()
        cache.set(repoID: repoID, branch: "main", status: pr, generation: fetchGen)

        #expect(cache.get(repoID: repoID, branch: "main") == .miss)
    }
}
