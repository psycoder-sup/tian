import Darwin
import OSLog

/// Lightweight app-level performance metrics singleton.
/// Collects timing data from ghostty init, surface creation, and session restore.
/// The debug overlay reads from this via `@Observable`.
@MainActor @Observable
final class AppMetrics {
    static let shared = AppMetrics()

    // MARK: - Ghostty Init

    private(set) var ghosttyInitMs: Double = 0
    private(set) var ghosttyAppNewMs: Double = 0

    var ghosttyTotalInitMs: Double {
        ghosttyInitMs + ghosttyAppNewMs
    }

    // MARK: - Surface Creation

    private(set) var surfaceCreationCount: Int = 0
    private(set) var surfaceCreationTotalMs: Double = 0
    private(set) var surfaceCreationLastMs: Double = 0

    var surfaceCreationAvgMs: Double {
        surfaceCreationCount > 0 ? surfaceCreationTotalMs / Double(surfaceCreationCount) : 0
    }

    // MARK: - Session Restore

    private(set) var restoreDurationMs: Int = 0
    private(set) var restorePaneCount: Int = 0

    // MARK: - Memory

    var memoryRSSBytes: UInt64 {
        readRSS()
    }

    var memoryRSSFormatted: String {
        let mb = Double(memoryRSSBytes) / (1024 * 1024)
        return String(format: "%.1f MB", mb)
    }

    // MARK: - Recording

    func recordGhosttyInit(initMs: Double, appNewMs: Double) {
        ghosttyInitMs = initMs
        ghosttyAppNewMs = appNewMs
        let total = initMs + appNewMs
        Log.perf.info(
            "ghostty_init: init_ms=\(Int(initMs)) app_new_ms=\(Int(appNewMs)) total_ms=\(Int(total))"
        )
    }

    func recordSurfaceCreation(durationMs: Double) {
        surfaceCreationCount += 1
        surfaceCreationTotalMs += durationMs
        surfaceCreationLastMs = durationMs
        let avg = surfaceCreationAvgMs
        Log.perf.info(
            "surface_created: duration_ms=\(Int(durationMs)) count=\(self.surfaceCreationCount) avg_ms=\(Int(avg))"
        )
    }

    func recordRestore(metrics: RestoreMetrics) {
        restoreDurationMs = metrics.durationMs
        restorePaneCount = metrics.paneCount
    }

    // MARK: - Private

    private func readRSS() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), ptr, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    private init() {}
}
