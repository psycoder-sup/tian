import Foundation
import Testing
@testable import tian

struct WorktreeKindTests {

    // MARK: - Helpers

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-wk-test-\(UUID().uuidString)")
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

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-wk-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
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

    // MARK: - Tests

    @Test func classifiesMainCheckoutAsRepo() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let kind = await WorktreeKind.classify(directory: repo)
        #expect(kind == .mainCheckout)
    }

    @Test func classifiesLinkedWorktreeAsWorktree() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let worktreePath = (repo as NSString)
            .deletingLastPathComponent
            .appending("/tian-wk-wt-\(UUID().uuidString)")
        defer { cleanup(worktreePath) }

        try runGitSync(["worktree", "add", worktreePath, "-b", "wt-branch"], in: repo)

        let kind = await WorktreeKind.classify(directory: worktreePath)
        #expect(kind == .linkedWorktree)
    }

    @Test func classifiesNonGitDirAsLocal() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let kind = await WorktreeKind.classify(directory: dir)
        #expect(kind == .notARepo)
    }

    @Test func classifiesNilDirAsNoWorkingDirectory() async {
        let kindNil = await WorktreeKind.classify(directory: nil)
        #expect(kindNil == .noWorkingDirectory)

        let kindEmpty = await WorktreeKind.classify(directory: "")
        #expect(kindEmpty == .noWorkingDirectory)
    }
}
