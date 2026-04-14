import OSLog

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.tian.app"

    // File-logged categories (dual: os.Logger + ~/Library/Logs/tian/tian.log)
    static let ipc = FileLogger(subsystem: subsystem, category: "ipc")
    static let lifecycle = FileLogger(subsystem: subsystem, category: "lifecycle")
    static let persistence = FileLogger(subsystem: subsystem, category: "persistence")

    // os.Logger only
    static let core = Logger(subsystem: subsystem, category: "core")
    static let view = Logger(subsystem: subsystem, category: "view")
    static let ghostty = Logger(subsystem: subsystem, category: "ghostty")
    static let perf = Logger(subsystem: subsystem, category: "perf")
    static let worktree = Logger(subsystem: subsystem, category: "worktree")
    static let git = Logger(subsystem: subsystem, category: "git")
}
