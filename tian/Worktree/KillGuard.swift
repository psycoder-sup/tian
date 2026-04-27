import Foundation

/// Atomic kill-eligibility gate for a child process.
///
/// Foundation's `Process` exposes only the bare PID for termination, and
/// macOS recycles PIDs — so a `kill()` that arrives after the child has
/// reaped can land on an unrelated process. This class closes that window:
/// `terminate(grace:)` is idempotent and schedules a SIGKILL escalation;
/// `markDead()` runs synchronously inside `terminationHandler` *before* the
/// awaiting continuation resumes, so any in-flight or stale kill request
/// becomes a no-op.
final class KillGuard: @unchecked Sendable {
    enum State { case alive, terminating, dead }

    private let lock = NSLock()
    private let pid: pid_t
    private var state: State = .alive
    private var sigkillItem: DispatchWorkItem?

    init(pid: pid_t) { self.pid = pid }

    /// Sends SIGTERM (idempotent) and schedules SIGKILL after `grace`.
    /// No-op once the process has been marked dead.
    func terminate(grace: TimeInterval) {
        lock.lock()
        guard state == .alive else { lock.unlock(); return }
        state = .terminating
        let item = DispatchWorkItem { [weak self] in self?.escalate() }
        sigkillItem = item
        let pidLocal = pid
        lock.unlock()

        kill(pidLocal, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + grace, execute: item)
    }

    private func escalate() {
        lock.lock()
        guard state == .terminating else { lock.unlock(); return }
        let pidLocal = pid
        lock.unlock()
        kill(pidLocal, SIGKILL)
    }

    /// Mark the process as dead. Cancels any pending SIGKILL escalation
    /// and prevents any further `kill()` calls. Must be called from the
    /// process's `terminationHandler` BEFORE resuming the awaiting
    /// continuation.
    func markDead() {
        lock.lock()
        state = .dead
        let item = sigkillItem
        sigkillItem = nil
        lock.unlock()
        item?.cancel()
    }

    /// Test-only: read current state for assertions.
    var currentState: State {
        lock.lock(); defer { lock.unlock() }
        return state
    }
}
