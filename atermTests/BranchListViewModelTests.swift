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
}
