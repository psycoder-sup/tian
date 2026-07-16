import Foundation
import Testing
@testable import tian

@MainActor
struct DetectionCacheTests {

    private func makeLocation(_ path: String = "/repo") -> RepoLocation {
        RepoLocation(
            gitDir: "\(path)/.git",
            commonDir: "\(path)/.git",
            workingTree: path,
            isWorktree: false
        )
    }

    @Test func getMissingEntryReturnsMiss() {
        let cache = DetectionCache()
        let result = cache.get(directory: "/repo")
        #expect(result == .miss)
    }

    @Test func setThenGetWithinPositiveTTLReturnsCachedValue() {
        nonisolated(unsafe) var currentTime = Date(timeIntervalSince1970: 1000)
        let cache = DetectionCache(now: { currentTime })
        let location = makeLocation()

        cache.set(directory: "/repo", location: location)

        currentTime = Date(timeIntervalSince1970: 1299)
        let result = cache.get(directory: "/repo")
        #expect(result == .hit(location))
    }

    @Test func positiveEntryExpiresAfter300Seconds() {
        nonisolated(unsafe) var currentTime = Date(timeIntervalSince1970: 1000)
        let cache = DetectionCache(now: { currentTime })
        let location = makeLocation()

        cache.set(directory: "/repo", location: location)

        currentTime = Date(timeIntervalSince1970: 1301)
        let result = cache.get(directory: "/repo")
        #expect(result == .miss)
    }

    @Test func setNilLocationCachesAsNegativeHitWithin30Seconds() {
        nonisolated(unsafe) var currentTime = Date(timeIntervalSince1970: 1000)
        let cache = DetectionCache(now: { currentTime })

        cache.set(directory: "/not-a-repo", location: nil)

        currentTime = Date(timeIntervalSince1970: 1029)
        let result = cache.get(directory: "/not-a-repo")
        #expect(result == .hit(nil))
    }

    @Test func negativeEntryExpiresAfter30Seconds() {
        nonisolated(unsafe) var currentTime = Date(timeIntervalSince1970: 1000)
        let cache = DetectionCache(now: { currentTime })

        cache.set(directory: "/not-a-repo", location: nil)

        currentTime = Date(timeIntervalSince1970: 1031)
        let result = cache.get(directory: "/not-a-repo")
        #expect(result == .miss)
    }

    @Test func invalidateRemovesSingleEntry() {
        let cache = DetectionCache()
        let location = makeLocation("/repo-a")
        cache.set(directory: "/repo-a", location: location)
        cache.set(directory: "/repo-b", location: nil)

        cache.invalidate(directory: "/repo-a")

        #expect(cache.get(directory: "/repo-a") == .miss)
        // Other entries are untouched.
        #expect(cache.get(directory: "/repo-b") == .hit(nil))
    }

    @Test func invalidateAllRemovesEveryEntry() {
        let cache = DetectionCache()
        cache.set(directory: "/repo-a", location: makeLocation("/repo-a"))
        cache.set(directory: "/repo-b", location: nil)

        cache.invalidateAll()

        #expect(cache.get(directory: "/repo-a") == .miss)
        #expect(cache.get(directory: "/repo-b") == .miss)
    }
}
