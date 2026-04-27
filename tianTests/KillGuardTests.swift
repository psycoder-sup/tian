import Testing
import Foundation
@testable import tian

@Suite("KillGuard")
struct KillGuardTests {

    // Use a PID that POSIX `kill()` will reject with ESRCH so the unit
    // tests never accidentally signal a real process. PID 0 (broadcasts
    // to the process group) and PID 1 (launchd) are unsafe to target;
    // a high but valid pid_t value reliably misses any real process.
    private static let unusedPID: pid_t = 0x7FFF_FF00

    @Test func startsAlive() {
        let guardObj = KillGuard(pid: Self.unusedPID)
        #expect(guardObj.currentState == .alive)
    }

    @Test func terminate_flipsToTerminating() {
        let guardObj = KillGuard(pid: Self.unusedPID)
        guardObj.terminate(grace: 60)   // long grace; SIGKILL won't fire during the test
        #expect(guardObj.currentState == .terminating)
        // Cancel the dangling sigkillItem so the test process doesn't keep
        // a global-queue work-item scheduled past the test's lifetime.
        guardObj.markDead()
    }

    @Test func markDead_blocksSubsequentTerminate() {
        let guardObj = KillGuard(pid: Self.unusedPID)
        guardObj.markDead()
        #expect(guardObj.currentState == .dead)

        guardObj.terminate(grace: 60)
        // Still dead — terminate() must be a no-op once markDead() ran.
        #expect(guardObj.currentState == .dead)
    }

    @Test func terminate_isIdempotent() {
        let guardObj = KillGuard(pid: Self.unusedPID)
        guardObj.terminate(grace: 60)
        guardObj.terminate(grace: 60)   // second call does nothing
        #expect(guardObj.currentState == .terminating)
        guardObj.markDead()
    }

    @Test func markDead_cancelsPendingEscalation() async throws {
        // Schedule SIGKILL with a short grace, then markDead() before it
        // fires. The state must remain .dead — escalation must not run.
        let guardObj = KillGuard(pid: Self.unusedPID)
        guardObj.terminate(grace: 0.05)
        guardObj.markDead()
        // Wait past the grace window. If markDead() failed to cancel,
        // escalate() would attempt to read state and (in the buggy case)
        // re-trigger work; the state must stay .dead either way because
        // escalate()'s guard requires .terminating.
        try await Task.sleep(for: .milliseconds(150))
        #expect(guardObj.currentState == .dead)
    }
}
