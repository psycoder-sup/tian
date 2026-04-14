import Foundation

/// Appends a JSONL entry to ~/Library/Logs/tian/cli.log for every CLI invocation.
/// Rotation: if the log exceeds 10 MB, rename to cli.log.1 and start fresh.
enum CommandLogger {

    private static let maxFileSize: UInt64 = 10 * 1024 * 1024  // 10 MB
    private static let logFileName = "cli.log"
    private static let rotatedFileName = "cli.log.1"

    nonisolated(unsafe) private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return e
    }()

    private struct LogEntry: Encodable {
        let timestamp: String
        let command: String
        let exitCode: Int32
        let result: String?
        let error: String?
        let durationMs: Int

        private enum CodingKeys: String, CodingKey {
            case timestamp, command, exitCode, result, error, durationMs
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(timestamp, forKey: .timestamp)
            try c.encode(command, forKey: .command)
            try c.encode(exitCode, forKey: .exitCode)
            try c.encode(result, forKey: .result)       // encodes null when nil
            try c.encode(error, forKey: .error)         // encodes null when nil
            try c.encode(durationMs, forKey: .durationMs)
        }
    }

    static func log(
        command: String,
        exitCode: Int32,
        result: String?,
        error: String?,
        startTime: ContinuousClock.Instant,
        logDirectory: URL? = nil
    ) {
        do {
            let durationMs = Int((ContinuousClock.now - startTime).components.attoseconds
                                 / 1_000_000_000_000_000)

            let timestamp = dateFormatter.string(from: Date())

            let entry = LogEntry(
                timestamp: timestamp,
                command: command,
                exitCode: exitCode,
                result: result,
                error: error,
                durationMs: durationMs
            )

            var data = try jsonEncoder.encode(entry)
            data.append(contentsOf: [UInt8(ascii: "\n")])

            let directory = logDirectory ?? defaultLogDirectory()
            try append(data: data, to: logFileName, in: directory)
        } catch {
            // Logging must never crash the CLI — silently discard errors.
        }
    }

    // MARK: - Private

    private static func defaultLogDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/tian")
    }

    private static func append(data: Data, to fileName: String, in directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let logFile = directory.appendingPathComponent(fileName)

        // Rotate if the existing file exceeds the size limit.
        if let attrs = try? fm.attributesOfItem(atPath: logFile.path),
           let size = attrs[.size] as? UInt64,
           size > maxFileSize {
            let rotated = directory.appendingPathComponent(rotatedFileName)
            try? fm.removeItem(at: rotated)
            try fm.moveItem(at: logFile, to: rotated)
        }

        // Create the file if it doesn't exist.
        if !fm.fileExists(atPath: logFile.path) {
            fm.createFile(atPath: logFile.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: logFile)
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
}
