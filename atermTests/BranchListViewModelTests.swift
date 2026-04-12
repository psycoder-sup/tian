import Testing
import Foundation
@testable import aterm

@MainActor
struct BranchListViewModelTests {

    // MARK: - Fixtures

    private func entry(
        local: String? = nil,
        remote: (String, String)? = nil,      // (remoteName, branchName)
        date: Date = Date(),
        upstream: String? = nil,
        inUse: Bool = false,
        current: Bool = false
    ) -> BranchEntry {
        if let name = local {
            return BranchEntry(
                id: "local:\(name)",
                displayName: name,
                kind: .local(upstream: upstream),
                committerDate: date,
                isInUse: inUse,
                isCurrent: current
            )
        } else if let (remoteName, branchName) = remote {
            return BranchEntry(
                id: "\(remoteName):\(branchName)",
                displayName: branchName,
                kind: .remote(remoteName: remoteName),
                committerDate: date,
                isInUse: inUse,
                isCurrent: current
            )
        } else {
            fatalError("need local or remote")
        }
    }

    // MARK: - Dedup

    @Test
    func dedup_collapsesLocalAndRemoteWithSameName() {
        let now = Date()
        let raw = [
            entry(local: "feat/auth", date: now),
            entry(remote: ("origin", "feat/auth"), date: now.addingTimeInterval(-60)),
        ]
        let rows = BranchListViewModel.dedup(raw)
        #expect(rows.count == 1)
        #expect(rows[0].displayName == "feat/auth")
        #expect(rows[0].badge == .localAndOrigin("origin"))
        #expect(rows[0].remoteRef == nil)   // picking local
    }

    @Test
    func dedup_keepsRemoteOnlyAsOrigin() {
        let rows = BranchListViewModel.dedup([
            entry(remote: ("origin", "feat/x"))
        ])
        #expect(rows.count == 1)
        #expect(rows[0].badge == .origin("origin"))
        #expect(rows[0].remoteRef == "origin/feat/x")
    }

    @Test
    func dedup_keepsLocalOnlyAsLocal() {
        let rows = BranchListViewModel.dedup([
            entry(local: "feat/y")
        ])
        #expect(rows.count == 1)
        #expect(rows[0].badge == .local)
        #expect(rows[0].remoteRef == nil)
    }

    @Test
    func dedup_sortsByMostRecentCommitterDate() {
        let now = Date()
        let raw = [
            entry(local: "oldest", date: now.addingTimeInterval(-10_000)),
            entry(local: "newest", date: now),
            entry(local: "middle", date: now.addingTimeInterval(-5_000)),
        ]
        let rows = BranchListViewModel.dedup(raw)
        #expect(rows.map(\.displayName) == ["newest", "middle", "oldest"])
    }

    @Test
    func dedup_preservesInUseFlagFromLocal() {
        let now = Date()
        let raw = [
            entry(local: "main", date: now, inUse: true, current: true),
            entry(remote: ("origin", "main"), date: now),
        ]
        let rows = BranchListViewModel.dedup(raw)
        #expect(rows[0].isInUse == true)
        #expect(rows[0].isCurrent == true)
    }

    // MARK: - Edge cases

    @Test
    func dedup_handlesEmptyInput() {
        #expect(BranchListViewModel.dedup([]).isEmpty)
    }

    // MARK: - formatRelative

    @Test
    func formatRelative_justNowUnder60Seconds() {
        let now = Date()
        #expect(BranchListViewModel.formatRelative(now.addingTimeInterval(-30), now: now) == "just now")
    }

    @Test
    func formatRelative_minutesAgo() {
        let now = Date()
        #expect(BranchListViewModel.formatRelative(now.addingTimeInterval(-5 * 60), now: now) == "5m ago")
    }

    @Test
    func formatRelative_hoursAgo() {
        let now = Date()
        #expect(BranchListViewModel.formatRelative(now.addingTimeInterval(-3 * 3600), now: now) == "3h ago")
    }

    @Test
    func formatRelative_yesterdayBetween24And48Hours() {
        let now = Date()
        #expect(BranchListViewModel.formatRelative(now.addingTimeInterval(-30 * 3600), now: now) == "yesterday")
    }

    @Test
    func formatRelative_daysAgo() {
        let now = Date()
        #expect(BranchListViewModel.formatRelative(now.addingTimeInterval(-3 * 86_400), now: now) == "3d ago")
    }

    @Test
    func formatRelative_weeksAgo() {
        let now = Date()
        #expect(BranchListViewModel.formatRelative(now.addingTimeInterval(-10 * 86_400), now: now) == "1w ago")
    }

    @Test
    func formatRelative_monthsAgo() {
        let now = Date()
        #expect(BranchListViewModel.formatRelative(now.addingTimeInterval(-60 * 86_400), now: now) == "2mo ago")
    }

    // MARK: - Fake service

