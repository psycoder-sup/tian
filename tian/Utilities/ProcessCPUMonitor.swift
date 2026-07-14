import Darwin
import Foundation

/// Samples tian's own CPU time and logs it, so an idle-CPU regression — a
/// runaway animation, a poll that never stops — shows up in the log file after
/// the fact instead of needing a live `sample(1)` run to catch it.
///
/// Deliberately independent of `SystemMonitor` (which reports machine-wide load
/// and stops when every window is occluded): an occluded app burning CPU is the
/// exact state most worth watching, so this loop keeps running regardless.
@MainActor @Observable
final class ProcessCPUMonitor {
    static let shared = ProcessCPUMonitor()

    /// Own-process CPU as a percentage of ONE core — the same basis as `top`'s
    /// %CPU column, so a logged number is directly comparable with what the
    /// user sees in Activity Monitor.
    private(set) var cpuPercent: Double = 0
    private(set) var threadCount: Int = 0

    /// Visible-window count, pushed by `WindowCoordinator` on every occlusion
    /// change. Logged alongside CPU so a hot sample can be attributed: burning
    /// CPU with zero visible windows means the animation/poll gating leaked.
    var visibleWindowCount: Int = 0

    private static let sampleInterval: Duration = .seconds(30)
    /// Log every sample at or above this (a visibly hot app), and otherwise
    /// only one heartbeat per `heartbeatEverySamples`, so a quiet app stays
    /// quiet in the log file.
    private static let noteworthyPercent: Double = 5.0
    private static let heartbeatEverySamples = 10  // 30s × 10 = 5 min

    private var pollingTask: Task<Void, Never>?
    private var previous: (cpuNanos: UInt64, at: ContinuousClock.Instant)?
    private var samplesSinceLog = 0
    private let clock = ContinuousClock()

    private init() {}

    var isRunning: Bool { pollingTask != nil }

    func start() {
        guard pollingTask == nil else { return }
        // Seed the baseline now so the first logged sample covers one interval
        // rather than the whole process lifetime.
        previous = Self.readCPU().map { ($0.cpuNanos, clock.now) }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sampleInterval)
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        previous = nil
    }

    // MARK: - Sampling

    /// Internal (not private) so tests can drive one tick directly instead of
    /// waiting out `sampleInterval`.
    func sample() {
        guard let current = Self.readCPU() else { return }
        let now = clock.now
        defer { previous = (current.cpuNanos, now) }
        guard let previous else { return }

        let elapsedNanos = Self.nanoseconds(in: now - previous.at)
        guard elapsedNanos > 0 else { return }

        let cpuDelta = current.cpuNanos &- previous.cpuNanos
        let percent = Double(cpuDelta) / elapsedNanos * 100

        cpuPercent = percent
        threadCount = current.threads

        samplesSinceLog += 1
        let noteworthy = percent >= Self.noteworthyPercent
        guard noteworthy || samplesSinceLog >= Self.heartbeatEverySamples else { return }
        samplesSinceLog = 0

        let rssMB = Double(AppMetrics.shared.memoryRSSBytes) / (1024 * 1024)
        Log.perf.info(
            "app_cpu: pct=\(String(format: "%.1f", percent)) threads=\(current.threads) rss_mb=\(String(format: "%.1f", rssMB)) visible_windows=\(self.visibleWindowCount)"
        )
    }

    /// Total CPU time this process has consumed, plus its live thread count.
    static func readCPU() -> (cpuNanos: UInt64, threads: Int)? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let read = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, size)
        guard read == size else { return nil }
        return (info.pti_total_user &+ info.pti_total_system, Int(info.pti_threadnum))
    }

    static func nanoseconds(in duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1e9 + Double(parts.attoseconds) / 1e9
    }
}
