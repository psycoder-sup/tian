import OSLog

enum Log {
    static let core = Logger(subsystem: "com.aterm.app", category: "core")
    static let view = Logger(subsystem: "com.aterm.app", category: "view")
    static let ghostty = Logger(subsystem: "com.aterm.app", category: "ghostty")
    static let persistence = Logger(subsystem: "com.aterm.app", category: "persistence")
}
