import Foundation
import Testing
@testable import tian

@MainActor
struct InspectDiffViewModelTests {

    // MARK: - FR-T18: cancel-on-new

    @Test func cancelsInFlightOnNewRefresh() async throws {
        let fake = BlockingDiffService()
        let vm = InspectDiffViewModel(
            debounceWindow: .milliseconds(20),
            diffService: { dir in await fake.diff(directory: dir) }
        )

        vm.scheduleRefresh(directory: "/tmp/A")
        // Give the debounce time to elapse and the first call to land in the fake.
        try await pollUntilDiff(timeout: .seconds(2)) { fake.callCount == 1 }

        vm.scheduleRefresh(directory: "/tmp/B")
        // Wait for B's debounce to elapse and B's call to register.
        try await pollUntilDiff(timeout: .seconds(2)) { fake.callCount == 2 }

        // Wait for the cancellation handler to record A as cancelled.
        try await pollUntilDiff(timeout: .seconds(2)) {
            fake.cancelledDirectories.contains("/tmp/A")
        }

        // Now release pending continuations so B can complete.
        let bFiles = [
            GitFileDiff(
                path: "b.swift",
                status: .modified,
                additions: 1,
                deletions: 0,
                hunks: [],
                isBinary: false
            )
        ]
        fake.releaseAll(with: bFiles)

        // Wait for B's result to land.
        try await pollUntilDiff(timeout: .seconds(2)) {
            vm.lastDirectory == "/tmp/B"
        }

        #expect(vm.lastDirectory == "/tmp/B")
        #expect(fake.cancelledDirectories.contains("/tmp/A"))
        #expect(vm.files.count == 1)
        #expect(vm.files.first?.path == "b.swift")

        vm.teardown()
    }

    // MARK: - FR-T18: trailing debounce

    @Test func debounceCoalescesBurst() async throws {
        let fake = BlockingDiffService()
        // Use a shorter debounce window to keep tests fast but still
        // exercise the trailing-debounce semantics.
        let window: Duration = .milliseconds(150)
        let vm = InspectDiffViewModel(
            debounceWindow: window,
            diffService: { dir in await fake.diff(directory: dir) }
        )

        // Burst: 5 calls within ~50 ms (well under the 150 ms window).
        for _ in 0..<5 {
            vm.scheduleRefresh(directory: "/tmp/burst")
            try await Task.sleep(for: .milliseconds(10))
        }

        // After the debounce window elapses, exactly one fetch should occur.
        try await pollUntilDiff(timeout: .seconds(2)) { fake.callCount == 1 }
        // Give a small buffer to make sure no extra fetch sneaks in.
        try await Task.sleep(for: .milliseconds(100))
        #expect(fake.callCount == 1)

        // After the debounce gap, a fresh schedule should produce a second
        // fetch.
        try await Task.sleep(for: .milliseconds(200))
        vm.scheduleRefresh(directory: "/tmp/burst")
        try await pollUntilDiff(timeout: .seconds(2)) { fake.callCount == 2 }
        #expect(fake.callCount == 2)

        // Release pending continuations so any in-flight tasks can finish.
        fake.releaseAll(with: [])
        vm.teardown()
    }

    // MARK: - FR-T11: collapse map prune

    @Test func collapseMapSurvivesRefreshWhenFilePresent() async throws {
        let state = InspectTabState()
        let fake = BlockingDiffService()
        let vm = InspectDiffViewModel(
            debounceWindow: .milliseconds(20),
            diffService: { dir in await fake.diff(directory: dir) }
        )
        vm.onFilesRefreshed = { paths in
            // Prune entries from collapse map whose paths are no longer in files.
            for key in state.diffCollapse.keys where !paths.contains(key) {
                state.diffCollapse.removeValue(forKey: key)
            }
        }

        // User collapses auth/middleware.ts
        state.diffCollapse["auth/middleware.ts"] = true

        // First refresh: file is present in the new diff.
        vm.scheduleRefresh(directory: "/tmp/repo")
        try await pollUntilDiff(timeout: .seconds(2)) { fake.callCount == 1 }
        let presentFiles = [
            GitFileDiff(
                path: "auth/middleware.ts",
                status: .modified,
                additions: 1,
                deletions: 0,
                hunks: [],
                isBinary: false
            ),
            GitFileDiff(
                path: "other.swift",
                status: .modified,
                additions: 2,
                deletions: 0,
                hunks: [],
                isBinary: false
            )
        ]
        fake.releaseAll(with: presentFiles)
        try await pollUntilDiff(timeout: .seconds(2)) { vm.files.count == 2 }

        // The collapse flag should still be there since the file is still in files.
        #expect(state.diffCollapse["auth/middleware.ts"] == true)

        // Second refresh: file disappears from diff.
        vm.scheduleRefresh(directory: "/tmp/repo")
        try await pollUntilDiff(timeout: .seconds(2)) { fake.callCount == 2 }
        let withoutFile = [
            GitFileDiff(
                path: "other.swift",
                status: .modified,
                additions: 2,
                deletions: 0,
                hunks: [],
                isBinary: false
            )
        ]
        fake.releaseAll(with: withoutFile)
        try await pollUntilDiff(timeout: .seconds(2)) {
            vm.files.count == 1 && state.diffCollapse["auth/middleware.ts"] == nil
        }

        #expect(state.diffCollapse["auth/middleware.ts"] == nil)
        vm.teardown()
    }

