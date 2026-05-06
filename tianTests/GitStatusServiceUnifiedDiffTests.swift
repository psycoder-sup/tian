import Foundation
import Testing
@testable import tian

struct GitStatusServiceUnifiedDiffTests {

    // MARK: - FR-T10 / FR-T15: parsesAddDeleteContextLines

    @Test func parsesAddDeleteContextLines() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Create a file with known content and commit it
        let filePath = (repo as NSString).appendingPathComponent("sample.txt")
        let originalLines = (1...5).map { "line \($0)" }.joined(separator: "\n")
        try originalLines.write(toFile: filePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", "sample.txt"], in: repo)
        try runGitSync(["commit", "-m", "add sample.txt"], in: repo)

        // Now modify: replace line 3, delete line 4, add a new line after line 5
        let modifiedContent = "line 1\nline 2\nline 3 modified\nline 5\nadded line"
        try modifiedContent.write(toFile: filePath, atomically: true, encoding: .utf8)

        let diffs = await GitStatusService.unifiedDiff(directory: repo)

        let fileDiff = try #require(diffs.first(where: { $0.path == "sample.txt" }))
        #expect(fileDiff.isBinary == false)
        #expect(!fileDiff.hunks.isEmpty)

        // Count additions and deletions
        #expect(fileDiff.additions > 0)
        #expect(fileDiff.deletions > 0)

        // Verify line kinds are present
        let allLines = fileDiff.hunks.flatMap(\.lines)
        #expect(allLines.contains(where: { $0.kind == .context }))
        #expect(allLines.contains(where: { $0.kind == .added }))
        #expect(allLines.contains(where: { $0.kind == .deleted }))

        // Verify line numbers are assigned
        let contextLines = allLines.filter { $0.kind == .context }
        #expect(contextLines.allSatisfy { $0.oldLineNumber != nil && $0.newLineNumber != nil })

        let addedLines = allLines.filter { $0.kind == .added }
        #expect(addedLines.allSatisfy { $0.oldLineNumber == nil && $0.newLineNumber != nil })

        let deletedLines = allLines.filter { $0.kind == .deleted }
        #expect(deletedLines.allSatisfy { $0.oldLineNumber != nil && $0.newLineNumber == nil })
    }

    // MARK: - FR-T10 / FR-T15: untrackedFilesAppearAsAdded

    @Test func untrackedFilesAppearAsAdded() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        let content = "alpha\nbeta\ngamma\n"
        let filePath = (repo as NSString).appendingPathComponent("untracked.txt")
        try content.write(toFile: filePath, atomically: true, encoding: .utf8)

        let diffs = await GitStatusService.unifiedDiff(directory: repo)

        let fileDiff = try #require(diffs.first(where: { $0.path == "untracked.txt" }))
        #expect(fileDiff.status == .added)
        #expect(fileDiff.isBinary == false)
        #expect(!fileDiff.hunks.isEmpty)

        let allLines = fileDiff.hunks.flatMap(\.lines)
        #expect(!allLines.isEmpty)
        #expect(allLines.allSatisfy { $0.kind == .added })
        #expect(fileDiff.additions == allLines.count)
        #expect(fileDiff.deletions == 0)
    }

    // MARK: - FR-T10a: binaryGate512KB

    @Test func binaryGate512KB() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Write a 600 KB untracked file (all zeros — text-safe but large)
        let largeData = Data(repeating: 0x41, count: 600 * 1024) // 614,400 bytes
        let filePath = (repo as NSString).appendingPathComponent("large_untracked.bin")
        try largeData.write(to: URL(filePath: filePath))

        let diffs = await GitStatusService.unifiedDiff(directory: repo)

        let fileDiff = try #require(diffs.first(where: { $0.path == "large_untracked.bin" }))
        #expect(fileDiff.isBinary == true)
        #expect(fileDiff.hunks.isEmpty)
    }

    // MARK: - FR-T10a: gitReportedBinaryFlagged

    @Test func gitReportedBinaryFlagged() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Stage a file containing NUL bytes — git considers this binary
        var binaryContent = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG header
        binaryContent.append(contentsOf: [UInt8](repeating: 0x00, count: 100))        // NUL bytes
        let filePath = (repo as NSString).appendingPathComponent("image.png")
        try binaryContent.write(to: URL(filePath: filePath))
        try runGitSync(["add", "image.png"], in: repo)
        try runGitSync(["commit", "-m", "add binary"], in: repo)

        // Modify it so there's a diff
        var modifiedBinary = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0B])
        modifiedBinary.append(contentsOf: [UInt8](repeating: 0x00, count: 100))
        try modifiedBinary.write(to: URL(filePath: filePath))

        let diffs = await GitStatusService.unifiedDiff(directory: repo)

        let fileDiff = try #require(diffs.first(where: { $0.path == "image.png" }))
        #expect(fileDiff.isBinary == true)
        #expect(fileDiff.hunks.isEmpty)

        // Ensure "Binary files differ" was never parsed as a line of text
        let allLines = fileDiff.hunks.flatMap(\.lines)
        #expect(allLines.allSatisfy { !$0.text.contains("Binary files") })
    }

    // MARK: - FR-T15: linesCapsAt5000

    @Test func linesCapsAt5000() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Create a new untracked file with 6000 lines (single large addition, no prior version)
        let lines = (1...6000).map { "line \($0)" }.joined(separator: "\n")
        let filePath = (repo as NSString).appendingPathComponent("bigfile.txt")
        try lines.write(toFile: filePath, atomically: true, encoding: .utf8)

        let diffs = await GitStatusService.unifiedDiff(directory: repo)

        let fileDiff = try #require(diffs.first(where: { $0.path == "bigfile.txt" }))
        #expect(fileDiff.isBinary == false)

        let totalEmittedLines = fileDiff.hunks.flatMap(\.lines).count
        #expect(totalEmittedLines == 5000)

        let totalTruncated = fileDiff.hunks.reduce(0) { $0 + $1.truncatedLines }
        #expect(totalTruncated == 1000)
    }

    // MARK: - FR-T10: gitignoredFilesExcluded

    @Test func gitignoredFilesExcluded() async throws {
        let repo = try makeTempGitRepo()
        defer { cleanup(repo) }

        // Write .gitignore
        let gitignorePath = (repo as NSString).appendingPathComponent(".gitignore")
        try "secret.txt\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        try runGitSync(["add", ".gitignore"], in: repo)
        try runGitSync(["commit", "-m", "add .gitignore"], in: repo)

        // Create the ignored file
        let secretPath = (repo as NSString).appendingPathComponent("secret.txt")
        try "top secret content".write(toFile: secretPath, atomically: true, encoding: .utf8)

        let diffs = await GitStatusService.unifiedDiff(directory: repo)

        #expect(!diffs.contains(where: { $0.path == "secret.txt" }))
    }

    // MARK: - Helpers

    private func makeTempGitRepo() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-diff-test-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir,
                                                  withIntermediateDirectories: true)
        try runGitSync(["init"], in: dir)
        try runGitSync(["config", "user.email", "test@test.com"], in: dir)
        try runGitSync(["config", "user.name", "Test"], in: dir)

        let readmePath = (dir as NSString).appendingPathComponent("README.md")
        try "# Test Repo\n".write(toFile: readmePath, atomically: true, encoding: .utf8)

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
        process.standardOutput = Pipe() // suppress output
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
