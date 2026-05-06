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

    // MARK: - FR-T20: headLaneFirst

    @Test func headLaneFirst() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Create a second branch
        try runGitSync(["checkout", "-b", "feature"], in: repo)
        let filePath = (repo as NSString).appendingPathComponent("feature.txt")
        try "feature content".write(toFile: filePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "feature commit"], in: repo)

        // HEAD is on 'feature'
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

        // Should have 7 lanes: 6 named + 1 collapsed "other" lane
        #expect(g.lanes.count == 7)
        #expect(g.lanes.last?.id == GitLane.collapsedID)
        #expect(g.lanes.last?.isCollapsed == true)
        // 9 branch tips total, 6 named lanes → 3 collapsed
        #expect(g.collapsedLaneCount == 3)
    }

    // MARK: - FR-T20a: lanePriorityOrdering

    @Test func lanePriorityOrdering() async throws {
        // Set up:
        // - HEAD on branch 'alpha'
        // - branch 'beta' tracks origin/beta (remote-tracking)
        // - branches 'gamma', 'delta' have more commits than 'beta' but no tracked remote
        // Expected lane order: alpha, beta, gamma/delta (alphabetical tie-break), then others

        let originRepo = try makeTempGitRepo()
        defer { cleanup(originRepo) }

        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Set up remote
        try runGitSync(["remote", "add", "origin", originRepo], in: repo)

        let defaultBranch = try getDefaultBranch(repo)

        // Create 'beta' and push-simulate by creating origin/beta
        try runGitSync(["checkout", "-b", "beta"], in: repo)
        let betaFile = (repo as NSString).appendingPathComponent("beta.txt")
        try "beta".write(toFile: betaFile, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "beta commit"], in: repo)

        // Create origin/beta in origin repo
        try runGitSync(["checkout", "-b", "beta"], in: originRepo)
        let originBetaFile = (originRepo as NSString).appendingPathComponent("beta.txt")
        try "beta".write(toFile: originBetaFile, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: originRepo)
        try runGitSync(["commit", "-m", "beta origin commit"], in: originRepo)

        // Fetch so origin/beta ref appears locally
        try runGitSync(["fetch", "origin", "beta"], in: repo)
        // Set upstream
        try runGitSync(["branch", "--set-upstream-to=origin/beta", "beta"], in: repo)

        // Create 'gamma' with 2 commits (more than beta's 1)
        try runGitSync(["checkout", defaultBranch], in: repo)
        try runGitSync(["checkout", "-b", "gamma"], in: repo)
        for i in 1...2 {
            let f = (repo as NSString).appendingPathComponent("gamma\(i).txt")
            try "g\(i)".write(toFile: f, atomically: true, encoding: .utf8)
            try runGitSync(["add", "."], in: repo)
            try runGitSync(["commit", "-m", "gamma commit \(i)"], in: repo)
        }

        // Create 'delta' with 2 commits
        try runGitSync(["checkout", defaultBranch], in: repo)
        try runGitSync(["checkout", "-b", "delta"], in: repo)
        for i in 1...2 {
            let f = (repo as NSString).appendingPathComponent("delta\(i).txt")
            try "d\(i)".write(toFile: f, atomically: true, encoding: .utf8)
            try runGitSync(["add", "."], in: repo)
            try runGitSync(["commit", "-m", "delta commit \(i)"], in: repo)
        }

        // Create 'alpha' — HEAD will be on this
        try runGitSync(["checkout", defaultBranch], in: repo)
        try runGitSync(["checkout", "-b", "alpha"], in: repo)
        let alphaFile = (repo as NSString).appendingPathComponent("alpha.txt")
        try "alpha".write(toFile: alphaFile, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "alpha commit"], in: repo)

        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        // alpha must be lanes[0] (HEAD)
        #expect(g.lanes[0].id == "alpha")

        // beta must be second (has tracked remote)
        if g.lanes.count > 1 {
            #expect(g.lanes[1].id == "beta")
        }

        // gamma and delta (more commits, no remote) come after beta, alphabetical
        let laneIDs = g.lanes.map(\.id)
        if let betaIdx = laneIDs.firstIndex(of: "beta"),
           let gammaIdx = laneIDs.firstIndex(of: "gamma"),
           let deltaIdx = laneIDs.firstIndex(of: "delta") {
            #expect(betaIdx < gammaIdx)
            #expect(betaIdx < deltaIdx)
            #expect(deltaIdx < gammaIdx) // alphabetical: delta < gamma
        }
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

    // MARK: - FR-T20: detachedHEADUsesShortSha

    @Test func detachedHEADUsesShortSha() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Add a commit so HEAD has a SHA
        let filePath = (repo as NSString).appendingPathComponent("file.txt")
        try "content".write(toFile: filePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "second commit"], in: repo)

        let sha = try getSHA(repo)
        let shortSha = String(sha.prefix(7))

        // Detach HEAD
        try runGitSync(["checkout", "--detach", "HEAD"], in: repo)

        let graph = await GitStatusService.commitGraph(directory: repo)
        let g = try #require(graph)

        // Graph should succeed
        #expect(!g.commits.isEmpty)
        #expect(!g.lanes.isEmpty)

        // The HEAD lane should use short SHA as label
        let headLane = g.lanes[0]
        #expect(headLane.label == shortSha)
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
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["symbolic-ref", "--short", "HEAD"]
        process.currentDirectoryURL = URL(filePath: repo)
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "main").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func getSHA(_ repo: String) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        process.currentDirectoryURL = URL(filePath: repo)
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGitSync(_ args: [String], in dir: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(filePath: dir)
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw StringError("git \(args.joined(separator: " ")) failed: \(msg)")
        }
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private struct StringError: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
