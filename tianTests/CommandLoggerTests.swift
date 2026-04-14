import Testing
import Foundation

struct CommandLoggerTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    private func logFilePath(in dir: URL) -> URL {
        dir.appendingPathComponent("cli.log")
    }

    private func rotatedFilePath(in dir: URL) -> URL {
        dir.appendingPathComponent("cli.log.1")
    }

    private func readLines(at url: URL) throws -> [String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        return content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    // MARK: - Tests

    @Test func logEntryContainsAllSixFields() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let start = ContinuousClock.now
        CommandLogger.log(
            command: "workspace create test",
            exitCode: 0,
            result: "a1b2c3d4",
            error: nil,
            startTime: start,
            logDirectory: dir
        )

        let lines = try readLines(at: logFilePath(in: dir))
        #expect(lines.count == 1)

        let data = try #require(lines[0].data(using: .utf8))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(obj["timestamp"] is String)
        #expect(obj["command"] as? String == "workspace create test")
        #expect(obj["exitCode"] as? Int == 0)
        #expect(obj["result"] as? String == "a1b2c3d4")
        #expect(obj["error"] is NSNull)
        #expect(obj["durationMs"] is Int)
        #expect(obj.count == 6)
    }

    @Test func resultIsNullWhenNil() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        CommandLogger.log(
            command: "workspace close abc",
            exitCode: 0,
            result: nil,
            error: nil,
            startTime: ContinuousClock.now,
            logDirectory: dir
        )

        let line = try readLines(at: logFilePath(in: dir))[0]
        #expect(line.contains("\"result\":null"))
    }

    @Test func errorFieldPopulatedOnFailure() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        CommandLogger.log(
            command: "workspace focus bad-id",
            exitCode: 1,
            result: nil,
            error: "Workspace not found",
            startTime: ContinuousClock.now,
            logDirectory: dir
        )

        let data = try readLines(at: logFilePath(in: dir))[0].data(using: .utf8)!
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(obj["exitCode"] as? Int == 1)
        #expect(obj["error"] as? String == "Workspace not found")
        #expect(obj["result"] is NSNull)
    }

    @Test func logDirectoryCreatedWhenAbsent() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-test-\(UUID().uuidString)")
        let dir = parent.appendingPathComponent("nested/logs")
        defer { cleanup(parent) }

        #expect(!FileManager.default.fileExists(atPath: dir.path))

        CommandLogger.log(
            command: "ping",
            exitCode: 0,
            result: nil,
            error: nil,
            startTime: ContinuousClock.now,
            logDirectory: dir
        )

        #expect(FileManager.default.fileExists(atPath: logFilePath(in: dir).path))
    }

    @Test func multipleEntriesAppendCorrectly() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        for i in 0..<3 {
            CommandLogger.log(
                command: "ping \(i)",
                exitCode: 0,
                result: nil,
                error: nil,
                startTime: ContinuousClock.now,
                logDirectory: dir
            )
        }

        let lines = try readLines(at: logFilePath(in: dir))
        #expect(lines.count == 3)
    }

    @Test func rotationTriggersWhenFileExceedsTenMB() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let logFile = logFilePath(in: dir)

        // Write a file just over 10 MB.
        let tenMBPlusOne = Data(repeating: UInt8(ascii: "x"), count: 10 * 1024 * 1024 + 1)
        try tenMBPlusOne.write(to: logFile)

        CommandLogger.log(
            command: "ping",
            exitCode: 0,
            result: nil,
            error: nil,
            startTime: ContinuousClock.now,
            logDirectory: dir
        )

        // cli.log.1 should have the old data.
        let rotated = rotatedFilePath(in: dir)
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        let rotatedSize = try FileManager.default.attributesOfItem(atPath: rotated.path)[.size] as! UInt64
        #expect(rotatedSize > 10 * 1024 * 1024)

        // cli.log should have only the new entry.
        let lines = try readLines(at: logFile)
        #expect(lines.count == 1)
    }

    @Test func rotationOverwritesExistingBackup() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let logFile = logFilePath(in: dir)
        let rotated = rotatedFilePath(in: dir)

        // Create an existing .1 file with known content.
        try Data("old-backup\n".utf8).write(to: rotated)

        // Create a log file over 10 MB.
        let tenMBPlusOne = Data(repeating: UInt8(ascii: "y"), count: 10 * 1024 * 1024 + 1)
        try tenMBPlusOne.write(to: logFile)

        CommandLogger.log(
            command: "ping",
            exitCode: 0,
            result: nil,
            error: nil,
            startTime: ContinuousClock.now,
            logDirectory: dir
        )

        // .1 should be the rotated file, not the old backup.
        let rotatedContent = try Data(contentsOf: rotated)
        #expect(rotatedContent.count > 10 * 1024 * 1024)
        #expect(!String(data: rotatedContent, encoding: .utf8)!.contains("old-backup"))
    }
}