    // MARK: - teardown cancels everything

    @Test func teardownCancelsInFlightAndDebounce() async throws {
        let fake = BlockingDiffService()
        let vm = InspectDiffViewModel(
            debounceWindow: .milliseconds(20),
            diffService: { dir in await fake.diff(directory: dir) }
        )

        vm.scheduleRefresh(directory: "/tmp/X")
        try await pollUntilDiff(timeout: .seconds(2)) { fake.callCount == 1 }

        vm.teardown()

        // Cancellation handler should run for X.
        try await pollUntilDiff(timeout: .seconds(2)) {
            fake.cancelledDirectories.contains("/tmp/X")
        }
        #expect(fake.cancelledDirectories.contains("/tmp/X"))

        // Even after release, no result should land because the task was
        // cancelled and the VM should ignore late results.
        fake.releaseAll(with: [
            GitFileDiff(
                path: "x.swift",
                status: .modified,
                additions: 1,
                deletions: 0,
                hunks: [],
                isBinary: false
            )
        ])
        try await Task.sleep(for: .milliseconds(100))
        #expect(vm.lastDirectory == nil)
        #expect(vm.files.isEmpty)
    }

    // MARK: - nil directory clears state

    @Test func nilDirectoryClearsFilesAndCancels() async throws {
        let fake = BlockingDiffService()
        let vm = InspectDiffViewModel(
            debounceWindow: .milliseconds(20),
            diffService: { dir in await fake.diff(directory: dir) }
        )

        vm.scheduleRefresh(directory: "/tmp/Y")
        try await pollUntilDiff(timeout: .seconds(2)) { fake.callCount == 1 }
        fake.releaseAll(with: [
            GitFileDiff(
                path: "y.swift",
                status: .modified,
                additions: 1,
                deletions: 0,
                hunks: [],
                isBinary: false
            )
        ])
        try await pollUntilDiff(timeout: .seconds(2)) { vm.lastDirectory == "/tmp/Y" }

        // Now schedule with nil — should clear state and cancel.
        vm.scheduleRefresh(directory: nil)

        try await pollUntilDiff(timeout: .seconds(2)) {
            vm.lastDirectory == nil && vm.files.isEmpty
        }
        #expect(vm.lastDirectory == nil)
        #expect(vm.files.isEmpty)

        vm.teardown()
    }
}

// MARK: - Test helpers

@MainActor
private final class BlockingDiffService {
    private var continuations: [CheckedContinuation<[GitFileDiff], Never>] = []
    private(set) var pendingDirectories: [String] = []
    private(set) var cancelledDirectories: [String] = []
    private(set) var callCount = 0

    func diff(directory: String) async -> [GitFileDiff] {
        callCount += 1
        pendingDirectories.append(directory)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { cont in
                continuations.append(cont)
            }
        } onCancel: {
            Task { @MainActor in
                self.cancelledDirectories.append(directory)
            }
        }
    }

    func releaseAll(with files: [GitFileDiff] = []) {
        let conts = continuations
        continuations.removeAll()
        for cont in conts { cont.resume(returning: files) }
    }
}

@MainActor
private func pollUntilDiff(
    timeout: Duration,
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    if !condition() {
        throw PollTimeoutError()
    }
}

private struct PollTimeoutError: Error {}
