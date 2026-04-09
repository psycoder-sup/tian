import OSLog

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.aterm.app"

    static let core = Logger(subsystem: subsystem, category: "core")
    static let view = Logger(subsystem: subsystem, category: "view")
    static let ghostty = Logger(subsystem: subsystem, category: "ghostty")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let perf = Logger(subsystem: subsystem, category: "perf")
    static let ipc = Logger(subsystem: subsystem, category: "ipc")
    static let worktree = Logger(subsystem: subsystem, category: "worktree")
    static let git = Logger(subsystem: subsystem, category: "git")
}
