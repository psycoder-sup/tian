import Darwin
import Foundation

/// Polls macOS system load metrics (CPU + RAM) and exposes a rolling history
/// for sparklines in the status bar.
///
/// CPU is computed across all logical cores using `host_processor_info` ticks
/// (user/system/idle/nice). RAM "used" follows Activity Monitor's rough
/// definition: active + wired + compressed.
@MainActor @Observable
final class SystemMonitor {
    static let shared = SystemMonitor()

    /// One sample's worth of state. Bundled into a single observable so a
    /// successful tick wakes observers once per window instead of firing
    /// five separate notifications. (The `Equatable` write-gate also
    /// suppresses the rare both-reads-failed tick.)
    struct Snapshot: Equatable {
        var cpu: Double = 0
        var ram: Double = 0
        var ramUsedBytes: UInt64 = 0
        var cpuHistory: [Double] = Array(repeating: 0, count: SystemMonitor.historyCapacity)
        var ramHistory: [Double] = Array(repeating: 0, count: SystemMonitor.historyCapacity)
    }

    nonisolated static let historyCapacity = 24
    /// 2s matches Activity Monitor's lighter polling — quiet enough to be
    /// cheap, lively enough to feel real.
    private static let sampleInterval: Duration = .seconds(2)

    private(set) var snapshot = Snapshot()
    let ramTotalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory

    private var pollingTask: Task<Void, Never>?
    private var previousCPUTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []

    private init() {}

    func start() {
        guard pollingTask == nil else { return }
        // Seed once so the first sparkline isn't all zeros.
        sample()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sampleInterval)
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    // MARK: - Sampling

    private func sample() {
        var next = snapshot
        if let cpu = readCPULoad() {
            next.cpu = cpu
            Self.appendTrim(cpu, to: &next.cpuHistory)
        }
        if let ram = readRAMUsage() {
            next.ramUsedBytes = ram.used
            next.ram = ram.total > 0 ? Double(ram.used) / Double(ram.total) : 0
            Self.appendTrim(next.ram, to: &next.ramHistory)
        }
        if next != snapshot {
            snapshot = next
        }
    }

    private static func appendTrim(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > historyCapacity {
            history.removeFirst(history.count - historyCapacity)
        }
    }

    // MARK: - CPU

    /// Returns the fraction of CPU time spent non-idle since the previous
    /// sample, averaged across all logical cores. Cores whose tick counters
    /// went backwards (counter reset, core offline) are skipped rather than
    /// silently wrapping.
    private func readCPULoad() -> Double? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &infoArray,
            &infoCount
        )
        guard result == KERN_SUCCESS, let infoArray else { return nil }
        defer {
            let bytes = vm_size_t(MemoryLayout<integer_t>.stride * Int(infoCount))
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: infoArray)), bytes)
        }

        let cpuStates = Int(CPU_STATE_MAX)
        var current: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        current.reserveCapacity(Int(cpuCount))
        for i in 0..<Int(cpuCount) {
            let base = i * cpuStates
            let user = UInt32(bitPattern: infoArray[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: infoArray[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: infoArray[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: infoArray[base + Int(CPU_STATE_NICE)])
            current.append((user, system, idle, nice))
        }

        // First sample (or core-count change after sleep/wake) — stash ticks
        // and skip this tick so cumulative counters don't surface as a fake
        // spike or a 0% dip in the sparkline.
        guard previousCPUTicks.count == current.count else {
            previousCPUTicks = current
            return nil
        }

        var loadSum = 0.0
        var counted = 0
        for (prev, now) in zip(previousCPUTicks, current) {
            guard now.user >= prev.user,
                  now.system >= prev.system,
                  now.idle >= prev.idle,
                  now.nice >= prev.nice
            else { continue }
            let busy = UInt64(now.user - prev.user)
                + UInt64(now.system - prev.system)
                + UInt64(now.nice - prev.nice)
            let total = busy + UInt64(now.idle - prev.idle)
            if total > 0 {
                loadSum += Double(busy) / Double(total)
                counted += 1
            }
        }
        previousCPUTicks = current
        guard counted > 0 else { return nil }
        return loadSum / Double(counted)
    }

    // MARK: - RAM

    private func readRAMUsage() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64_data_t()
        var size = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &size)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(getpagesize())
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        return (active + wired + compressed, ramTotalBytes)
    }
}
