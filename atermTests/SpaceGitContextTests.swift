import Foundation
import Testing
@testable import aterm

@MainActor
struct SpaceGitContextTests {

    // MARK: - Lazy vs Eager Detection

    @Test func lazyDetectionDoesNotDetectOnInitForNonWorktreeSpace() async {
        let context = SpaceGitContext(worktreePath: nil)

        // Give any hypothetical init-time task a chance to run
        try? await Task.sleep(for: .milliseconds(100))

        #expect(context.repoStatuses.isEmpty)
        #expect(context.pinnedRepoOrder.isEmpty)
        #expect(context.paneRepoAssignments.isEmpty)
    }

    @Test func eagerDetectionDetectsOnInitForWorktreeSpace() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: URL(filePath: repo))

        // Wait for the async detection task to complete
        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.repoStatuses.count == 1)
        #expect(context.pinnedRepoOrder.count == 1)
        let status = context.repoStatuses.values.first
        #expect(status?.branchName != nil)
        #expect(status?.branchName?.isEmpty == false)
    }

    // MARK: - Restored Session

    @Test func restoredSessionTriggersDetectionViaPaneAdded() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)

        // Simulate restore: call paneAdded with a persisted working directory
        let paneID = UUID()
        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.paneRepoAssignments[paneID] != nil)
        #expect(context.repoStatuses.count == 1)
        let status = context.repoStatuses.values.first
        #expect(status?.branchName != nil)
    }

    @Test func paneAddedIgnoresEmptyAndTildeDirectories() async {
        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneAdded(paneID: paneID, workingDirectory: nil)
        context.paneAdded(paneID: paneID, workingDirectory: "")
        context.paneAdded(paneID: paneID, workingDirectory: "~")

        try? await Task.sleep(for: .milliseconds(200))

        #expect(context.repoStatuses.isEmpty)
        #expect(context.paneRepoAssignments.isEmpty)
    }

    // MARK: - In-flight Task Cancellation

    @Test func rapidRefreshesCancelPriorTask() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        // Fire multiple rapid directory changes — earlier tasks should be cancelled
        for i in 0..<5 {
            context.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: repo)
            // Tiny delay to ensure tasks are actually dispatched
            if i < 4 {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        // Should end up with exactly one repo status (not duplicated)
        #expect(context.repoStatuses.count == 1)
        #expect(context.pinnedRepoOrder.count == 1)
        let status = context.repoStatuses.values.first
        #expect(status?.branchName != nil)
    }

    // MARK: - Pane Removed / Garbage Collection

    @Test func paneRemovedGarbageCollectsOrphanedRepo() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.repoStatuses.count == 1)

        // Remove the only pane referencing this repo
        context.paneRemoved(paneID: paneID)

        #expect(context.repoStatuses.isEmpty)
        #expect(context.pinnedRepoOrder.isEmpty)
    }

    // MARK: - Teardown

    @Test func teardownClearsAllState() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        context.paneAdded(paneID: UUID(), workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        context.teardown()

        #expect(context.repoStatuses.isEmpty)
        #expect(context.pinnedRepoOrder.isEmpty)
        #expect(context.paneRepoAssignments.isEmpty)
    }

    // MARK: - Integration: Full Flow

    @Test func integrationDetectsRepoAndPopulatesBranchName() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Create a named branch to verify
        try runGitSync(["checkout", "-b", "feature/test-branch"], in: repo)

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.repoStatuses.count == 1)
        let repoID = try #require(context.pinnedRepoOrder.first)
        let status = try #require(context.repoStatuses[repoID])

        #expect(status.branchName == "feature/test-branch")
        #expect(status.isDetachedHead == false)
        #expect(status.diffSummary.isEmpty)
        #expect(status.changedFiles.isEmpty)
        #expect(status.prStatus == nil)
    }

    // MARK: - Integration: Diff Summary

    @Test func integrationPopulatesDiffSummary() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Modify existing file
        let readmePath = (repo as NSString).appendingPathComponent("README.md")
        try "Modified content".write(toFile: readmePath, atomically: true, encoding: .utf8)

        // Add a new untracked file
        let newFilePath = (repo as NSString).appendingPathComponent("new.txt")
        try "new file".write(toFile: newFilePath, atomically: true, encoding: .utf8)

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneWorkingDirectoryChanged(paneID: paneID, newDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            context.repoStatuses.values.first?.diffSummary.isEmpty == false
        }

        let repoID = try #require(context.pinnedRepoOrder.first)
        let status = try #require(context.repoStatuses[repoID])

        #expect(status.diffSummary.modified == 1)
        #expect(status.diffSummary.added == 1)
        #expect(status.diffSummary.totalCount == 2)
        #expect(status.changedFiles.count == 2)
    }

    // MARK: - Watcher Lifecycle

    @Test func watcherStartedOnRepoDetection() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.activeWatcherCount == 1)
    }

    @Test func watcherStoppedOnRepoUnpin() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        let paneID = UUID()

        context.paneAdded(paneID: paneID, workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        #expect(context.activeWatcherCount == 1)

        context.paneRemoved(paneID: paneID)

        #expect(context.activeWatcherCount == 0)
    }

    @Test func teardownStopsAllWatchers() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let context = SpaceGitContext(worktreePath: nil)
        context.paneAdded(paneID: UUID(), workingDirectory: repo)

        try await pollUntil(timeout: 5.0) {
            !context.repoStatuses.isEmpty
        }

        context.teardown()

        #expect(context.activeWatcherCount == 0)
    }

    // MARK: - Helpers

    private func pollUntil(timeout: Double, condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("Timed out waiting for condition after \(timeout)s")
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aterm-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir,
                                                  withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)

        let readmePath = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readmePath, atomically: true, encoding: .utf8)

        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)

        return dir
    }

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