    private actor FakeService: BranchListProviding {
        var entries: [BranchEntry]
        var fetchCalls = 0
        var fetchShouldThrow = false

        init(_ entries: [BranchEntry]) {
            self.entries = entries
        }

        func setEntries(_ new: [BranchEntry]) { self.entries = new }
        func setFetchShouldThrow(_ v: Bool) { fetchShouldThrow = v }

        func listBranches(repoRoot: String) async throws -> [BranchEntry] {
            entries
        }

        func fetchRemotes(repoRoot: String) async throws {
            fetchCalls += 1
            if fetchShouldThrow {
                throw WorktreeError.gitError(command: "git fetch", stderr: "no network")
            }
        }
    }

    private func makeModel(
        entries: [BranchEntry]
    ) -> (BranchListViewModel, FakeService) {
        let service = FakeService(entries)
        let model = BranchListViewModel(service: service)
        return (model, service)
    }

    // MARK: - Filter

    @Test
    func filter_isCaseInsensitiveSubstring() async {
        let (model, _) = makeModel(entries: [
            entry(local: "feat/auth"),
            entry(local: "feat/onboarding"),
            entry(local: "main"),
        ])
        await model.load(repoRoot: "/unused")
        model.query = "AUT"
        #expect(model.rows.map(\.displayName) == ["feat/auth"])
    }

    @Test
    func filter_autoHighlightsFirstMatch() async {
        let (model, _) = makeModel(entries: [
            entry(local: "feat/auth", date: Date()),
            entry(local: "feat/account", date: Date().addingTimeInterval(-60)),
        ])
        await model.load(repoRoot: "/unused")
        model.query = "feat"
        #expect(model.highlightedID == "local:feat/auth")
    }

    // MARK: - Highlight

    @Test
    func moveHighlight_skipsInUseRows() async {
        let now = Date()
        let (model, _) = makeModel(entries: [
            entry(local: "a", date: now),
            entry(local: "b", date: now.addingTimeInterval(-10), inUse: true),
            entry(local: "c", date: now.addingTimeInterval(-20)),
        ])
        await model.load(repoRoot: "/unused")
        // highlight starts on "a"
        #expect(model.highlightedID == "local:a")
        model.moveHighlight(.down)
        #expect(model.highlightedID == "local:c")  // skipped "b"
        model.moveHighlight(.up)
        #expect(model.highlightedID == "local:a")
    }

    @Test
    func selectedRow_returnsNilForInUse() async {
        let (model, _) = makeModel(entries: [
            entry(local: "main", inUse: true, current: true),
        ])
        await model.load(repoRoot: "/unused")
        // Only row is in-use — highlight should be nil.
        #expect(model.highlightedID == nil)
        #expect(model.selectedRow() == nil)
    }

    // MARK: - Collision

    @Test
    func collision_returnsMatchingRowInNewBranchMode() async {
        let (model, _) = makeModel(entries: [
            entry(local: "main"),
        ])
        await model.load(repoRoot: "/unused")
        model.mode = .newBranch
        #expect(model.collision(for: "main")?.displayName == "main")
        #expect(model.collision(for: "feat/new") == nil)
    }

    // MARK: - Load flow

    @Test
    func load_invokesFetchAfterInitialList() async {
        let (model, service) = makeModel(entries: [entry(local: "a")])
        await model.load(repoRoot: "/unused")
        #expect(await service.fetchCalls == 1)
        #expect(model.isFetching == false)
        #expect(model.usedCachedRemotes == false)
    }

    @Test
    func load_marksUsedCachedRemotesOnFetchFailure() async {
        let (model, service) = makeModel(entries: [entry(local: "a")])
        await service.setFetchShouldThrow(true)
        await model.load(repoRoot: "/unused")
        #expect(model.usedCachedRemotes == true)
        #expect(model.rows.map(\.displayName) == ["a"])  // cached list still shown
    }

    @Test
    func load_clearsStaleLoadErrorAfterRecovery() async {
        // Step 1 fails (first listBranches throws), then step 2's fetch + reload succeed.
        // loadError must be cleared so the UI doesn't show a stale error over valid rows.
        let service = FakingListService()
        await service.setFailFirstListOnly(true)
        await service.setEntriesOnRecovery([entry(local: "a")])

        let model = BranchListViewModel(service: service)
        await model.load(repoRoot: "/unused")

        #expect(model.loadError == nil)
        #expect(model.rows.map(\.displayName) == ["a"])
    }
}

private actor FakingListService: BranchListProviding {
    private var failFirstListOnly = false
    private var listCallCount = 0
    private var recoveryEntries: [BranchEntry] = []

    func setFailFirstListOnly(_ v: Bool) { failFirstListOnly = v }
    func setEntriesOnRecovery(_ entries: [BranchEntry]) { recoveryEntries = entries }

    func listBranches(repoRoot: String) async throws -> [BranchEntry] {
        listCallCount += 1
        if failFirstListOnly && listCallCount == 1 {
            throw WorktreeError.gitError(command: "git for-each-ref", stderr: "boom")
        }
        return recoveryEntries
    }

    func fetchRemotes(repoRoot: String) async throws {
        // success (no-op)
    }
}
