import Testing
import Foundation
@testable import aterm

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
            .appendingPathComponent("aterm-orch-test-\(UUID().uuidString)")
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
        let configDir = (repoRoot as NSString).appendingPathComponent(".aterm")
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

        // Verify isCreating is reset
        #expect(!orchestrator.isCreating)
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
        setup_timeout = 0.01

        [[setup]]
        command = "echo step1"

        [[setup]]
        command = "echo step2"

        [[setup]]
        command = "echo step3"
        """, in: repo)

        let (provider, workspace) = makeProvider(repoPath: repo)
        let orchestrator = WorktreeOrchestrator(workspaceProvider: provider)

        // Schedule cancellation during creation (fires during an await suspension)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))
            orchestrator.cancelSetup()
        }

        let result = try await orchestrator.createWorktreeSpace(
            branchName: "cancel-branch",
            repoPath: repo,
            workspaceID: workspace.id
        )

        // Creation should still succeed (Space exists)
        #expect(!result.existed)
        let newSpace = workspace.spaceCollection.spaces.first(where: { $0.id == result.spaceID })
        #expect(newSpace != nil)

        // isCreating should be reset
        #expect(!orchestrator.isCreating)
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

    // MARK: - Remote ref

    @Test
    func createWorktreeSpace_withRemoteRef_skipsBranchExistsPreflight() async throws {
        // Seed a remote with a branch, clone it — the branch only exists as origin/feat/r in the clone.
        let remote = try makeTempGitRepo()
        defer { cleanup(remote) }
        try runGitSync(["branch", "feat/r"], in: remote)

        let clone = FileManager.default.temporaryDirectory
            .appendingPathComponent("aterm-orch-clone-\(UUID().uuidString)").path
        defer { cleanup(clone) }
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
