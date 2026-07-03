import OSLog

/// Correctness and timing data captured during session restore.
struct RestoreMetrics: Sendable, Equatable {
    enum Source: String, Sendable { case primary, backup }

    // MARK: - Source & Migration

    var source: Source = .primary
    var migrated: Bool = false
    var fileBytes: Int = 0

    // MARK: - Entity Counts

    var workspaceCount: Int = 0
    var sessionCount: Int = 0
    var paneCount: Int = 0

    // MARK: - Corrections

    var staleWorkspaceIdFixes: Int = 0
    var staleSessionIdFixes: Int = 0
    var stalePaneIdFixes: Int = 0
    var directoryFallbacks: Int = 0

    var totalStaleIdFixes: Int {
        staleWorkspaceIdFixes + staleSessionIdFixes + stalePaneIdFixes
    }

    // MARK: - Timing

    var durationMs: Int = 0

    // MARK: - Logging

    func log() {
        Log.persistence.info("""
            restore completed: \
            source=\(source.rawValue) \
            migrated=\(migrated) \
            duration_ms=\(durationMs) \
            file_bytes=\(fileBytes) \
            workspaces=\(workspaceCount) \
            sessions=\(sessionCount) \
            panes=\(paneCount) \
            stale_ids=\(totalStaleIdFixes) \
            dir_fallbacks=\(directoryFallbacks)
            """)
    }
}

/// Bundles a validated SessionState with the metrics captured during restore.
struct RestoreResult: Sendable {
    let state: SessionState
    let metrics: RestoreMetrics
}
