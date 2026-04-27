import Testing
import Foundation
@testable import tian

// MARK: - Mock

@MainActor
final class MockWorkspaceProvider: WorkspaceProviding {
    var collections: [WorkspaceCollection] = []
    var keyWindowWorkspace: Workspace?

    var allWorkspaceCollections: [WorkspaceCollection] { collections }

    func activeWorkspaceForKeyWindow() -> Workspace? { keyWindowWorkspace }
}

// MARK: - Tests

@MainActor
struct WorktreeOrchestratorTests {

    // MARK: - Helpers

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
            throw OrchestratorTestError("git \(args.joined(separator: " ")) failed: \(msg)")
        }
    }

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-orch-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)

        let readmePath = (dir as NSString).appendingPathComponent("README.md")
        try "# Test".write(toFile: readmePath, atomically: true, encoding: .utf8)

        try runGitSync(["add", "."], in: dir)
        try runGitSync(["commit", "-m", "Initial commit"], in: dir)

        return dir
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func resolvePath(_ path: String) -> String {
        URL(filePath: path).resolvingSymlinksInPath().path
    }

    private func writeConfig(_ toml: String, in repoRoot: String) throws {
        let configDir = (repoRoot as NSString).appendingPathComponent(".tian")
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let configPath = (configDir as NSString).appendingPathComponent("config.toml")
        try toml.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    private func makeProvider(repoPath: String) -> (MockWorkspaceProvider, Workspace) {
        let collection = WorkspaceCollection(workingDirectory: repoPath)
        let workspace = collection.activeWorkspace!
        let provider = MockWorkspaceProvider()
        provider.collections = [collection]
        return (provider, workspace)
    }

    // MARK: - Create with config

    @Test func createWorktreeSpaceWithConfig() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Write config with copy rules and fast timeouts
        let envFile = (repo as NSString).appendingPathComponent(".env")
        try "DB_URL=localhost".write(toFile: envFile, atomically: true, encoding: .utf8)

        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 0.01

        [[copy]]
        source = ".env*"
        dest = "."
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "feature/test-config",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Verify result
        #expect(!result.existed)

        // Verify worktree directory exists on disk
        let expectedPath = (repo as NSString).appendingPathComponent(".worktrees/feature/test-config")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: expectedPath, isDirectory: &isDir))
        #expect(isDir.boolValue)

        // Verify Space was created in the collection
        let newSpace = workspace.spaceCollection.spaces.first(where: { $0.id == result.spaceID })
        #expect(newSpace != nil)
        #expect(newSpace?.name == "feature/test-config")
        #expect(newSpace?.worktreePath != nil)
        #expect(resolvePath(newSpace!.worktreePath!.path) == resolvePath(expectedPath))
        #expect(newSpace?.defaultWorkingDirectory != nil)

        // Verify .env was copied to worktree
        let copiedEnv = (expectedPath as NSString).appendingPathComponent(".env")
        #expect(FileManager.default.fileExists(atPath: copiedEnv))

        // Verify setupProgress is cleared
        #expect(orchestrator.setupProgress == nil)
    }

    // MARK: - Create without config

    @Test func createWorktreeSpaceWithoutConfig() async throws {
        let repo = try makeTempGitRepo()
        let repoName = URL(filePath: repo).lastPathComponent
        let centralBase = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".worktrees/\(repoName)")
        defer {
            cleanup(repo)
            cleanup(centralBase)
        }

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "no-config-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(!result.existed)

        // Default: ~/.worktrees/<repo-name>/<branch>
        let expectedPath = (centralBase as NSString).appendingPathComponent("no-config-branch")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: expectedPath, isDirectory: &isDir))
        #expect(isDir.boolValue)

        // Space has a single tab (no layout applied)
        let newSpace = workspace.spaceCollection.spaces.first(where: { $0.id == result.spaceID })
        #expect(newSpace != nil)
        #expect(newSpace?.tabs.count == 1)
        #expect(newSpace?.name == "no-config-branch")
    }

    // MARK: - Duplicate detection

    @Test func duplicateDetectionFocusesExisting() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // First creation
        let first = try await orchestrator.createWorktreeSpace(
            branchName: "dup-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        #expect(!first.existed)

        let spaceCountAfterFirst = workspace.spaceCollection.spaces.count

        // Second creation with same branch — should detect duplicate
        let second = try await orchestrator.createWorktreeSpace(
            branchName: "dup-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(second.existed)
        #expect(second.spaceID == first.spaceID)
        // No new Space should have been added
        #expect(workspace.spaceCollection.spaces.count == spaceCountAfterFirst)
    }

    // MARK: - Cancel setup

    @Test func cancelSetupSkipsRemainingCommands() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 30

        [[setup]]
        command = "sleep 30"

        [[setup]]
        command = "sleep 30"

        [[setup]]
        command = "sleep 30"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // Cancel once setupProgress shows the first command running.
        Task { @MainActor in
            for _ in 0..<300 {
                if orchestrator.setupProgress?.currentCommand?.hasPrefix("sleep") == true { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            orchestrator.cancelCommands()
        }

        let start = ContinuousClock.now
        let result = try await orchestrator.createWorktreeSpace(
            branchName: "cancel-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        let elapsed = ContinuousClock.now - start

        // Whole creation finishes well before any 30 s sleep would.
        #expect(elapsed < .seconds(5))
        #expect(!result.existed)
        #expect(orchestrator.setupProgress == nil)
    }

    // MARK: - SetupProgress lifecycle

    @Test func setupProgress_isNilBeforeAndAfterCreation() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 0.5

        [[setup]]
        command = "true"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        #expect(orchestrator.setupProgress == nil)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "lifecycle-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(orchestrator.setupProgress == nil)
        #expect(!result.existed)
    }

    @Test func setupProgress_carriesWorkspaceAndSpaceIDsDuringRun() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // A single command that blocks until the test releases it. While
        // blocked, we snapshot setupProgress and assert its IDs.
        let gate = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-setup-gate-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: gate) }

        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 5

        [[setup]]
        command = "while [ ! -f \(gate) ]; do sleep 0.02; done"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let observedSpaceIDBox = Box<UUID>()

        Task { @MainActor in
            // Wait for setupProgress to appear, snapshot, then release the gate.
            for _ in 0..<500 {
                if orchestrator.setupProgress != nil { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let observedWorkspaceID = orchestrator.setupProgress?.workspaceID
            let observedSpaceID = orchestrator.setupProgress?.spaceID
            let observedTotal = orchestrator.setupProgress?.totalCommands
            #expect(observedWorkspaceID == workspace.id)
            #expect(observedTotal == 1)
            // observedSpaceID is the new Space being created. We can't compare
            // it to a known UUID from this side (Space is created inside the
            // orchestrator), but we can assert it's non-nil and persist it
            // for the outer test to verify post-await.
            #expect(observedSpaceID != nil)
            observedSpaceIDBox.value = observedSpaceID
            FileManager.default.createFile(atPath: gate, contents: Data(), attributes: nil)
        }

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "ids-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(orchestrator.setupProgress == nil)
        #expect(result.spaceID == workspace.spaceCollection.spaces.first { $0.id == result.spaceID }?.id)

        let observedSpaceID = observedSpaceIDBox.value
        #expect(observedSpaceID == result.spaceID,
                "polling task should have observed the same Space ID that createWorktreeSpace returned")
    }

    @Test func setupProgress_recordsLastFailedIndex_whenCommandExitsNonZero() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Three commands; the middle one fails. We capture lastFailedIndex
        // mid-flight via a sentinel-blocked third command.
        let gate = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-fail-gate-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: gate) }

        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 5

        [[setup]]
        command = "true"

        [[setup]]
        command = "exit 7"

        [[setup]]
        command = "while [ ! -f \(gate) ]; do sleep 0.02; done"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        Task { @MainActor in
            // Always release the gate, even if the assertion fails — otherwise
            // the gated `while` command spins until setup_timeout (5 s) and
            // bloats the test's wall-clock time on slow CI.
            defer { FileManager.default.createFile(atPath: gate, contents: Data(), attributes: nil) }
            // Wait until both the third command is in flight (currentIndex == 2)
            // AND the failed exit from the second has been recorded.
            for _ in 0..<300 {
                if orchestrator.setupProgress?.currentIndex == 2,
                   orchestrator.setupProgress?.lastFailedIndex == 1 { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            #expect(orchestrator.setupProgress?.lastFailedIndex == 1)
        }

        _ = try await orchestrator.createWorktreeSpace(
            branchName: "fail-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        #expect(orchestrator.setupProgress == nil)
    }

    // MARK: - Remove worktree space

    @Test func removeWorktreeSpace() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // Create a worktree Space
        let result = try await orchestrator.createWorktreeSpace(
            branchName: "to-remove",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/to-remove")
        #expect(FileManager.default.fileExists(atPath: worktreePath))

        let spaceCountBefore = workspace.spaceCollection.spaces.count

        // Remove it
        try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID)

        // Worktree directory should be gone
        #expect(!FileManager.default.fileExists(atPath: worktreePath))

        // Space should be removed from collection
        #expect(workspace.spaceCollection.spaces.count == spaceCountBefore - 1)
        #expect(!workspace.spaceCollection.spaces.contains(where: { $0.id == result.spaceID }))
    }

    @Test func removeWorktreeSpace_runsArchiveCommands() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Drop a sentinel-stamping archive command. We pick a path
        // OUTSIDE the worktree so the file survives `git worktree remove`
        // and we can assert on it after the Space is gone.
        let sentinel = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-archive-sentinel-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: sentinel) }

        try writeConfig(
            """
            worktree_dir = ".worktrees"

            [[archive]]
            command = "pwd > \(sentinel.path)"
            """,
            in: repo
        )

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "archive-me",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/archive-me")
        // Capture the canonical (realpath) form BEFORE removal — `pwd`
        // inside the shell returns the canonical `/private/var/...`
        // path on macOS, but Foundation's path normalizers don't always
        // traverse the `/var` → `/private/var` symlink, so we lean on
        // libc's realpath here.
        let canonicalWorktree = realpath(worktreePath, nil).flatMap { ptr -> String? in
            defer { free(ptr) }
            return String(cString: ptr)
        } ?? worktreePath

        try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID)

        #expect(!FileManager.default.fileExists(atPath: worktreePath))
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
        let recordedCwd = try String(contentsOf: sentinel, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(recordedCwd == canonicalWorktree)
        #expect(!workspace.spaceCollection.spaces.contains(where: { $0.id == result.spaceID }))
    }

    @Test func removeWorktreeSpace_archiveFailureDoesNotBlockRemoval() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig(
            """
            worktree_dir = ".worktrees"

            [[archive]]
            command = "exit 1"
            """,
            in: repo
        )

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "archive-fails",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/archive-fails")
        try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID)

        #expect(!FileManager.default.fileExists(atPath: worktreePath))
        #expect(!workspace.spaceCollection.spaces.contains(where: { $0.id == result.spaceID }))
    }

    // MARK: - Remote ref

    @Test
    func createWorktreeSpace_withRemoteRef_skipsBranchExistsPreflight() async throws {
        // Seed a remote with a branch, clone it — the branch only exists as origin/feat/r in the clone.
        let remote = try makeTempGitRepo()
        defer { cleanup(remote) }
        try runGitSync(["branch", "feat/r"], in: remote)

        let clone = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-orch-clone-\(UUID().uuidString)").path
        let cloneCentralBase = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".worktrees/\(URL(filePath: clone).lastPathComponent)")
        defer {
            cleanup(clone)
            cleanup(cloneCentralBase)
        }
        try runGitSync(["clone", remote, clone], in: FileManager.default.temporaryDirectory.path)

        let (provider, workspace) = makeProvider(repoPath: clone)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "feat/r",
            existingBranch: true,
            remoteRef: "origin/feat/r",
            repoPath: clone,
            workspaceID: workspace.id
        )
        #expect(result.existed == false)
    }

    @Test
    func presentError_storesLastError() async {
        let (provider, _) = makeProvider(repoPath: "/tmp")
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)
        #expect(orchestrator.lastError == nil)

        orchestrator.presentError(
            WorktreeError.gitError(command: "test", stderr: "boom")
        )
        #expect(orchestrator.lastError != nil)
    }

    // MARK: - Remove with uncommitted changes + force

    @Test func removeWithUncommittedChangesAndForce() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "dirty-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Add an uncommitted file in the worktree
        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/dirty-branch")
        let dirtyFile = (worktreePath as NSString).appendingPathComponent("uncommitted.txt")
        try "dirty content".write(toFile: dirtyFile, atomically: true, encoding: .utf8)
        try runGitSync(["add", "uncommitted.txt"], in: worktreePath)

        // Remove without force should fail
        await #expect(throws: WorktreeError.self) {
            try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID, force: false)
        }

        // Space should still exist after failed removal
        #expect(workspace.spaceCollection.spaces.contains(where: { $0.id == result.spaceID }))

        // Remove with force should succeed
        try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID, force: true)

        #expect(!FileManager.default.fileExists(atPath: worktreePath))
        #expect(!workspace.spaceCollection.spaces.contains(where: { $0.id == result.spaceID }))
    }

    // MARK: - Pipe overflow

    @Test func setupCommands_withLargeOutput_doNotDeadlock() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Emit ~300 KB of stdout. With the old readDataToEndOfFile() drain,
        // the child blocks on a full pipe, terminationHandler never fires,
        // and we hit the timeout. With incremental drain, this completes
        // promptly under the 5 s timeout.
        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 5

        [[setup]]
        command = "yes hello | head -c 300000"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let start = ContinuousClock.now
        _ = try await orchestrator.createWorktreeSpace(
            branchName: "loud-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        let elapsed = ContinuousClock.now - start

        // Allow generous slack on busy CI; 4 s well below the 5 s timeout.
        #expect(elapsed < .seconds(4))
        #expect(orchestrator.setupProgress == nil)
    }

    // MARK: - SIGKILL escalation

    @Test func setupCommand_ignoringSIGTERM_isKilledViaSIGKILL_escalation() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // `trap '' TERM` sets SIGTERM disposition to SIG_IGN in the shell.
        // POSIX inherits SIG_IGN across exec, so the spawned `sleep` also
        // ignores SIGTERM. With the SIGTERM-only kill path, this command
        // would block until `setup_timeout`'s deadline and then continue
        // ignoring the signal — leaving the orchestrator hung. With the
        // SIGKILL escalation, the grace period elapses and SIGKILL (which
        // cannot be trapped) reaps the child.
        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 0.1
        setup_kill_grace = 0.2

        [[setup]]
        command = "trap '' TERM; sleep 30"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let start = ContinuousClock.now
        _ = try await orchestrator.createWorktreeSpace(
            branchName: "trap-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        let elapsed = ContinuousClock.now - start

        // Timeout (0.1) + grace (0.2) ≈ 0.3 s; allow generous slack for CI.
        // Pre-fix this would have hung on the 30 s sleep.
        #expect(elapsed < .seconds(3))
        #expect(orchestrator.setupProgress == nil)
    }

    // MARK: - Workspace ID targeting (Bug 1 regression)

    @Test func createWorktreeSpaceTargetsSpecifiedWorkspaceNotKeyWindow() async throws {
        let repoA = try makeTempGitRepo()
        let repoC = try makeTempGitRepo()
        let repoCName = URL(filePath: repoC).lastPathComponent
        let centralBaseC = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".worktrees/\(repoCName)")
        defer {
            cleanup(repoA)
            cleanup(repoC)
            cleanup(centralBaseC)
        }

        let collectionA = WorkspaceCollection(workingDirectory: repoA)
        let collectionC = WorkspaceCollection(workingDirectory: repoC)
        let workspaceA = collectionA.activeWorkspace!
        let workspaceC = collectionC.activeWorkspace!

        // Simulate the bug scenario: key window's active workspace is A, but we
        // target C explicitly via workspaceID. The new space must land in C.
        let provider = MockWorkspaceProvider()
        provider.collections = [collectionA, collectionC]
        provider.keyWindowWorkspace = workspaceA

        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "feature-c",
            existingBranch: false,
            repoPath: repoC,
            workspaceID: workspaceC.id
        )

        #expect(workspaceC.spaceCollection.spaces.contains { $0.id == result.spaceID })
        #expect(!workspaceA.spaceCollection.spaces.contains { $0.id == result.spaceID })
    }
}

private struct OrchestratorTestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private final class Box<T>: @unchecked Sendable {
    var value: T?
    init() {}
}
