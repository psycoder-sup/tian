import Testing
import Foundation
@testable import tian

@MainActor
struct RefreshSchedulerTests {

    @Test func coalescesRapidSubmitsForSameKey() async throws {
        var fired: [String] = []
        let scheduler = RefreshScheduler<String>(
            debounce: .milliseconds(30),
            maxConcurrent: 4
        ) { key in
            await MainActor.run { fired.append(key) }
        }

        scheduler.schedule(key: "repo-a")
        scheduler.schedule(key: "repo-a")
        scheduler.schedule(key: "repo-a")

        try await Task.sleep(for: .milliseconds(120))

        #expect(fired == ["repo-a"])
    }

    @Test func capsConcurrentExecutions() async throws {
        actor Counter {
            var inFlight = 0
            var peak = 0
            func enter() { inFlight += 1; peak = max(peak, inFlight) }
            func exit() { inFlight -= 1 }
            func snapshot() -> Int { peak }
        }
        let counter = Counter()

        let scheduler = RefreshScheduler<String>(
            debounce: .milliseconds(5),
            maxConcurrent: 2
        ) { _ in
            await counter.enter()
            try? await Task.sleep(for: .milliseconds(40))
            await counter.exit()
        }

        for i in 0..<6 {
            scheduler.schedule(key: "k\(i)")
        }

        try await Task.sleep(for: .milliseconds(500))

        let peak = await counter.snapshot()
        #expect(peak <= 2)
    }

    @Test func cancelAllPreventsFurtherDelivery() async throws {
        var fired: [String] = []
        let scheduler = RefreshScheduler<String>(
            debounce: .milliseconds(20),
            maxConcurrent: 4
        ) { key in
            await MainActor.run { fired.append(key) }
        }

        scheduler.schedule(key: "a")
        scheduler.schedule(key: "b")
        scheduler.cancelAll()

        try await Task.sleep(for: .milliseconds(80))

        #expect(fired.isEmpty)
    }

    @Test func cancelKeyPreventsThatKeyOnly() async throws {
        var fired: [String] = []
        let scheduler = RefreshScheduler<String>(
            debounce: .milliseconds(20),
            maxConcurrent: 4
        ) { key in
            await MainActor.run { fired.append(key) }
        }

        scheduler.schedule(key: "a")
        scheduler.schedule(key: "b")
        scheduler.cancel(key: "a")

        try await Task.sleep(for: .milliseconds(80))

        #expect(fired == ["b"])
    }

    @Test func scheduleAfterCancelStillFires() async throws {
        var fired: [String] = []
        let scheduler = RefreshScheduler<String>(
            debounce: .milliseconds(20),
            maxConcurrent: 4
        ) { key in
            await MainActor.run { fired.append(key) }
        }

        scheduler.schedule(key: "a")
        scheduler.cancel(key: "a")
        scheduler.schedule(key: "a")

        try await Task.sleep(for: .milliseconds(80))

        #expect(fired == ["a"])
    }
}
