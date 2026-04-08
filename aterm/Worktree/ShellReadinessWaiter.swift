import Foundation

/// Indicates how shell readiness was detected.
enum ShellReadyReason: Sendable {
    /// Shell emitted an OSC 7 working directory notification.
    case osc7
    /// Timed out waiting for OSC 7; fell back to delay.
    case timeout
}

/// Waits for shell readiness by observing OSC 7 (working directory) notifications,
/// with a timeout fallback for shells that don't emit OSC 7.
enum ShellReadinessWaiter {

    /// Waits until the given surface emits an OSC 7 pwd notification, or the timeout expires.
    /// - Parameters:
    ///   - surfaceID: The UUID of the surface to monitor.
    ///   - timeout: Maximum seconds to wait before returning.
    /// - Returns: The reason readiness was determined.
    @MainActor @discardableResult
    static func waitForReady(surfaceID: UUID, timeout: TimeInterval) async -> ShellReadyReason {
        await withCheckedContinuation { (continuation: CheckedContinuation<ShellReadyReason, Never>) in
            var resumed = false

            func resume(_ reason: ShellReadyReason) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: reason)
            }

            var observer: NSObjectProtocol?
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                resume(.timeout)
            }

            observer = NotificationCenter.default.addObserver(
                forName: GhosttyApp.surfacePwdNotification, object: nil, queue: .main
            ) { notification in
                guard let notifSurfaceID = notification.userInfo?["surfaceId"] as? UUID,
                      notifSurfaceID == surfaceID else { return }
                timeoutTask.cancel()
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                resume(.osc7)
            }
        }
    }
}
