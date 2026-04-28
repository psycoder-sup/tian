import Testing
import Foundation
@testable import tian

@MainActor
struct EventCoalescerTests {

    @Test func deliversLastValuePerKeyAfterInterval() async throws {
        var delivered: [(UUID, String)] = []
        let coalescer = EventCoalescer<UUID, String>(interval: .milliseconds(20)) { key, value in
            delivered.append((key, value))
        }
        let key = UUID()

        coalescer.submit(key: key, value: "first")
        coalescer.submit(key: key, value: "second")
        coalescer.submit(key: key, value: "third")

        // Wait past the interval.
        try await Task.sleep(for: .milliseconds(60))

        #expect(delivered.count == 1)
        #expect(delivered.first?.1 == "third")
    }

    @Test func separateKeysFireIndependently() async throws {
        var delivered: [(UUID, String)] = []
        let coalescer = EventCoalescer<UUID, String>(interval: .milliseconds(20)) { key, value in
            delivered.append((key, value))
        }
        let a = UUID()
        let b = UUID()

        coalescer.submit(key: a, value: "alpha")
        coalescer.submit(key: b, value: "beta")

        try await Task.sleep(for: .milliseconds(60))

        #expect(delivered.count == 2)
        #expect(delivered.contains(where: { $0.0 == a && $0.1 == "alpha" }))
        #expect(delivered.contains(where: { $0.0 == b && $0.1 == "beta" }))
    }

    @Test func laterSubmitResetsTimer() async throws {
        var delivered: [String] = []
        let coalescer = EventCoalescer<String, String>(interval: .milliseconds(40)) { _, value in
            delivered.append(value)
        }

        coalescer.submit(key: "k", value: "v1")
        try await Task.sleep(for: .milliseconds(20))
        coalescer.submit(key: "k", value: "v2")
        try await Task.sleep(for: .milliseconds(20))
        // 40ms total since first, but only 20ms since last — should not have fired yet.
        #expect(delivered.isEmpty)

        try await Task.sleep(for: .milliseconds(40))
        #expect(delivered == ["v2"])
    }

    @Test func cancelPreventsDelivery() async throws {
        var delivered: [String] = []
        let coalescer = EventCoalescer<String, String>(interval: .milliseconds(20)) { _, value in
            delivered.append(value)
        }

        coalescer.submit(key: "k", value: "v")
        coalescer.cancel(key: "k")

        try await Task.sleep(for: .milliseconds(60))

        #expect(delivered.isEmpty)
    }
}
