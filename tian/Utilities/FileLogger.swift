import OSLog

/// Logger that dual-writes to both `os.Logger` (unified logging) and a log file.
/// Drop-in replacement for `os.Logger` on selected categories where post-mortem
/// debugging requires persisted logs.
struct FileLogger: Sendable {
    private let osLogger: Logger
    private let category: String

    init(subsystem: String, category: String) {
        self.osLogger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    func debug(_ message: String) {
        osLogger.debug("\(message)")
        FileLogWriter.shared.write(level: "DEBUG", category: category, message: message)
    }

    func info(_ message: String) {
        osLogger.info("\(message)")
        FileLogWriter.shared.write(level: "INFO", category: category, message: message)
    }

    func warning(_ message: String) {
        osLogger.warning("\(message)")
        FileLogWriter.shared.write(level: "WARN", category: category, message: message)
    }

    func error(_ message: String) {
        osLogger.error("\(message)")
        FileLogWriter.shared.write(level: "ERROR", category: category, message: message)
    }
}
