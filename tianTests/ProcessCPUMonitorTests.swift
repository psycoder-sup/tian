import Foundation
import Testing

@testable import tian

@MainActor
struct ProcessCPUMonitorTests {
    @Test func readsOwnProcessCPUAndThreads() {
        let reading = ProcessCPUMonitor.readCPU()
        #expect(reading != nil)
        // A running test process has burned some CPU and holds at least one thread.
        #expect((reading?.cpuNanos ?? 0) > 0)
        #expect((reading?.threads ?? 0) > 0)
    }

    @Test func cpuTimeIsMonotonic() {
        guard let first = ProcessCPUMonitor.readCPU() else {
            Issue.record("proc_pidinfo returned no reading")
            return
        }
        // Burn a little CPU so the second reading has somewhere to go.
        var sink = 0
        for i in 0..<200_000 { sink &+= i }
        #expect(sink != 0)

        guard let second = ProcessCPUMonitor.readCPU() else {
            Issue.record("proc_pidinfo returned no reading")
            return
        }
        #expect(second.cpuNanos >= first.cpuNanos)
    }

    @Test func durationConvertsToNanoseconds() {
        #expect(ProcessCPUMonitor.nanoseconds(in: .seconds(2)) == 2e9)
        #expect(ProcessCPUMonitor.nanoseconds(in: .milliseconds(500)) == 5e8)
        #expect(ProcessCPUMonitor.nanoseconds(in: .zero) == 0)
    }

    /// Drives one tick directly (rather than waiting out the 30s interval) to
    /// check the seed → delta → percent path produces a live reading.
    @Test func sampleProducesLiveReading() {
        let monitor = ProcessCPUMonitor.shared
        let wasRunning = monitor.isRunning
        monitor.stop()  // clear any stale baseline
        monitor.start()  // seeds the baseline

        var sink = 0
        for i in 0..<2_000_000 { sink &+= i }
        #expect(sink != 0)

        monitor.sample()
        #expect(monitor.cpuPercent > 0)
        #expect(monitor.threadCount > 0)

        if !wasRunning { monitor.stop() }
    }

    /// One test for the shared singleton's lifecycle so the transitions run in
    /// a fixed order; ends stopped, matching a fresh process.
    @Test func startStopLifecycle() {
        let monitor = ProcessCPUMonitor.shared
        let wasRunning = monitor.isRunning

        monitor.start()
        #expect(monitor.isRunning)
        monitor.start()  // idempotent
        #expect(monitor.isRunning)

        monitor.stop()
        #expect(!monitor.isRunning)
        monitor.stop()  // no-op when stopped
        #expect(!monitor.isRunning)

        if wasRunning {
            monitor.start()
        }
    }
}
