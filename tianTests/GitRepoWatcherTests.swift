import Foundation
import os
import Testing
@testable import tian

struct GitRepoWatcherTests {

    // MARK: - Watch Path Resolution

    @Test func regularRepoWatchPaths() {
        let paths = GitRepoWatcher.resolveWatchPaths(for: RepoLocation(
            gitDir: ".git",
            commonDir: "/Users/dev/project/.git",
            workingTree: "/Users/dev/project",
            isWorktree: false
        ))
        #expect(paths == ["/Users/dev/project"])
    }

    @Test func worktreeWatchPathsIncludeWorkingTreeGitDirAndRefs() {
        let paths = GitRepoWatcher.resolveWatchPaths(for: RepoLocation(
            gitDir: "/Users/dev/project/.git/worktrees/feature-branch",
            commonDir: "/Users/dev/project/.git",
            workingTree: "/Users/dev/worktrees/feature-branch",
            isWorktree: true
        ))
        #expect(paths.count == 3)
        #expect(paths.contains("/Users/dev/worktrees/feature-branch"))
        #expect(paths.contains("/Users/dev/project/.git/worktrees/feature-branch"))
        #expect(paths.contains("/Users/dev/project/.git/refs"))
    }

    @Test func absoluteGitDirEndingWithDotGit() {
        let paths = GitRepoWatcher.resolveWatchPaths(for: RepoLocation(
            gitDir: "/Users/dev/project/.git",
            commonDir: "/Users/dev/project/.git",
            workingTree: "/Users/dev/project",
            isWorktree: false
        ))
        #expect(paths == ["/Users/dev/project"])
    }

    // MARK: - pathsAffectPRState

    @Test func pathsAffectPRStateTrueForRemoteRef() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [commonDir + "/refs/remotes/origin/main"]
        #expect(GitRepoWatcher.pathsAffectPRState(paths, canonicalCommonDir: commonDir))
    }

    @Test func pathsAffectPRStateTrueForPackedRefs() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [commonDir + "/packed-refs"]
        #expect(GitRepoWatcher.pathsAffectPRState(paths, canonicalCommonDir: commonDir))
    }

    @Test func pathsAffectPRStateFalseForLocalHeadMove() {
        let commonDir = "/Users/dev/project/.git"
        // `git commit` bumps refs/heads/<branch> but doesn't change the remote
        // PR state, so we shouldn't evict the PR cache on every commit.
        let paths = [commonDir + "/refs/heads/feature"]
        #expect(!GitRepoWatcher.pathsAffectPRState(paths, canonicalCommonDir: commonDir))
    }

    @Test func pathsAffectPRStateFalseForIndexWrite() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [commonDir + "/index", "/Users/dev/project/src/app.swift"]
        #expect(!GitRepoWatcher.pathsAffectPRState(paths, canonicalCommonDir: commonDir))
    }

    @Test func pathsAffectPRStateTrueWhenBatchMixesRefsAndIndex() {
        let commonDir = "/Users/dev/project/.git"
        let paths = [
            commonDir + "/index",
            commonDir + "/refs/remotes/origin/feature",
        ]
        #expect(GitRepoWatcher.pathsAffectPRState(paths, canonicalCommonDir: commonDir))
    }

    // MARK: - Lifecycle

    @Test func watcherCanBeCreatedAndTornDown() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let watcher = GitRepoWatcher(
            watchPaths: [repo + "/.git"],
            onChangeDetected: { _ in }
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
            onChangeDetected: { _ in callbackFired.fire() }
        )
        defer { watcher.stop() }

        // Modify a file and stage it to change .git/index
        let filePath = (repo as NSString).appendingPathComponent("test.txt")
        try "change".write(toFile: filePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "test.txt"], in: repo)

        try await waitForCallback(callbackFired)
        #expect(callbackFired.didFire)
    }

    @Test func watcherDetectsWorkingTreeFileChanges() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let paths = GitRepoWatcher.resolveWatchPaths(for: RepoLocation(
            gitDir: ".git",
            commonDir: repo + "/.git",
            workingTree: repo,
            isWorktree: false
        ))

        let callbackFired = CallbackTracker()
        let watcher = GitRepoWatcher(
            watchPaths: paths,
            latency: 0.5,
            onChangeDetected: { _ in callbackFired.fire() }
        )
        defer { watcher.stop() }

        // Untracked file write — does not touch .git, so a .git-only watcher would miss it.
        let filePath = (repo as NSString).appendingPathComponent("new.txt")
        try "new file".write(toFile: filePath, atomically: true, encoding: .utf8)

        try await waitForCallback(callbackFired)
        #expect(callbackFired.didFire)
    }

    @Test func watcherReportsEventPathsForRemoteRefWrite() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // FSEvents reports `/private/var/...` while `repo` is `/var/...`;
        // canonicalize so the prefix check matches.
        let commonDir = GitRepoWatcher.canonicalizedPath(repo + "/.git")
        let paths = GitRepoWatcher.resolveWatchPaths(for: RepoLocation(
            gitDir: ".git",
            commonDir: commonDir,
            workingTree: repo,
            isWorktree: false
        ))

        let recorder = PathRecorder()
        let watcher = GitRepoWatcher(
            watchPaths: paths,
            latency: 0.5,
            onChangeDetected: { received in recorder.record(received) }
        )
        defer { watcher.stop() }

        // Simulate `git push` updating a remote ref without invoking the network.
        let remoteRefDir = commonDir + "/refs/remotes/origin"
        try FileManager.default.createDirectory(
            atPath: remoteRefDir, withIntermediateDirectories: true)
        let remoteRef = remoteRefDir + "/main"
        try "0000000000000000000000000000000000000000\n"
            .write(toFile: remoteRef, atomically: true, encoding: .utf8)

        try await waitForCondition {
            GitRepoWatcher.pathsAffectPRState(recorder.paths, canonicalCommonDir: commonDir)
        }
        #expect(GitRepoWatcher.pathsAffectPRState(recorder.paths, canonicalCommonDir: commonDir))
    }

    // MARK: - Helpers

    /// Polls the tracker until it fires or `timeout` elapses. Using a deadline
    /// instead of a fixed sleep keeps the suite fast on dev machines while
    /// giving slower CI boxes headroom for FSEvents delivery latency.
    private func waitForCallback(
        _ tracker: CallbackTracker,
        timeout: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(50)
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !tracker.didFire, ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }
    }

    /// Polls `condition` until it returns true or `timeout` elapses.
    private func waitForCondition(
        timeout: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(50),
        _ condition: @Sendable () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }
    }

    /// Synchronized flag used to bridge a callback fired on the FSEvents
    /// dispatch queue to the test task reading on the main task.
    final class CallbackTracker: Sendable {
        private let state = OSAllocatedUnfairLock<Bool>(initialState: false)
        var didFire: Bool { state.withLock { $0 } }
        func fire() { state.withLock { $0 = true } }
    }

    /// Thread-safe accumulator for paths reported by the watcher across batches.
    final class PathRecorder: Sendable {
        private let state = OSAllocatedUnfairLock<[String]>(initialState: [])
        var paths: [String] { state.withLock { $0 } }
        func record(_ received: [String]) {
            state.withLock { $0.append(contentsOf: received) }
        }
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
