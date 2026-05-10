import Foundation
import Testing
@testable import tian

@Suite(.serialized)
struct GitStatusServiceCommitGraphTests {

    // MARK: - FR-T25: threeSubprocessesOnly

    @Test func threeSubprocessesOnly() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Add a commit and a tag for completeness
        let filePath = (repo as NSString).appendingPathComponent("file.txt")
        try "content".write(toFile: filePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "second commit"], in: repo)
        try runGitSync(["tag", "v1.0"], in: repo)

        GitStatusService.commitGraphSubprocessCounter = 0
        let graph = await GitStatusService.commitGraph(directory: repo)
        #expect(graph != nil)
        #expect(GitStatusService.commitGraphSubprocessCounter == 3)
    }

    // MARK: - mostAheadLaneFirst

    /// Lane 0 is the most-ahead branch — i.e. whichever branch's tip sits at
    /// the top of `git log --all --date-order`. When that branch happens to
    /// be HEAD, lane 0 carries HEAD's branch name.
    @Test func mostAheadLaneFirst() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Create a second branch
        try runGitSync(["checkout", "-b", "feature"], in: repo)
        let filePath = (repo as NSString).appendingPathComponent("feature.txt")
        try "feature content".write(toFile: filePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "feature commit"], in: repo)

        // HEAD is on 'feature' — and 'feature' is the most-ahead branch.
        let graph = await GitStatusService.commitGraph(directory: repo)
        let graph2 = try #require(graph)
        #expect(!graph2.lanes.isEmpty)
        #expect(graph2.lanes[0].id == "feature")
    }

    // MARK: - FR-T20a: laneCapAtSixWithOther

    @Test func laneCapAtSixWithOther() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Create the initial branch (main/master is already lane 0)
        // We need 9 distinct branch tips inside the 50-commit window.
        // Start from main, create 8 more branches each with their own commit.
        let defaultBranch = try getDefaultBranch(repo)

        for i in 1...8 {
            // Go back to default branch and create new branch from it
            try runGitSync(["checkout", defaultBranch], in: repo)
            try runGitSync(["checkout", "-b", "branch-\(i)"], in: repo)
            let filePath = (repo as NSString).appendingPathComponent("branch\(i).txt")
            try "content \(i)".write(toFile: filePath, atomically: true, encoding: .utf8)
            try runGitSync(["add", "."], in: repo)
            try runGitSync(["commit", "-m", "commit on branch-\(i)"], in: repo)
        }

        // HEAD is now on 'branch-8'. Return to default branch.
        try runGitSync(["checkout", defaultBranch], in: repo)

        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        // The most-ahead branch (last-created branch-8) absorbs the default
        // branch into its trunk via the shared root, so we end up with 8
        // lanes total: 1 trunk + 7 sibling tips. After the 6-lane cap that
        // collapses to 6 named + 1 trailing "other" lane.
        #expect(g.lanes.count == 7)
        #expect(g.lanes.last?.id == GitLane.collapsedID)
        #expect(g.lanes.last?.isCollapsed == true)
        #expect(g.collapsedLaneCount == 2)
    }

    // MARK: - mostAheadBranchOwnsTrunkLane

    /// Lane 0 is the trunk of the *most ahead* branch — the topmost commit
    /// in `git log --all --date-order`. When a sibling branch is created
    /// after HEAD's branch, that sibling becomes lane 0 even though HEAD
    /// stays on its own (now-behind) branch.
    @Test func mostAheadBranchOwnsTrunkLane() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let defaultBranch = try getDefaultBranch(repo)

        // HEAD branch: a single commit on `behind`. Use explicit dates so
        // `git log --date-order` ranks `most-ahead` strictly newer than
        // `behind` regardless of how fast the test runs.
        try runGitSync(["checkout", "-b", "behind"], in: repo)
        let bf = (repo as NSString).appendingPathComponent("behind.txt")
        try "b".write(toFile: bf, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try commitWithDate(repo, message: "behind commit", date: "2025-01-01T00:00:00")
        let behindSha = try getSHA(repo)

        // The "most ahead" branch — created from the same root, with a
        // strictly newer commit (one minute later). Then go back to HEAD on
        // `behind`.
        try runGitSync(["checkout", defaultBranch], in: repo)
        try runGitSync(["checkout", "-b", "most-ahead"], in: repo)
        let af = (repo as NSString).appendingPathComponent("ahead.txt")
        try "a".write(toFile: af, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try commitWithDate(repo, message: "ahead commit", date: "2025-01-01T00:01:00")
        let aheadSha = try getSHA(repo)
        try runGitSync(["checkout", "behind"], in: repo)

        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        // Lane 0 belongs to the most-ahead branch, not to HEAD.
        #expect(g.lanes[0].id == "most-ahead")

        let aheadCommit = try #require(g.commits.first { $0.sha == aheadSha })
        let behindCommit = try #require(g.commits.first { $0.sha == behindSha })

        // The most-ahead tip and the shared root sit on lane 0; HEAD's tip
        // is on a non-trunk side lane.
        #expect(aheadCommit.laneIndex == 0)
        #expect(behindCommit.laneIndex != 0)

        // HEAD ring still anchors to the actual HEAD commit (on its side
        // lane), via `headSha`.
        #expect(g.headSha == behindSha)
    }

    // MARK: - localBranchWithSlashIsRecognisedAsLocal

    /// Local branches whose names contain `/` (e.g. `fix/foo`, `feature/x`)
    /// must be classified as local — the `for-each-ref` ref-prefix check, not
    /// a "contains slash" heuristic, decides local vs remote.
    @Test func localBranchWithSlashIsRecognisedAsLocal() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Create a local slash-named branch with the most-ahead commit.
        try runGitSync(["checkout", "-b", "fix/git-ignored-dir"], in: repo)
        let f = (repo as NSString).appendingPathComponent("fix.txt")
        try "fix".write(toFile: f, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "fix commit"], in: repo)
        let fixSha = try getSHA(repo)

        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        // The slash branch is the most-ahead tip and must own lane 0,
        // labelled with its local name (not as a remote ref).
        #expect(g.lanes[0].id == "fix/git-ignored-dir")
        let fixCommit = try #require(g.commits.first { $0.sha == fixSha })
        #expect(fixCommit.laneIndex == 0)
    }

    // MARK: - localBranchTipNotMostAheadKeepsItsOwnSideLane

    /// When a local branch's tip is *not* the most-ahead commit, it sits on
    /// a non-trunk side lane labelled with the local branch name. This is
    /// the more interesting case for slash-named branches because the
    /// for-each-ref classification only matters when the branch isn't being
    /// absorbed into the trunk.
    @Test func localBranchTipNotMostAheadKeepsItsOwnSideLane() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let defaultBranch = try getDefaultBranch(repo)

        // Slash-named branch with a commit (not the newest).
        try runGitSync(["checkout", "-b", "fix/git-ignored-dir"], in: repo)
        let f = (repo as NSString).appendingPathComponent("fix.txt")
        try "fix".write(toFile: f, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try commitWithDate(repo, message: "fix commit", date: "2025-01-01T00:00:00")
        let fixSha = try getSHA(repo)

        // Make a strictly-newer sibling on a different branch so `fix/...`
        // is no longer the most-ahead tip.
        try runGitSync(["checkout", defaultBranch], in: repo)
        try runGitSync(["checkout", "-b", "newer"], in: repo)
        let nf = (repo as NSString).appendingPathComponent("newer.txt")
        try "n".write(toFile: nf, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try commitWithDate(repo, message: "newer commit", date: "2025-01-01T00:01:00")

        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        let laneIDs = g.lanes.map(\.id)
        #expect(laneIDs.contains("fix/git-ignored-dir"))
        let fixLaneIdx = try #require(laneIDs.firstIndex(of: "fix/git-ignored-dir"))
        let fixCommit = try #require(g.commits.first { $0.sha == fixSha })
        #expect(fixCommit.laneIndex == fixLaneIdx)
        #expect(fixCommit.laneIndex != 0)
    }

    // MARK: - divergentSiblingsGetSeparateLanes

    /// Divergent commits sharing a single parent must each render on their
    /// own lane so the fork is visually obvious.
    @Test func divergentSiblingsGetSeparateLanes() async throws {
        let originRepo = try makeTempGitRepo()
        defer { cleanup(originRepo) }
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try runGitSync(["remote", "add", "origin", originRepo], in: repo)
        let defaultBranch = try getDefaultBranch(repo)
        let parentSha = try getSHA(repo)

        // Sibling 1: HEAD branch (local) diverging from parent
        try runGitSync(["checkout", "-b", "feature/local"], in: repo)
        let f1 = (repo as NSString).appendingPathComponent("local.txt")
        try "local".write(toFile: f1, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "local sibling"], in: repo)
        let localSha = try getSHA(repo)

        // Sibling 2: a commit that exists only as a remote ref
        // (origin/remote-only). Build it in the origin repo then fetch.
        try runGitSync(["checkout", defaultBranch], in: originRepo)
        try runGitSync(["checkout", "-b", "remote-only"], in: originRepo)
        let f2 = (originRepo as NSString).appendingPathComponent("remote.txt")
        try "remote".write(toFile: f2, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: originRepo)
        try runGitSync(["commit", "-m", "remote sibling"], in: originRepo)
        try runGitSync(["fetch", "origin", "remote-only"], in: repo)
        let remoteSha = try getSHA(repo, ref: "refs/remotes/origin/remote-only")

        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        let localCommit = try #require(g.commits.first { $0.sha == localSha })
        let remoteCommit = try #require(g.commits.first { $0.sha == remoteSha })
        let parentCommit = try #require(g.commits.first { $0.sha == parentSha })

        // The most-ahead tip owns lane 0; the other sibling lives on a
        // non-trunk lane. Whichever of `localSha`/`remoteSha` was created
        // last (by author timestamp) is the most-ahead tip, so we just
        // assert the two siblings end up on different lanes and one of them
        // is on the trunk.
        let onTrunk = [localCommit.laneIndex, remoteCommit.laneIndex].contains(0)
        #expect(onTrunk, "one of the two divergent siblings must own lane 0")
        #expect(localCommit.laneIndex != remoteCommit.laneIndex,
                "divergent siblings must occupy distinct lanes")
        // The shared parent of the local sibling lies on its sibling's
        // first-parent walk — if `localSha` is the most-ahead tip, the
        // parent inherits lane 0; otherwise the parent inherits whatever
        // side lane local landed on. Either way it shares the local sibling's
        // lane, never the remote sibling's.
        #expect(parentCommit.laneIndex == localCommit.laneIndex)
    }

    // MARK: - trunkAbsorbsAncestorWithBranchDecoration

    /// The trunk follows the most-ahead tip's first-parent walk in its
    /// entirety — even when it passes through commits that carry a non-HEAD
    /// branch decoration (e.g. an ancestor where the default branch's tip
    /// lives). A naive "match decoration first" lane resolver would split
    /// the trunk in two at that ancestor.
    @Test func trunkAbsorbsAncestorWithBranchDecoration() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }
        let defaultBranch = try getDefaultBranch(repo)

        // An undecorated commit on the default branch — this becomes the
        // default branch's tip when we leave it for `feature` below.
        let extra = (repo as NSString).appendingPathComponent("extra.txt")
        try "x".write(toFile: extra, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "extra default-branch commit"], in: repo)
        let ancestorSha = try getSHA(repo)

        // `feature` becomes the most-ahead tip with one extra commit.
        try runGitSync(["checkout", "-b", "feature"], in: repo)
        let ff = (repo as NSString).appendingPathComponent("feature.txt")
        try "f".write(toFile: ff, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "feature commit"], in: repo)

        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        let ancestor = try #require(g.commits.first { $0.sha == ancestorSha })

        // The ancestor carries the `defaultBranch` decoration but it's still
        // on the trunk's spine, so it must render on lane 0 — not split off
        // into a `defaultBranch`-named side lane.
        #expect(ancestor.laneIndex == 0)
        #expect(g.lanes[0].id == "feature")
        #expect(!g.lanes.contains { $0.id == defaultBranch })
    }

    // MARK: - FR-T25: tagsResolvedFromBulkCall

    @Test func tagsResolvedFromBulkCall() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Create 5 commits and tag each
        var taggedShas: [String] = []
        for i in 1...5 {
            let filePath = (repo as NSString).appendingPathComponent("file\(i).txt")
            try "content \(i)".write(toFile: filePath, atomically: true, encoding: .utf8)
            try runGitSync(["add", "."], in: repo)
            try runGitSync(["commit", "-m", "commit \(i)"], in: repo)
            try runGitSync(["tag", "v\(i).0"], in: repo)
            let sha = try getSHA(repo)
            taggedShas.append(sha)
        }

        GitStatusService.commitGraphSubprocessCounter = 0
        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        // Subprocess count must remain 3 even with 5 tags
        #expect(GitStatusService.commitGraphSubprocessCounter == 3)

        // The HEAD commit (latest) should have the tag "v5.0"
        let headCommit = g.commits.first
        let headTag = try #require(headCommit?.tag)
        #expect(headTag == "v5.0")

        // At least some commits should have tags populated
        let taggedCommits = g.commits.filter { $0.tag != nil }
        #expect(taggedCommits.count >= 1)
    }

    // MARK: - detachedHeadResolvesHeadShaButLaneLabelComesFromMostAhead

    /// When HEAD is detached on a commit that *also* has a branch decoration
    /// (e.g. `git checkout --detach` from `main`), the most-ahead trunk lane
    /// is labelled with that branch — but `headSha` still resolves to the
    /// detached commit so the HEAD ring/chip can anchor correctly.
    @Test func detachedHeadResolvesHeadShaButLaneLabelComesFromMostAhead() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }
        let defaultBranch = try getDefaultBranch(repo)

        let filePath = (repo as NSString).appendingPathComponent("file.txt")
        try "content".write(toFile: filePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "second commit"], in: repo)
        let sha = try getSHA(repo)

        try runGitSync(["checkout", "--detach", "HEAD"], in: repo)

        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        #expect(!g.commits.isEmpty)
        #expect(!g.lanes.isEmpty)

        // Lane 0 is labelled by the most-ahead branch decoration on the
        // tip — `defaultBranch` here, since main still points at the same
        // commit HEAD detached from.
        #expect(g.lanes[0].id == defaultBranch)

        // `headSha` still resolves to the detached commit so the HEAD ring
        // anchors to the right node in the canvas.
        #expect(g.headSha == sha)
    }

    // MARK: - Helpers

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-cg-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)
        // Disable GPG signing for test repos
        try runGitSync(["config", "commit.gpgsign", "false"], in: dir)

        let readmePath = (dir as NSString).appendingPathComponent("README.md")
        try "# Test Repo\n".write(toFile: readmePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)

        return dir
    }

    private func getDefaultBranch(_ repo: String) throws -> String {
        try runGitSync(["symbolic-ref", "--short", "HEAD"], in: repo)
    }

    private func getSHA(_ repo: String, ref: String = "HEAD") throws -> String {
        try runGitSync(["rev-parse", ref], in: repo)
    }

    @discardableResult
    private func runGitSync(
        _ args: [String], in dir: String, env: [String: String] = [:]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(filePath: dir)
        if !env.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            process.environment = merged
        }
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw StringError("git \(args.joined(separator: " ")) failed: \(msg)")
        }
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        return (String(data: out, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `git commit -m <message>` with explicit author/committer dates so the
    /// resulting `--date-order` log is deterministic across fast-running
    /// tests. `date` is an ISO 8601 timestamp like `"2025-01-01T00:01:00"`.
    private func commitWithDate(_ dir: String, message: String, date: String) throws {
        try runGitSync(
            ["commit", "-m", message],
            in: dir,
            env: ["GIT_AUTHOR_DATE": date, "GIT_COMMITTER_DATE": date]
        )
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private struct StringError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
