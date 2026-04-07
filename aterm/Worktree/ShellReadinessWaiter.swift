import Foundation

/// Waits for shell readiness by observing OSC 7 (working directory) notifications,
/// with a timeout fallback for shells that don't emit OSC 7.
enum ShellReadinessWaiter {

    /// Waits until the given surface emits an OSC 7 pwd notification, or the timeout expires.
    /// - Parameters:
    ///   - surfaceID: The UUID of the surface to monitor.
    ///   - timeout: Maximum seconds to wait before returning.
    @MainActor
    static func waitForReady(surfaceID: UUID, timeout: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false

            func resume() {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }

            var observer: NSObjectProtocol?
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                resume()
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
                resume()
            }
        }
    }
}
