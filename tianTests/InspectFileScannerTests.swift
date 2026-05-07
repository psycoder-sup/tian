import Foundation
import Testing
@testable import tian

struct InspectFileScannerTests {

    // `git ls-files --cached --others --exclude-standard -z` yields tracked
    // and untracked non-ignored files. Ignored entries are intentionally
    // excluded from the scanner; the view model merges rolled-up ignored
    // directory entries from `scanGitIgnored` separately so they appear as
    // single dimmed nodes instead of 50k+ individual paths.
    @Test func gitTrackedReturnsTrackedAndUntrackedNotIgnored() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Tracked file (committed by makeTempGitRepo as README.md). Add another.
        let trackedPath = (repo as NSString).appendingPathComponent("tracked.txt")
        try "tracked".write(toFile: trackedPath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "tracked.txt"], in: repo)
        try runGitSync(["commit", "-m", "add tracked"], in: repo)

        // .gitignore lists ignored.txt.
        let gitignorePath = (repo as NSString).appendingPathComponent(".gitignore")
        try "ignored.txt\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)

        // Untracked-not-ignored file.
        let untrackedPath = (repo as NSString).appendingPathComponent("untracked.txt")
        try "untracked".write(toFile: untrackedPath, atomically: true, encoding: .utf8)

        // Ignored file — present on disk and referenced by .gitignore.
        let ignoredPath = (repo as NSString).appendingPathComponent("ignored.txt")
        try "ignored".write(toFile: ignoredPath, atomically: true, encoding: .utf8)

        let result = try await InspectFileScanner.scanGitTracked(workingTree: repo)
        #expect(result.contains("tracked.txt"))
        #expect(result.contains("untracked.txt"))
        // With --exclude-standard the scanner no longer returns ignored files;
        // the view model merges rolled-up ignored dirs from scanGitIgnored.
        #expect(!result.contains("ignored.txt"))
    }

    // FR-15 / FR-22 — outside a git repo, fall back to FileManager enumeration.
    @Test func fileSystemFallbackEnumeratesNonGitDir() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let fileA = (dir as NSString).appendingPathComponent("a.txt")
        try "a".write(toFile: fileA, atomically: true, encoding: .utf8)

        let nestedDir = (dir as NSString).appendingPathComponent("nested")
        try FileManager.default.createDirectory(atPath: nestedDir, withIntermediateDirectories: true)
        let nestedFile = (nestedDir as NSString).appendingPathComponent("b.txt")
        try "b".write(toFile: nestedFile, atomically: true, encoding: .utf8)

        let result = try await InspectFileScanner.scanFileSystem(root: URL(filePath: dir))
        #expect(result.contains("a.txt"))
        #expect(result.contains("nested/b.txt"))
        // No leading `./`.
        #expect(!result.contains(where: { $0.hasPrefix("./") }))
    }

    @Test func fileSystemFallbackOnEmptyDirReturnsEmpty() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let result = try await InspectFileScanner.scanFileSystem(root: URL(filePath: dir))
        #expect(result.isEmpty)
    }

    // FR-16 — hidden dotfiles (`.env`) shown when not gitignored.
    @Test func dotfilesShownWhenNotIgnored() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let envPath = (repo as NSString).appendingPathComponent(".env")
        try "SECRET=1".write(toFile: envPath, atomically: true, encoding: .utf8)

        let result = try await InspectFileScanner.scanGitTracked(workingTree: repo)
        #expect(result.contains(".env"))
    }

    // FR-17 — symlinks shown as files, target not followed.
    @Test func symlinksReturnedAsFiles() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Create the symlink target outside `dir` so that following the
        // symlink would (incorrectly) surface the target file.
        let outsideDir = try makeTempDir()
        defer { cleanup(outsideDir) }
        let targetPath = (outsideDir as NSString).appendingPathComponent("target.txt")
        try "target contents".write(toFile: targetPath, atomically: true, encoding: .utf8)

        let linkPath = (dir as NSString).appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: targetPath)

        let result = try await InspectFileScanner.scanFileSystem(root: URL(filePath: dir))
        #expect(result.contains("link.txt"))
        // Symlink target must not surface under the symlink path.
        #expect(!result.contains(where: { $0.contains("target.txt") }))
    }

    // MARK: - Helpers

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-scanner-\(UUID().uuidString)")
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

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-scanner-\(UUID().uuidString)")
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
}
