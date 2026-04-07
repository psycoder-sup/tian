import Testing
import Foundation
@testable import aterm

struct WorktreeServiceTests {

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
            throw StringError("git \(args.joined(separator: " ")) failed: \(msg)")
        }
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

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aterm-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir,
                                                  withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func resolvePath(_ path: String) -> String {
        URL(filePath: path).resolvingSymlinksInPath().path
    }

    // MARK: - resolveRepoRoot

    @Test func resolveRepoRootFromGitRepo() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let root = try await WorktreeService.resolveRepoRoot(from: repo)
        #expect(resolvePath(root) == resolvePath(repo))
    }

    @Test func resolveRepoRootFromNonGitDirThrows() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        await #expect(throws: WorktreeError.self) {
            try await WorktreeService.resolveRepoRoot(from: dir)
        }
    }

    // MARK: - createWorktree

    @Test func createWorktreeWithNewBranch() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let path = try await WorktreeService.createWorktree(
            repoRoot: repo,
            worktreeDir: ".worktrees",
            branchName: "feature/test-branch",
            existingBranch: false
        )

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDir))
        #expect(isDir.boolValue)

        let branchFound = try await WorktreeService.branchExists(
            repoRoot: repo, branchName: "feature/test-branch"
        )
        #expect(branchFound)
    }

    @Test func createWorktreeWithExistingBranch() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        try runGitSync(["branch", "existing-branch"], in: repo)

        let path = try await WorktreeService.createWorktree(
            repoRoot: repo,
            worktreeDir: ".worktrees",
            branchName: "existing-branch",
            existingBranch: true
        )

        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test func createWorktreeWhenBranchExistsThrows() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        _ = try await WorktreeService.createWorktree(
            repoRoot: repo,
            worktreeDir: ".worktrees",
            branchName: "dup-branch",
            existingBranch: false
        )

        await #expect(throws: WorktreeError.self) {
            try await WorktreeService.createWorktree(
                repoRoot: repo,
                worktreeDir: ".worktrees",
                branchName: "dup-branch",
                existingBranch: false
            )
        }
    }

    // MARK: - removeWorktree

    @Test func removeWorktree() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let path = try await WorktreeService.createWorktree(
            repoRoot: repo,
            worktreeDir: ".worktrees",
            branchName: "to-remove",
            existingBranch: false
        )
        #expect(FileManager.default.fileExists(atPath: path))

        try await WorktreeService.removeWorktree(
            repoRoot: repo,
            worktreePath: path,
            force: false
        )
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    // MARK: - pruneEmptyParents

    @Test func pruneEmptyParentsRemovesNestedDirs() throws {
        let repo = try makeTempDir()
        defer { cleanup(repo) }

        // Create .worktrees/feature/my-branch/ (empty leaf)
        let branchDir = (repo as NSString)
            .appendingPathComponent(".worktrees/feature/my-branch")
        try FileManager.default.createDirectory(
            atPath: branchDir,
            withIntermediateDirectories: true
        )

        try WorktreeService.pruneEmptyParents(
            worktreePath: branchDir,
            worktreeDir: ".worktrees",
            repoRoot: repo
        )

        let featureDir = (repo as NSString).appendingPathComponent(".worktrees/feature")
        let worktreesDir = (repo as NSString).appendingPathComponent(".worktrees")

        #expect(!FileManager.default.fileExists(atPath: branchDir))
        #expect(!FileManager.default.fileExists(atPath: featureDir))
        // .worktrees itself should remain (stop boundary)
        #expect(FileManager.default.fileExists(atPath: worktreesDir))
    }

    @Test func pruneEmptyParentsStopsAtNonEmpty() throws {
        let repo = try makeTempDir()
        defer { cleanup(repo) }

        let branchA = (repo as NSString)
            .appendingPathComponent(".worktrees/feature/branch-a")
        let branchB = (repo as NSString)
            .appendingPathComponent(".worktrees/feature/branch-b")
        try FileManager.default.createDirectory(
            atPath: branchA, withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            atPath: branchB, withIntermediateDirectories: true
        )
        // Put a file in branch-b so feature/ is non-empty after removing branch-a
        let filePath = (branchB as NSString).appendingPathComponent("marker.txt")
        try "x".write(toFile: filePath, atomically: true, encoding: .utf8)

        try WorktreeService.pruneEmptyParents(
            worktreePath: branchA,
            worktreeDir: ".worktrees",
            repoRoot: repo
        )

        #expect(!FileManager.default.fileExists(atPath: branchA))
        let featureDir = (repo as NSString).appendingPathComponent(".worktrees/feature")
        #expect(FileManager.default.fileExists(atPath: featureDir))
    }

    // MARK: - copyFiles

    @Test func copyFilesWithGlobPattern() throws {
        let source = try makeTempDir()
        let dest = try makeTempDir()
        defer { cleanup(source); cleanup(dest) }

        // Create source files
        try ".env content".write(
            toFile: (source as NSString).appendingPathComponent(".env"),
            atomically: true, encoding: .utf8
        )
        try ".env.local content".write(
            toFile: (source as NSString).appendingPathComponent(".env.local"),
            atomically: true, encoding: .utf8
        )
        try "other".write(
            toFile: (source as NSString).appendingPathComponent("other.txt"),
            atomically: true, encoding: .utf8
        )

        let rules = [CopyRule(source: ".env*", dest: ".")]

        WorktreeService.copyFiles(
            copyRules: rules,
            mainWorktreePath: source,
            newWorktreePath: dest
        )

        #expect(FileManager.default.fileExists(
            atPath: (dest as NSString).appendingPathComponent(".env")
        ))
        #expect(FileManager.default.fileExists(
            atPath: (dest as NSString).appendingPathComponent(".env.local")
        ))
        // other.txt should NOT be copied
        #expect(!FileManager.default.fileExists(
            atPath: (dest as NSString).appendingPathComponent("other.txt")
        ))
    }

    @Test func copyFilesNoMatchDoesNotThrow() throws {
        let source = try makeTempDir()
        let dest = try makeTempDir()
        defer { cleanup(source); cleanup(dest) }

        let rules = [CopyRule(source: "nonexistent*", dest: ".")]

        // Should complete without error
        WorktreeService.copyFiles(
            copyRules: rules,
            mainWorktreePath: source,
            newWorktreePath: dest
        )
    }

    // MARK: - ensureGitignore

    @Test func ensureGitignoreAppendsToExisting() throws {
        let repo = try makeTempDir()
        defer { cleanup(repo) }

        let gitignorePath = (repo as NSString).appendingPathComponent(".gitignore")
        try "node_modules\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)

        try WorktreeService.ensureGitignore(repoRoot: repo, worktreeDir: ".worktrees")

        let content = try String(contentsOfFile: gitignorePath, encoding: .utf8)
        #expect(content.contains("node_modules"))
        #expect(content.contains(".worktrees"))
    }

    @Test func ensureGitignoreCreatesNew() throws {
        let repo = try makeTempDir()
        defer { cleanup(repo) }

        let gitignorePath = (repo as NSString).appendingPathComponent(".gitignore")
        #expect(!FileManager.default.fileExists(atPath: gitignorePath))

        try WorktreeService.ensureGitignore(repoRoot: repo, worktreeDir: ".worktrees")

        let content = try String(contentsOfFile: gitignorePath, encoding: .utf8)
        #expect(content.contains(".worktrees"))
        #expect(content.contains("# aterm worktree directory"))
    }
}

private struct StringError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
