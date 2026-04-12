import Testing
import Foundation
@testable import aterm

struct BranchListServiceTests {

    // MARK: - Helpers

    private struct TestError: Error { let msg: String }

    private func runGitSync(_ args: [String], in dir: String) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(filePath: dir)
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let msg = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw TestError(msg: "git \(args.joined(separator: " ")) failed: \(msg)")
        }
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aterm-branch-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try runGitSync(["init", "--initial-branch=main"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)
        let readme = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readme, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)
        return dir
    }

    private func cleanup(_ dir: String) {
        try? FileManager.default.removeItem(atPath: dir)
    }

    // MARK: - Tests

    @Test
    func listBranches_returnsLocalBranches() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }
        try runGitSync(["branch", "feat/auth"], in: repo)
        try runGitSync(["branch", "feat/onboarding"], in: repo)

        let entries = try await BranchListService.listBranches(repoRoot: repo)

        let names = entries.map(\.displayName).sorted()
        #expect(names == ["feat/auth", "feat/onboarding", "main"])
        #expect(entries.allSatisfy { if case .local = $0.kind { return true } else { return false } })
    }

    @Test
    func listBranches_marksCurrentHead() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let entries = try await BranchListService.listBranches(repoRoot: repo)
        let main = try #require(entries.first { $0.displayName == "main" })
        #expect(main.isCurrent == true)
        #expect(main.isInUse == true)
    }

    @Test
    func listBranches_handlesEmptyRepoWithoutCommits() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aterm-branch-empty-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }
        try runGitSync(["init", "--initial-branch=main"], in: dir)

        let entries = try await BranchListService.listBranches(repoRoot: dir)
        #expect(entries.isEmpty)
    }

    @Test
    func listBranches_marksInUseBranchesFromOtherWorktrees() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }
        try runGitSync(["branch", "feat/auth"], in: repo)
        let wtPath = (repo as NSString).appendingPathComponent("../wt-\(UUID().uuidString)")
        try runGitSync(["worktree", "add", wtPath, "feat/auth"], in: repo)
        defer { try? FileManager.default.removeItem(atPath: wtPath) }

        let entries = try await BranchListService.listBranches(repoRoot: repo)
        let auth = try #require(entries.first { $0.displayName == "feat/auth" })
        #expect(auth.isInUse == true)
    }

    @Test
    func listBranches_includesRemoteBranches() async throws {
        let remote = try makeTempGitRepo()
        defer { cleanup(remote) }
        try runGitSync(["branch", "feat/remote-only"], in: remote)

        let clone = FileManager.default.temporaryDirectory
            .appendingPathComponent("aterm-clone-\(UUID().uuidString)").path
        defer { cleanup(clone) }
        try runGitSync(["clone", remote, clone], in: FileManager.default.temporaryDirectory.path)

        let entries = try await BranchListService.listBranches(repoRoot: clone)
        let remoteEntry = try #require(entries.first { entry in
            guard entry.displayName == "feat/remote-only" else { return false }
            if case .remote = entry.kind { return true } else { return false }
        })
        if case .remote(let name) = remoteEntry.kind {
            #expect(name == "origin")
        } else {
            Issue.record("expected remote kind")
        }
    }

    @Test
    func fetchRemotes_refreshesRemoteRefs() async throws {
        let remote = try makeTempGitRepo()
        defer { cleanup(remote) }

        let clone = FileManager.default.temporaryDirectory
            .appendingPathComponent("aterm-fetch-\(UUID().uuidString)").path
        defer { cleanup(clone) }
        try runGitSync(["clone", remote, clone], in: FileManager.default.temporaryDirectory.path)

        // Add a new branch in the remote AFTER cloning
        try runGitSync(["branch", "feat/new-after-clone"], in: remote)

        // Before fetch — the clone should not see the new branch
        let before = try await BranchListService.listBranches(repoRoot: clone)
        #expect(before.first { $0.displayName == "feat/new-after-clone" } == nil)

        // Fetch, then re-list
        try await BranchListService.fetchRemotes(repoRoot: clone)
        let after = try await BranchListService.listBranches(repoRoot: clone)
        #expect(after.first { $0.displayName == "feat/new-after-clone" } != nil)
    }

    @Test
    func fetchRemotes_throwsGitErrorOnFailure() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aterm-bad-fetch-\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }
        try runGitSync(["init"], in: dir)
        try runGitSync(["remote", "add", "origin", "/nonexistent/repo.git"], in: dir)

        do {
            try await BranchListService.fetchRemotes(repoRoot: dir)
            Issue.record("expected fetchRemotes to throw")
        } catch WorktreeError.gitError {
            // expected
        } catch {
            Issue.record("expected WorktreeError.gitError, got \(error)")
        }
    }
}
