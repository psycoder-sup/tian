import Foundation
import Testing
@testable import tian

@MainActor
struct InspectBranchViewModelTests {

    // MARK: - FR-T20a / FR-T25: graph populates from injected service

    @Test func assemblesGraphFromService() async throws {
        let expected = Self.makeThreeLaneGraph()
        let vm = InspectBranchViewModel()
        vm.graphService = { _ in expected }

        vm.scheduleRefresh(directory: "/tmp/repo", repoID: nil, in: nil)

        try await pollUntil(timeout: .seconds(2)) { vm.lastDirectory == "/tmp/repo" }
        #expect(vm.graph == expected)
        #expect(vm.lastDirectory == "/tmp/repo")
        #expect(vm.isLoadingInitial == false)

        vm.teardown()
    }

    // MARK: - FR-T28: dirty-flag handshake

    @Test func dirtyFlagDrivesRefresh() async throws {
        let host = FakeBranchGraphHost()
        let repoID = GitRepoID(path: "/tmp/repo/.git")
        host.branchGraphDirty.insert(repoID)

        let expected = Self.makeThreeLaneGraph()
        let vm = InspectBranchViewModel()
        vm.graphService = { _ in expected }

        vm.scheduleRefresh(directory: "/tmp/repo", repoID: repoID, in: host)

        try await pollUntil(timeout: .seconds(2)) {
            vm.graph != nil && host.clearedRepos == [repoID]
        }

        #expect(vm.graph == expected)
        #expect(host.clearedRepos == [repoID])
        #expect(host.branchGraphDirty.contains(repoID) == false)

        vm.teardown()
    }

    // MARK: - teardown cancels in-flight task

    @Test func teardownCancelsInFlight() async throws {
        let fake = BlockingGraphService()
        let vm = InspectBranchViewModel()
        vm.graphService = { dir in await fake.graph(directory: dir) }

        vm.scheduleRefresh(directory: "/tmp/repo", repoID: nil, in: nil)
        try await pollUntil(timeout: .seconds(2)) { fake.callCount == 1 }

        vm.teardown()

        try await pollUntil(timeout: .seconds(2)) {
            fake.cancelledDirectories.contains("/tmp/repo")
        }

        // Even after release, no result should land because the task was cancelled.
        fake.releaseAll(with: Self.makeThreeLaneGraph())
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.graph == nil)
        #expect(vm.lastDirectory == nil)
    }

    // MARK: - nil directory clears state

    @Test func nilDirectoryClearsState() async throws {
        let expected = Self.makeThreeLaneGraph()
        let vm = InspectBranchViewModel()
        vm.graphService = { _ in expected }

        vm.scheduleRefresh(directory: "/tmp/repo", repoID: nil, in: nil)
        try await pollUntil(timeout: .seconds(2)) { vm.graph != nil }

        vm.scheduleRefresh(directory: nil, repoID: nil, in: nil)
        try await pollUntil(timeout: .seconds(2)) {
            vm.graph == nil && vm.lastDirectory == nil
        }
        #expect(vm.graph == nil)
        #expect(vm.lastDirectory == nil)

        vm.teardown()
    }

    // MARK: - Fixtures

    private static func makeThreeLaneGraph() -> GitCommitGraph {
        let lanes = [
            GitLane(id: "main", label: "main", colorIndex: 0, isCollapsed: false),
            GitLane(id: "feat-a", label: "feat-a", colorIndex: 1, isCollapsed: false),
            GitLane(id: "feat-b", label: "feat-b", colorIndex: 2, isCollapsed: false)
        ]
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let commits = [
            GitCommit(
                sha: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                shortSha: "aaaaaaa",
                laneIndex: 0,
                parentShas: ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
                author: "alice",
                when: when,
                subject: "head of main",
                isMerge: false,
                headRefs: ["main"],
                tag: nil
            ),
            GitCommit(
                sha: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                shortSha: "bbbbbbb",
                laneIndex: 1,
                parentShas: [],
                author: "bob",
                when: when.addingTimeInterval(-3600),
                subject: "feat a",
                isMerge: false,
                headRefs: ["feat-a"],
                tag: nil
            ),
            GitCommit(
                sha: "cccccccccccccccccccccccccccccccccccccccc",
                shortSha: "ccccccc",
                laneIndex: 2,
                parentShas: [],
                author: "carol",
                when: when.addingTimeInterval(-7200),
                subject: "feat b",
                isMerge: false,
                headRefs: ["feat-b"],
                tag: nil
            )
        ]
        return GitCommitGraph(lanes: lanes, commits: commits, collapsedLaneCount: 0)
    }
}

// MARK: - Test fakes

@MainActor
private final class FakeBranchGraphHost: BranchGraphDirtyHost {
    var branchGraphDirty: Set<GitRepoID> = []
    private(set) var clearedRepos: [GitRepoID] = []
    func clearBranchGraphDirty(repoID: GitRepoID) {
        clearedRepos.append(repoID)
        branchGraphDirty.remove(repoID)
    }
}

@MainActor
private final class BlockingGraphService {
    private var continuations: [CheckedContinuation<GitCommitGraph?, Never>] = []
    private(set) var cancelledDirectories: [String] = []
    private(set) var callCount = 0

    func graph(directory: String) async -> GitCommitGraph? {
        callCount += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                continuations.append(cont)
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelledDirectories.append(directory)
            }
        }
    }

    func releaseAll(with graph: GitCommitGraph?) {
        let conts = continuations
        continuations.removeAll()
        for cont in conts { cont.resume(returning: graph) }
    }
}

