import Foundation
import Testing
@testable import tian

struct GitRepoWatcherTests {

    // MARK: - Watch Path Resolution

    @Test func regularRepoWatchPaths() {
        let paths = GitRepoWatcher.resolveWatchPaths(
            gitDir: ".git",
            commonDir: "/Users/dev/project/.git",
            workingTree: "/Users/dev/project"
        )
        // Working tree is watched recursively; .git/ is covered as a subdirectory.
        #expect(paths == ["/Users/dev/project"])
    }

    @Test func worktreeWatchPathsIncludeWorkingTreeGitDirAndRefs() {
        let paths = GitRepoWatcher.resolveWatchPaths(
            gitDir: "/Users/dev/project/.git/worktrees/feature-branch",
            commonDir: "/Users/dev/project/.git",
            workingTree: "/Users/dev/worktrees/feature-branch"
        )
        #expect(paths.count == 3)
        #expect(paths.contains("/Users/dev/worktrees/feature-branch"))
        #expect(paths.contains("/Users/dev/project/.git/worktrees/feature-branch"))
        #expect(paths.contains("/Users/dev/project/.git/refs"))
    }

    @Test func absoluteGitDirEndingWithDotGit() {
        let paths = GitRepoWatcher.resolveWatchPaths(
            gitDir: "/Users/dev/project/.git",
            commonDir: "/Users/dev/project/.git",
            workingTree: "/Users/dev/project"
        )
        #expect(paths == ["/Users/dev/project"])
    }

    // MARK: - Lifecycle

    @Test func watcherCanBeCreatedAndTornDown() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let watcher = GitRepoWatcher(
            watchPaths: [repo + "/.git"],
            onChangeDetected: { }
        )

        #expect(watcher.isRunning)
        watcher.stop()
        #expect(!watcher.isRunning)
    }

    @Test func watcherDetectsFileChanges() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let callbackFired = CallbackTracker()
        let watcher = GitRepoWatcher(
            watchPaths: [repo + "/.git"],
            latency: 0.5,
            onChangeDetected: { callbackFired.fire() }
        )
        defer { watcher.stop() }

        // Modify a file and stage it to change .git/index
        let filePath = (repo as NSString).appendingPathComponent("test.txt")
        try "change".write(toFile: filePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "test.txt"], in: repo)

        // Wait for FSEvents callback
        try await Task.sleep(for: .seconds(2))

        #expect(callbackFired.didFire)
    }

    @Test func watcherDetectsWorkingTreeFileChanges() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let paths = GitRepoWatcher.resolveWatchPaths(
            gitDir: ".git",
            commonDir: repo + "/.git",
            workingTree: repo
        )

        let callbackFired = CallbackTracker()
        let watcher = GitRepoWatcher(
            watchPaths: paths,
            latency: 0.5,
            onChangeDetected: { callbackFired.fire() }
        )
        defer { watcher.stop() }

        // Create an untracked file in the working tree — does NOT touch .git.
        // With a .git-only watcher this does not fire; the fix requires the
        // working tree to be in watchPaths so diff changes update the badge.
        let filePath = (repo as NSString).appendingPathComponent("new.txt")
        try "new file".write(toFile: filePath, atomically: true, encoding: .utf8)

        try await Task.sleep(for: .seconds(2))

        #expect(callbackFired.didFire)
    }

    // MARK: - Helpers

    final class CallbackTracker: @unchecked Sendable {
        private var _didFire = false
        var didFire: Bool { _didFire }
        func fire() { _didFire = true }
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-watcher-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)
        let readme = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readme, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial"], in: dir)
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
