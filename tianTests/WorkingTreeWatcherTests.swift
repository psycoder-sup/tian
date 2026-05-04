import Foundation
import os
import Testing
@testable import tian

struct WorkingTreeWatcherTests {

    // Watcher fires the debounced callback when a file is created in the watched root.
    @Test func watcherFiresOnFileCreation() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let tracker = CallbackTracker()
        let watcher = WorkingTreeWatcher(
            root: dir,
            debounce: .milliseconds(100),
            onChange: { tracker.fire() }
        )
        defer { watcher.stop() }

        let filePath = (dir as NSString).appendingPathComponent("created.txt")
        try "hello".write(toFile: filePath, atomically: true, encoding: .utf8)

        // Bounded poll: FSEvents + 100 ms debounce typically delivers within
        // a few hundred ms; allow ~3 s on slow CI.
        try await waitForCondition { tracker.fireCount >= 1 }
        #expect(tracker.fireCount >= 1)
    }

    // Coalesces a burst of changes into a single trailing-debounced callback.
    @Test func watcherCoalescesBurstIntoSingleCall() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let tracker = CallbackTracker()
        let watcher = WorkingTreeWatcher(
            root: dir,
            debounce: .milliseconds(250),
            onChange: { tracker.fire() }
        )
        defer { watcher.stop() }

        // Write a burst of files synchronously — they should all land within
        // the 250 ms debounce window and produce one callback, not many.
        for i in 0..<10 {
            let path = (dir as NSString).appendingPathComponent("burst-\(i).txt")
            try "x".write(toFile: path, atomically: true, encoding: .utf8)
        }

        // Wait for at least one fire.
        try await waitForCondition { tracker.fireCount >= 1 }
        // Then wait a touch longer than the debounce to confirm the count
        // didn't blow past 1 from a follow-up trailing edge.
        try await Task.sleep(for: .milliseconds(500))
        // Allow up to 2 — FSEvents can deliver in two adjacent batches when
        // the burst straddles the latency window. > 2 means the debounce
        // is broken.
        #expect(tracker.fireCount <= 2, "expected coalesced callback count, got \(tracker.fireCount)")
    }

    // After stop(), no further callbacks fire even when the FS is changed.
    @Test func stopPreventsFurtherCallbacks() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let tracker = CallbackTracker()
        let watcher = WorkingTreeWatcher(
            root: dir,
            debounce: .milliseconds(100),
            onChange: { tracker.fire() }
        )

        // Trigger one event so we know the watcher is wired.
        let firstPath = (dir as NSString).appendingPathComponent("first.txt")
        try "1".write(toFile: firstPath, atomically: true, encoding: .utf8)
        try await waitForCondition { tracker.fireCount >= 1 }

        watcher.stop()
        let baseline = tracker.fireCount

        // After stop, additional changes must not increment the count.
        for i in 0..<5 {
            let path = (dir as NSString).appendingPathComponent("post-\(i).txt")
            try "x".write(toFile: path, atomically: true, encoding: .utf8)
        }
        // Wait long enough that any in-flight or trailing fire would have
        // landed (debounce + FSEvents latency).
        try await Task.sleep(for: .milliseconds(800))
        #expect(tracker.fireCount == baseline)
    }

    // MARK: - Helpers

    /// Polls `condition` until true or `timeout` elapses. Bounded so a broken
    /// watcher fails fast instead of stalling the suite.
    private func waitForCondition(
        timeout: Duration = .seconds(3),
        pollInterval: Duration = .milliseconds(50),
        _ condition: @Sendable () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
        }
    }

    /// Thread-safe counter for callbacks fired off the FSEvents queue.
    final class CallbackTracker: Sendable {
        private let state = OSAllocatedUnfairLock<Int>(initialState: 0)
        var fireCount: Int { state.withLock { $0 } }
        func fire() { state.withLock { $0 += 1 } }
    }

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tian-watcher-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}
