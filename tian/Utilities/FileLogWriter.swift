import Foundation

/// Writes log lines to `~/Library/Logs/tian/tian.log` with size-based rotation.
/// Thread-safe via serial dispatch queue. All errors are silently swallowed —
/// logging must never crash the app.
final class FileLogWriter: @unchecked Sendable {
    static let shared = FileLogWriter()

    private let queue = DispatchQueue(label: "com.tian.file-log-writer")
    private let maxFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    private let logDirectory: URL
    private let logFileURL: URL
    private let backupFileURL: URL
    private var fileHandle: FileHandle?
    private var currentSize: UInt64 = 0

    private let dateFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        logDirectory = home.appendingPathComponent("Library/Logs/tian")
        logFileURL = logDirectory.appendingPathComponent("tian.log")
        backupFileURL = logDirectory.appendingPathComponent("tian.1.log")
        setupDirectory()
        openFile()
    }

    func write(level: String, category: String, message: String) {
        let now = Date()
        queue.async { [self] in
            let timestamp = dateFormatter.string(from: now)
            let line = "\(timestamp) [\(level)] [\(category)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            rotateIfNeeded()
            guard let handle = fileHandle else { return }
            do {
                try handle.write(contentsOf: data)
                currentSize += UInt64(data.count)
            } catch {
                // Silent failure — logging errors must never crash the app
            }
        }
    }

    // MARK: - File Management

    private func setupDirectory() {
        try? FileManager.default.createDirectory(
            at: logDirectory,
            withIntermediateDirectories: true
        )
    }

    private func openFile() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: logFileURL.path) {
            fm.createFile(atPath: logFileURL.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        if let handle = fileHandle {
            currentSize = handle.seekToEndOfFile()
        }
    }

    private func rotateIfNeeded() {
        guard currentSize >= maxFileSize else { return }

        let fm = FileManager.default
        fileHandle?.closeFile()
        fileHandle = nil

        try? fm.removeItem(at: backupFileURL)
        try? fm.moveItem(at: logFileURL, to: backupFileURL)

        fm.createFile(atPath: logFileURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        currentSize = 0
    }
}
