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

    /// Runs git and returns trimmed stdout (for assertions like `rev-parse HEAD`).
    /// Reuses the shared `WorktreeServiceTestsRunner` git runner.
    private func gitOutput(_ args: [String], in dir: String) async throws -> String {
        let result = try await WorktreeServiceTestsRunner.run(args, in: dir)
        guard result.exitCode == 0 else {
            throw OrchestratorTestError("git \(args.joined(separator: " ")) failed: \(result.stderr)")
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
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

    @Test func createWorktreeSessionWithConfig() async throws {
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

        let result = try await orchestrator.createWorktreeSession(
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

        // Verify Session was created in the collection
        let newSession = workspace.sessionCollection.sessions.first(where: { $0.id == result.sessionID })
        #expect(newSession != nil)
        #expect(newSession?.customName == "feature/test-config")
        #expect(newSession?.worktreePath != nil)
        #expect(resolvePath(newSession!.worktreePath!.path) == resolvePath(expectedPath))
        #expect(newSession?.defaultWorkingDirectory != nil)

        // Verify .env was copied to worktree
        let copiedEnv = (expectedPath as NSString).appendingPathComponent(".env")
        #expect(FileManager.default.fileExists(atPath: copiedEnv))

        // Verify setupProgress is cleared
        #expect(orchestrator.setupProgress == nil)
    }

    // MARK: - Create without config

    @Test func createWorktreeSessionWithoutConfig() async throws {
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

        let result = try await orchestrator.createWorktreeSession(
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

        // Session has a live Claude pane and a single-pane terminal panel
        // (no layout applied → the terminal panel is never split).
        let newSession = workspace.sessionCollection.sessions.first(where: { $0.id == result.sessionID })
        #expect(newSession != nil)
        #expect(newSession?.customName == "no-config-branch")
        #expect(newSession?.claudePane != nil)
        #expect(newSession?.terminalPanel?.splitTree.leafCount == 1)
    }

    // MARK: - Layout targets the terminal panel

    /// A `[[layout]]` split lands in the splittable terminal panel — never the
    /// Claude pane. The Claude pane stays a single leaf; the terminal panel
    /// grows to the layout's pane count.
    @Test func applyLayoutSplitsLandInTerminalPanel() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // A single vertical split with two empty panes (no commands → no shell
        // readiness wait). Two terminal panes expected after creation.
        try writeConfig("""
        worktree_dir = ".worktrees"
        shell_ready_delay = 0.01

        [layout]
        direction = "vertical"
        ratio = 0.5

        [layout.first]

        [layout.second]
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSession(
            branchName: "layout-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let newSession = workspace.sessionCollection.sessions.first(where: { $0.id == result.sessionID })
        #expect(newSession != nil)
        // Split landed in the terminal panel (2 leaves)…
        #expect(newSession?.terminalPanel?.splitTree.leafCount == 2)
        // …and the Claude pane stayed a single, unsplittable leaf.
        #expect(newSession?.claudePane?.splitTree.leafCount == 1)
        #expect(newSession?.claudePane?.allowsSplits == false)
    }

    // MARK: - Duplicate detection

    @Test func duplicateDetectionFocusesExisting() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // First creation
        let first = try await orchestrator.createWorktreeSession(
            branchName: "dup-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        #expect(!first.existed)

        let sessionCountAfterFirst = workspace.sessionCollection.sessions.count

        // Second creation with same branch — should detect duplicate
        let second = try await orchestrator.createWorktreeSession(
            branchName: "dup-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(second.existed)
        #expect(second.sessionID == first.sessionID)
        // Duplicate detection returns the existing Session's pane ids.
        #expect(second.claudePaneID == first.claudePaneID)
        #expect(second.terminalPaneID == first.terminalPaneID)
        // No new Session should have been added
        #expect(workspace.sessionCollection.sessions.count == sessionCountAfterFirst)
    }

    @Test func duplicateDetectionBackgroundDoesNotActivate() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // First creation (foreground) activates the new worktree Session.
        let first = try await orchestrator.createWorktreeSession(
            branchName: "dup-bg-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        #expect(!first.existed)

        // Move focus to a different Session so a stray activation would be observable.
        let otherSessionID = workspace.sessionCollection.sessions
            .first(where: { $0.id != first.sessionID })?.id
        #expect(otherSessionID != nil)
        workspace.sessionCollection.activeSessionID = otherSessionID!

        let sessionCountAfterFirst = workspace.sessionCollection.sessions.count

        // Second creation with same branch + background — duplicate detected,
        // must NOT steal focus from the currently active Session.
        let second = try await orchestrator.createWorktreeSession(
            branchName: "dup-bg-branch",
            repoPath: repo,
            workspaceID: workspace.id,
            background: true
        )

        #expect(second.existed)
        #expect(second.sessionID == first.sessionID)
        #expect(workspace.sessionCollection.sessions.count == sessionCountAfterFirst)
        // Background opt-out: active Session stays put instead of jumping to the worktree.
        #expect(workspace.sessionCollection.activeSessionID == otherSessionID)
    }

    @Test func newSessionBackgroundDoesNotStealFocus() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // Stay in whatever Session is active before creating the worktree.
        let originalActiveSessionID = workspace.sessionCollection.activeSessionID

        // Create a brand-new worktree Session in the background.
        let result = try await orchestrator.createWorktreeSession(
            branchName: "bg-new-branch",
            repoPath: repo,
            workspaceID: workspace.id,
            background: true
        )

        #expect(!result.existed)
        #expect(result.sessionID != originalActiveSessionID)
        // Background opt-out: the active Session must not jump to the new worktree.
        #expect(workspace.sessionCollection.activeSessionID == originalActiveSessionID)

        let newSession = workspace.sessionCollection.sessions.first(where: { $0.id == result.sessionID })
        #expect(newSession != nil)
        // showTerminal(background:) must leave focus on the Claude area rather than
        // flipping to .terminal — flipping pulls the terminal surface's first responder
        // and steals the window key, which is the focus-steal this guards against.
        #expect(newSession?.focusedArea == .claude)

        // The worktree still exposes both its terminal pane and its Claude pane.
        #expect(result.terminalPaneID != nil)
        #expect(result.claudePaneID != nil)
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
        let result = try await orchestrator.createWorktreeSession(
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

        _ = try await orchestrator.createWorktreeSession(
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

        let result = try await orchestrator.createWorktreeSession(
            branchName: "lifecycle-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(orchestrator.setupProgress == nil)
        #expect(!result.existed)
    }

    @Test func setupProgress_carriesWorkspaceAndSessionIDsDuringRun() async throws {
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

        let observedSessionIDBox = Box<UUID>()

        Task { @MainActor in
            // Wait for setupProgress to appear, snapshot, then release the gate.
            for _ in 0..<500 {
                if orchestrator.setupProgress != nil { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            let observedWorkspaceID = orchestrator.setupProgress?.workspaceID
            let observedSessionID = orchestrator.setupProgress?.sessionID
            let observedTotal = orchestrator.setupProgress?.totalCommands
            #expect(observedWorkspaceID == workspace.id)
            #expect(observedTotal == 1)
            // observedSessionID is the new Session being created. We can't compare
            // it to a known UUID from this side (Session is created inside the
            // orchestrator), but we can assert it's non-nil and persist it
            // for the outer test to verify post-await.
            #expect(observedSessionID != nil)
            observedSessionIDBox.value = observedSessionID
            FileManager.default.createFile(atPath: gate, contents: Data(), attributes: nil)
        }

        let result = try await orchestrator.createWorktreeSession(
            branchName: "ids-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(orchestrator.setupProgress == nil)
        #expect(result.sessionID == workspace.sessionCollection.sessions.first { $0.id == result.sessionID }?.id)

        let observedSessionID = observedSessionIDBox.value
        #expect(observedSessionID == result.sessionID,
                "polling task should have observed the same Session ID that createWorktreeSession returned")
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

        _ = try await orchestrator.createWorktreeSession(
            branchName: "fail-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )
        #expect(orchestrator.setupProgress == nil)
    }

    // MARK: - Remove worktree session

    @Test func removeWorktreeSession() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // Create a worktree Session
        let result = try await orchestrator.createWorktreeSession(
            branchName: "to-remove",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/to-remove")
        #expect(FileManager.default.fileExists(atPath: worktreePath))

        let sessionCountBefore = workspace.sessionCollection.sessions.count

        // Remove it
        try await orchestrator.removeWorktreeSession(sessionID: result.sessionID)

        // Worktree directory should be gone
        #expect(!FileManager.default.fileExists(atPath: worktreePath))

        // Session should be removed from collection
        #expect(workspace.sessionCollection.sessions.count == sessionCountBefore - 1)
        #expect(!workspace.sessionCollection.sessions.contains(where: { $0.id == result.sessionID }))
    }

    @Test func removeWorktreeSession_runsArchiveCommands() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Drop a sentinel-stamping archive command. We pick a path
        // OUTSIDE the worktree so the file survives `git worktree remove`
        // and we can assert on it after the Session is gone.
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

        let result = try await orchestrator.createWorktreeSession(
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

        try await orchestrator.removeWorktreeSession(sessionID: result.sessionID)

        #expect(!FileManager.default.fileExists(atPath: worktreePath))
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
        let recordedCwd = try String(contentsOf: sentinel, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(recordedCwd == canonicalWorktree)
        #expect(!workspace.sessionCollection.sessions.contains(where: { $0.id == result.sessionID }))
    }

    // MARK: - Remove with --delete-branch

    @Test func removeWorktreeSession_keepsBranchByDefault() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSession(
            branchName: "keep-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Default removal (no deleteBranch) must leave the branch in place.
        let removal = try await orchestrator.removeWorktreeSession(sessionID: result.sessionID)

        #expect(removal.branchName == nil)
        #expect(!removal.branchDeleted)
        let exists = try await WorktreeService.branchExists(
            repoRoot: repo, branchName: "keep-branch"
        )
        #expect(exists)
    }

    @Test func removeWorktreeSession_deleteBranch_removesMergedBranch() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // A fresh worktree branch has no commits beyond HEAD — it's merged,
        // so `git branch -d` deletes it without --force.
        let result = try await orchestrator.createWorktreeSession(
            branchName: "del-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/del-branch")
        let removal = try await orchestrator.removeWorktreeSession(
            sessionID: result.sessionID, deleteBranch: true
        )

        #expect(removal.branchName == "del-branch")
        #expect(removal.branchDeleted)
        #expect(removal.branchKeptReason == nil)
        #expect(!FileManager.default.fileExists(atPath: worktreePath))
        let exists = try await WorktreeService.branchExists(
            repoRoot: repo, branchName: "del-branch"
        )
        #expect(!exists)
    }

    @Test func removeWorktreeSession_deleteBranch_keepsUnmergedAndStillRemovesWorktree() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSession(
            branchName: "unmerged-wt",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Commit a change inside the worktree so the branch carries work not
        // reachable from the main HEAD. The working tree stays clean, so
        // `git worktree remove` still succeeds without --force.
        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/unmerged-wt")
        let change = (worktreePath as NSString).appendingPathComponent("change.txt")
        try "change".write(toFile: change, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: worktreePath)
        try runGitSync(["commit", "-m", "unmerged work"], in: worktreePath)

        let removal = try await orchestrator.removeWorktreeSession(
            sessionID: result.sessionID, deleteBranch: true
        )

        // The worktree (primary action) is removed and the Session is gone…
        #expect(!FileManager.default.fileExists(atPath: worktreePath))
        #expect(!workspace.sessionCollection.sessions.contains(where: { $0.id == result.sessionID }))
        // …but the unmerged branch is kept because --force was not passed.
        #expect(removal.branchName == "unmerged-wt")
        #expect(!removal.branchDeleted)
        #expect(removal.branchKeptReason == "unmerged")
        let exists = try await WorktreeService.branchExists(
            repoRoot: repo, branchName: "unmerged-wt"
        )
        #expect(exists)
    }

    @Test func removeWorktreeSession_deleteBranch_force_removesUnmergedBranch() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSession(
            branchName: "force-del-wt",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Commit unmerged work inside the worktree. The tree stays clean, so
        // `git worktree remove` needs no force; force only upgrades the branch
        // delete from `-d` to `-D`.
        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/force-del-wt")
        let change = (worktreePath as NSString).appendingPathComponent("change.txt")
        try "change".write(toFile: change, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: worktreePath)
        try runGitSync(["commit", "-m", "unmerged work"], in: worktreePath)

        // force: true must thread through to `git branch -D`, deleting the
        // unmerged branch the safe `-d` would have kept.
        let removal = try await orchestrator.removeWorktreeSession(
            sessionID: result.sessionID, force: true, deleteBranch: true
        )

        #expect(removal.branchName == "force-del-wt")
        #expect(removal.branchDeleted)
        #expect(removal.branchKeptReason == nil)
        let exists = try await WorktreeService.branchExists(
            repoRoot: repo, branchName: "force-del-wt"
        )
        #expect(!exists)
    }

    @Test func removeWorktreeSession_deleteBranch_detachedHead_skipsBranchDelete() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSession(
            branchName: "detach-wt",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Detach HEAD inside the worktree so it no longer owns a branch. The
        // branch ref itself survives detaching.
        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/detach-wt")
        try runGitSync(["checkout", "--detach"], in: worktreePath)

        let removal = try await orchestrator.removeWorktreeSession(
            sessionID: result.sessionID, deleteBranch: true
        )

        // Worktree removed, but no branch is deleted — we never guess a name
        // from the (renamable) Session, so the branch is left intact.
        #expect(!FileManager.default.fileExists(atPath: worktreePath))
        #expect(removal.branchName == nil)
        #expect(!removal.branchDeleted)
        #expect(removal.branchKeptReason == "no branch")
        let exists = try await WorktreeService.branchExists(
            repoRoot: repo, branchName: "detach-wt"
        )
        #expect(exists)
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

        let result = try await orchestrator.createWorktreeSession(
            branchName: "cleanup-flow",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Capture every distinct phase observed while removeWorktreeSession runs.
        let (_, phases) = try await observingProgressPhases(on: orchestrator) {
            try await orchestrator.removeWorktreeSession(sessionID: result.sessionID)
        }

        #expect(phases.contains(.cleanup))
        #expect(orchestrator.setupProgress == nil)
        // Session should be gone (clean archive success path).
        #expect(!workspace.sessionCollection.sessions.contains(where: { $0.id == result.sessionID }))
    }

    /// FR-040, FR-041, FR-050: archive failure halts the cleanup pipeline,
    /// the worktree directory stays on disk, the Session stays open, and
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

        let result = try await orchestrator.createWorktreeSession(
            branchName: "archive-halt",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/archive-halt")
        // The orchestrator must NOT throw on archive failure — failure is
        // captured via setupProgress.lastFailedIndex and the linger-capsule.
        try await orchestrator.removeWorktreeSession(sessionID: result.sessionID)

        // Worktree directory still on disk.
        #expect(FileManager.default.fileExists(atPath: worktreePath))
        // Session still in the collection.
        #expect(workspace.sessionCollection.sessions.contains(where: { $0.id == result.sessionID }))
        // setupProgress nil after call.
        #expect(orchestrator.setupProgress == nil)
    }

    /// FR-040, FR-041: user cancel during archive halts the pipeline before
    /// `git worktree remove`. Worktree and Session are preserved.
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

        let result = try await orchestrator.createWorktreeSession(
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
        try await orchestrator.removeWorktreeSession(sessionID: result.sessionID)
        let elapsed = ContinuousClock.now - start

        // Should return well before the 5s sleep completes.
        #expect(elapsed < .seconds(4))
        // Worktree directory preserved on disk.
        #expect(FileManager.default.fileExists(atPath: worktreePath))
        // Session preserved.
        #expect(workspace.sessionCollection.sessions.contains(where: { $0.id == result.sessionID }))
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

        let result = try await orchestrator.createWorktreeSession(
            branchName: "no-archive",
            repoPath: repo,
            workspaceID: workspace.id
        )

        let (_, phases) = try await observingProgressPhases(on: orchestrator) {
            try await orchestrator.removeWorktreeSession(sessionID: result.sessionID)
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

        let result = try await orchestrator.createWorktreeSession(
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
            try await orchestrator.removeWorktreeSession(sessionID: result.sessionID, force: false)
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
        // Session and worktree still preserved (uncommitted changes were
        // not force-removed).
        #expect(workspace.sessionCollection.sessions.contains(where: { $0.id == result.sessionID }))
        #expect(FileManager.default.fileExists(atPath: worktreePath))
    }

    // MARK: - Remote ref

    @Test
    func createWorktreeSession_withRemoteRef_skipsBranchExistsPreflight() async throws {
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

        let result = try await orchestrator.createWorktreeSession(
            branchName: "feat/r",
            existingBranch: true,
            remoteRef: "origin/feat/r",
            repoPath: clone,
            workspaceID: workspace.id
        )
        #expect(result.existed == false)
    }

    // MARK: - Base ref

    @Test
    func createWorktreeSession_withBaseRef_branchesFromBase() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        // Capture the initial commit (the base), then advance HEAD.
        let baseSHA = try await gitOutput(["rev-parse", "HEAD"], in: repo)
        let secondFile = (repo as NSString).appendingPathComponent("second.txt")
        try "second".write(toFile: secondFile, atomically: true, encoding: .utf8)
        try runGitSync(["add", "."], in: repo)
        try runGitSync(["commit", "-m", "Second commit"], in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSession(
            branchName: "feature/from-base",
            base: baseSHA,
            repoPath: repo,
            workspaceID: workspace.id
        )
        #expect(!result.existed)

        // The new worktree's HEAD must equal the base commit, not repo HEAD.
        let worktreePath = (repo as NSString).appendingPathComponent(".worktrees/feature/from-base")
        let worktreeHEAD = try await gitOutput(["rev-parse", "HEAD"], in: worktreePath)
        #expect(worktreeHEAD == baseSHA)
    }

    @Test
    func createWorktreeSession_baseWithExisting_throws() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)
        try runGitSync(["branch", "existing-branch"], in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        await #expect(throws: WorktreeError.self) {
            try await orchestrator.createWorktreeSession(
                branchName: "existing-branch",
                existingBranch: true,
                base: "HEAD",
                repoPath: repo,
                workspaceID: workspace.id
            )
        }
    }

    @Test
    func createWorktreeSession_invalidBaseRef_throws() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        await #expect(throws: WorktreeError.self) {
            try await orchestrator.createWorktreeSession(
                branchName: "feature/bad-base",
                base: "no-such-ref-xyz",
                repoPath: repo,
                workspaceID: workspace.id
            )
        }
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

        let result = try await orchestrator.createWorktreeSession(
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
            try await orchestrator.removeWorktreeSession(sessionID: result.sessionID, force: false)
        }

        // Session should still exist after failed removal
        #expect(workspace.sessionCollection.sessions.contains(where: { $0.id == result.sessionID }))

        // Remove with force should succeed
        try await orchestrator.removeWorktreeSession(sessionID: result.sessionID, force: true)

        #expect(!FileManager.default.fileExists(atPath: worktreePath))
        #expect(!workspace.sessionCollection.sessions.contains(where: { $0.id == result.sessionID }))
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
        _ = try await orchestrator.createWorktreeSession(
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
        _ = try await orchestrator.createWorktreeSession(
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

    @Test func createWorktreeSessionTargetsSpecifiedWorkspaceNotKeyWindow() async throws {
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
        // target C explicitly via workspaceID. The new session must land in C.
        let provider = MockWorkspaceProvider()
        provider.collections = [collectionA, collectionC]
        provider.keyWindowWorkspace = workspaceA

        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orchestrator.createWorktreeSession(
            branchName: "feature-c",
            existingBranch: false,
            repoPath: repoC,
            workspaceID: workspaceC.id
        )

        #expect(workspaceC.sessionCollection.sessions.contains { $0.id == result.sessionID })
        #expect(!workspaceA.sessionCollection.sessions.contains { $0.id == result.sessionID })
    }

    // MARK: - In-flight guard (FR-061)

    /// FR-061: Concurrent `removeWorktreeSession` on a *different* Session is
    /// rejected with `WorktreeError.closeInFlight` while the first removal
    /// is still in flight.
    @Test func concurrentCloseOnDifferentSessionIsRejected() async throws {
        let repoA = try makeTempGitRepo()
        let repoB = try makeTempGitRepo()
        defer {
            cleanup(repoA)
            cleanup(repoB)
        }

        // Session A: configure a slow archive command so the first removal
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
        // Session B: no archive commands — fast removal so the in-flight
        // guard is the only thing stopping it.
        try writeConfig("worktree_dir = \".worktrees\"", in: repoB)

        // Both Sessions live in the same orchestrator / provider.
        let collectionA = WorkspaceCollection(workingDirectory: repoA)
        let collectionB = WorkspaceCollection(workingDirectory: repoB)
        let workspaceA = collectionA.activeWorkspace!
        let workspaceB = collectionB.activeWorkspace!

        let provider = MockWorkspaceProvider()
        provider.collections = [collectionA, collectionB]
        provider.keyWindowWorkspace = workspaceA

        let orch = WorktreeOrchestrator(workspaceProvider: provider)

        // Create both worktree Sessions first.
        let resultA = try await orch.createWorktreeSession(
            branchName: "close-guard-a",
            repoPath: repoA,
            workspaceID: workspaceA.id
        )
        let resultB = try await orch.createWorktreeSession(
            branchName: "close-guard-b",
            repoPath: repoB,
            workspaceID: workspaceB.id
        )

        // Cancel Session A's slow archive command after it starts, so the
        // test doesn't hang for 5 s.
        let cancelTask = Task { @MainActor in
            for _ in 0..<500 {
                if orch.isCloseInFlight { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            orch.cancelCommands()
        }

        // Start Session A removal in background — it will block on `sleep 5`.
        let removeATask = Task { @MainActor in
            try await orch.removeWorktreeSession(sessionID: resultA.sessionID)
        }

        // Wait until the in-flight guard is raised.
        for _ in 0..<500 {
            if orch.isCloseInFlight { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(orch.isCloseInFlight, "isCloseInFlight should be true while Session A removal is running")

        // Attempt to remove Session B while Session A removal is still in flight.
        var caughtCloseInFlight = false
        do {
            try await orch.removeWorktreeSession(sessionID: resultB.sessionID)
        } catch WorktreeError.closeInFlight {
            caughtCloseInFlight = true
        }
        #expect(caughtCloseInFlight, "Expected WorktreeError.closeInFlight when removing a different Session concurrently")

        // Let Session A's removal finish (cancel already signalled above).
        _ = await cancelTask.value
        _ = try? await removeATask.value

        // After both calls complete, the guard must be cleared.
        #expect(!orch.isCloseInFlight, "isCloseInFlight should be false after all removals complete")
    }

    /// `isCloseInFlight` is cleared via defer even when `removeWorktreeSession`
    /// returns normally (success path).
    @Test func isCloseInFlight_isClearedOnSuccess() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orch = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orch.createWorktreeSession(
            branchName: "inflight-success",
            repoPath: repo,
            workspaceID: workspace.id
        )

        #expect(!orch.isCloseInFlight)
        try await orch.removeWorktreeSession(sessionID: result.sessionID)
        #expect(!orch.isCloseInFlight)
    }

    /// `isCloseInFlight` is cleared via defer even when `removeWorktreeSession`
    /// throws (error path, e.g. uncommittedChanges).
    @Test func isCloseInFlight_isClearedOnFailure() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orch = WorktreeOrchestrator(workspaceProvider: provider)

        let result = try await orch.createWorktreeSession(
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
            try await orch.removeWorktreeSession(sessionID: result.sessionID, force: false)
        } catch WorktreeError.uncommittedChanges {
            // expected
        }
        #expect(!orch.isCloseInFlight, "isCloseInFlight should be false after a throwing removal")
    }

    // MARK: - Orchestrator → implementer parent link

    /// A worktree Session records the creating Session as its `parentSessionID`
    /// so the sidebar can nest it under its orchestrator.
    @Test func worktreeSessionRecordsCreatorAsParent() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }
        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // The workspace's default Session plays the orchestrator.
        let creator = workspace.sessionCollection.activeSession!

        let result = try await orchestrator.createWorktreeSession(
            branchName: "impl-a",
            repoPath: repo,
            workspaceID: workspace.id,
            background: true,
            creatorSessionID: creator.id
        )

        let newSession = workspace.sessionCollection.sessions.first(where: { $0.id == result.sessionID })
        #expect(newSession?.parentSessionID == creator.id)
    }

    /// Two-level cap: when an implementer (a Session that already has a parent)
    /// spawns another worktree, the new Session attaches to the top orchestrator,
    /// not the implementer — never a third level.
    @Test func worktreeSessionCapsNestingAtTwoLevels() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }
        try writeConfig("worktree_dir = \".worktrees\"", in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)
        let top = workspace.sessionCollection.activeSession!

        let firstResult = try await orchestrator.createWorktreeSession(
            branchName: "impl-1",
            repoPath: repo,
            workspaceID: workspace.id,
            background: true,
            creatorSessionID: top.id
        )
        let firstImpl = workspace.sessionCollection.sessions.first(where: { $0.id == firstResult.sessionID })!
        #expect(firstImpl.parentSessionID == top.id)

        // The implementer spawns another worktree → caps to the top orchestrator.
        let secondResult = try await orchestrator.createWorktreeSession(
            branchName: "impl-2",
            repoPath: repo,
            workspaceID: workspace.id,
            background: true,
            creatorSessionID: firstImpl.id
        )
        let secondImpl = workspace.sessionCollection.sessions.first(where: { $0.id == secondResult.sessionID })!
        #expect(secondImpl.parentSessionID == top.id)
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
