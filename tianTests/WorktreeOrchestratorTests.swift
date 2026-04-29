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

    // Regression for the setup-shell interactivity fix in
    // WorktreeOrchestrator.runCommandOffMain. POSIX: $- contains 'i' iff
    // the shell is interactive — touch a marker file only in that case
    // and assert it exists.
    @Test func setupCommands_runInInteractiveShell() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-interactive-\(UUID().uuidString).flag").path
        defer { try? FileManager.default.removeItem(atPath: marker) }

        // Generous timeout: interactive zsh startup (.zshrc + plugins like
        // p10k, gitstatus, nvm) can take several seconds on heavy configs.
        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01
        setup_timeout = 30

        [[setup]]
        command = "case $- in *i*) touch '\(marker)';; esac"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        _ = try await orchestrator.createWorktreeSpace(
            branchName: "interactive-shell-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(FileManager.default.fileExists(atPath: marker),
                "setup command did not see an interactive shell ($- lacked 'i') — `-i` flag may have been removed from WorktreeOrchestrator shell args")
    }

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

    // MARK: - Archive close flow (FR-007, FR-010-013, FR-040-041, FR-050-053)

    /// Polls `setupProgress` on the main actor at ~5ms intervals while the
    /// supplied async operation runs, capturing every distinct phase that
    /// passes through. Stops as soon as the operation returns.
    @MainActor
    private func observingProgressPhases<T>(
        on orchestrator: WorktreeOrchestrator,
        during operation: () async throws -> T
    ) async rethrows -> (T, [SetupProgress.Phase]) {
        let phasesBox = Box<[SetupProgress.Phase]>()
        phasesBox.value = []
        let stopBox = Box<Bool>()
        stopBox.value = false

        let pollerTask = Task { @MainActor in
            while stopBox.value == false {
                if let snapshot = orchestrator.setupProgress {
                    var current = phasesBox.value ?? []
                    if current.last != snapshot.phase {
                        current.append(snapshot.phase)
                        phasesBox.value = current
                    }
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        do {
            let result = try await operation()
            stopBox.value = true
            _ = await pollerTask.value
            return (result, phasesBox.value ?? [])
        } catch {
            stopBox.value = true
            _ = await pollerTask.value
            throw error
        }
    }

    /// FR-007, FR-010, FR-011: archive flow publishes phase=.cleanup and the
    /// per-command progress index advances 0→1 with 2 archive commands.
    @Test func archiveFlowPublishesCleanupPhase() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig(
            """
            worktree_dir = ".worktrees"

            [[archive]]
            command = "echo one"

            [[archive]]
            command = "echo two"
            """,
            in: repo
        )

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "cleanup-flow",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Capture every distinct phase observed while removeWorktreeSpace runs.
        let (_, phases) = try await observingProgressPhases(on: orchestrator) {
            try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID)
        }

        #expect(phases.contains(.cleanup))
        #expect(orchestrator.setupProgress == nil)
        // Space should be gone (clean archive success path).
        #expect(!workspace.spaceCollection.spaces.contains(where: { $0.id == result.spaceID }))
    }

    /// FR-040, FR-041, FR-050: archive failure halts the cleanup pipeline,
    /// the worktree directory stays on disk, the Space stays open, and
    /// setupProgress is nil after the call returns.
    @Test func archiveFailureHaltsPipeline() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig(
            """
            worktree_dir = ".worktrees"

            [[archive]]
            command = "false"
            """,
            in: repo
        )

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "archive-halt",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/archive-halt")
        // The orchestrator must NOT throw on archive failure — failure is
        // captured via setupProgress.lastFailedIndex and the linger-capsule.
        try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID)

        // Worktree directory still on disk.
        #expect(FileManager.default.fileExists(atPath: worktreePath))
        // Space still in the collection.
        #expect(workspace.spaceCollection.spaces.contains(where: { $0.id == result.spaceID }))
        // setupProgress nil after call.
        #expect(orchestrator.setupProgress == nil)
    }

    /// FR-040, FR-041: user cancel during archive halts the pipeline before
    /// `git worktree remove`. Worktree and Space are preserved.
    @Test func userCancelDuringArchivePreservesWorktree() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig(
            """
            worktree_dir = ".worktrees"

            [[archive]]
            command = "sleep 5"
            """,
            in: repo
        )

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "archive-cancel",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/archive-cancel")

        // Launch the cancel after the archive command has begun.
        Task { @MainActor in
            for _ in 0..<300 {
                if orchestrator.setupProgress?.currentCommand?.hasPrefix("sleep") == true { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            orchestrator.cancelCommands()
        }

        let start = ContinuousClock.now
        try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID)
        let elapsed = ContinuousClock.now - start

        // Should return well before the 5s sleep completes.
        #expect(elapsed < .seconds(4))
        // Worktree directory preserved on disk.
        #expect(FileManager.default.fileExists(atPath: worktreePath))
        // Space preserved.
        #expect(workspace.spaceCollection.spaces.contains(where: { $0.id == result.spaceID }))
        // setupProgress nil after call.
        #expect(orchestrator.setupProgress == nil)
    }

    /// FR-012, FR-022: when no archive commands are configured, the
    /// orchestrator briefly publishes phase=.removing while `git worktree
    /// remove` + pruning run.
    @Test func noArchiveCaseShowsRemovingPhase() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // No archive section.
        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "no-archive",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let (_, phases) = try await observingProgressPhases(on: orchestrator) {
            try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID)
        }

        #expect(phases.contains(.removing))
        // Cleanup phase must NOT appear when there are no archive commands.
        #expect(!phases.contains(.cleanup))
        #expect(orchestrator.setupProgress == nil)
    }

    /// FR-053: when `git worktree remove` throws WorktreeError.uncommittedChanges
    /// after archive succeeds, the orchestrator must nil setupProgress
    /// synchronously (on the MainActor) before the throw, so the modal
    /// alert never overlaps with the progress capsule.
    @Test func setupProgressNilOnUncommittedChanges() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig(
            """
            worktree_dir = ".worktrees"

            [[archive]]
            command = "true"
            """,
            in: repo
        )

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "uncommitted-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Add uncommitted index changes inside the worktree to force
        // `git worktree remove` to fail with .uncommittedChanges.
        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/uncommitted-branch")
        let dirtyFile = (worktreePath as NSString).appendingPathComponent("uncommitted.txt")
        try "dirty content".write(toFile: dirtyFile, atomically: true, encoding: .utf8)
        try runGitSync(["add", "uncommitted.txt"], in: worktreePath)

        // Expect uncommittedChanges thrown; check setupProgress is nil at
        // the catch site.
        var caughtUncommitted = false
        do {
            try await orchestrator.removeWorktreeSpace(spaceID: result.spaceID, force: false)
        } catch let error as WorktreeError {
            if case .uncommittedChanges = error {
                caughtUncommitted = true
            }
            // FR-053: setupProgress must be nil at the moment the alert
            // would consume the thrown error.
            #expect(orchestrator.setupProgress == nil)
        }
        #expect(caughtUncommitted)
        #expect(orchestrator.setupProgress == nil)
        // Space and worktree still preserved (uncommitted changes were
        // not force-removed).
        #expect(workspace.spaceCollection.spaces.contains(where: { $0.id == result.spaceID }))
        #expect(FileManager.default.fileExists(atPath: worktreePath))
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

    // MARK: - In-flight guard (FR-061)

    /// FR-061: Concurrent `removeWorktreeSpace` on a *different* Space is
    /// rejected with `WorktreeError.closeInFlight` while the first removal
    /// is still in flight.
    @Test func concurrentCloseOnDifferentSpaceIsRejected() async throws {
        let repoA = try makeTempGitRepo()
        let repoB = try makeTempGitRepo()
        defer {
            cleanup(repoA)
            cleanup(repoB)
        }

        // Space A: configure a slow archive command so the first removal
        // stays in flight long enough for the second call to race.
        try writeConfig(
            """
            worktree_dir = ".worktrees"
            setup_timeout = 10

            [[archive]]
            command = "sleep 5"
            """,
            in: repoA
        )
        // Space B: no archive commands — fast removal so the in-flight
        // guard is the only thing stopping it.
        try writeConfig("worktree_dir = \".worktrees\"", in: repoB)

        // Both Spaces live in the same orchestrator / provider.
        let collectionA = WorkspaceCollection(workingDirectory: repoA)
        let collectionB = WorkspaceCollection(workingDirectory: repoB)
        let workspaceA = collectionA.activeWorkspace!
        let workspaceB = collectionB.activeWorkspace!

        let provider = MockWorkspaceProvider()
        provider.collections = [collectionA, collectionB]
        provider.keyWindowWorkspace = workspaceA

        let orch = WorktreeOrchestrator(workspaceProvider: provider)

        // Create both worktree Spaces first.
        let resultA = try await orch.createWorktreeSpace(
            branchName: "close-guard-a",
            repoPath: repoA,
            workspaceID: workspaceA.id
        )
        let resultB = try await orch.createWorktreeSpace(
            branchName: "close-guard-b",
            repoPath: repoB,
            workspaceID: workspaceB.id
        )

        // Cancel Space A's slow archive command after it starts, so the
        // test doesn't hang for 5 s.
        let cancelTask = Task { @MainActor in
            for _ in 0..<500 {
                if orch.isCloseInFlight { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            orch.cancelCommands()
        }

        // Start Space A removal in background — it will block on `sleep 5`.
        let removeATask = Task { @MainActor in
            try await orch.removeWorktreeSpace(spaceID: resultA.spaceID)
        }

        // Wait until the in-flight guard is raised.
        for _ in 0..<500 {
            if orch.isCloseInFlight { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(orch.isCloseInFlight, "isCloseInFlight should be true while Space A removal is running")

        // Attempt to remove Space B while Space A removal is still in flight.
        var caughtCloseInFlight = false
        do {
            try await orch.removeWorktreeSpace(spaceID: resultB.spaceID)
        } catch WorktreeError.closeInFlight {
            caughtCloseInFlight = true
        }
        #expect(caughtCloseInFlight, "Expected WorktreeError.closeInFlight when removing a different Space concurrently")

        // Let Space A's removal finish (cancel already signalled above).
        _ = await cancelTask.value
        _ = try? await removeATask.value

        // After both calls complete, the guard must be cleared.
        #expect(!orch.isCloseInFlight, "isCloseInFlight should be false after all removals complete")
    }

    /// `isCloseInFlight` is cleared via defer even when `removeWorktreeSpace`
    /// returns normally (success path).
    @Test func isCloseInFlight_isClearedOnSuccess() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orch = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orch.createWorktreeSpace(
            branchName: "inflight-success",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(!orch.isCloseInFlight)
        try await orch.removeWorktreeSpace(spaceID: result.spaceID)
        #expect(!orch.isCloseInFlight)
    }

    /// `isCloseInFlight` is cleared via defer even when `removeWorktreeSpace`
    /// throws (error path, e.g. uncommittedChanges).
    @Test func isCloseInFlight_isClearedOnFailure() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orch = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orch.createWorktreeSpace(
            branchName: "inflight-failure",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Dirty the worktree so removal throws.
        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/inflight-failure")
        let dirtyFile = (worktreePath as NSString).appendingPathComponent("dirty.txt")
        try "dirty".write(toFile: dirtyFile, atomically: true, encoding: .utf8)
        try runGitSync(["add", "dirty.txt"], in: worktreePath)

        #expect(!orch.isCloseInFlight)
        do {
            try await orch.removeWorktreeSpace(spaceID: result.spaceID, force: false)
        } catch WorktreeError.uncommittedChanges {
            // expected
        }
        #expect(!orch.isCloseInFlight, "isCloseInFlight should be false after a throwing removal")
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
