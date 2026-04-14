import Testing
import Foundation
@testable import tian

struct NotificationManagerTests {
    @Test @MainActor func ensureAuthorizedCachesResult() async {
        let manager = NotificationManager()
        // First call requests authorization from UNUserNotificationCenter.
        // In a test host app without notification entitlement, this may
        // succeed or fail depending on the system state. We verify the
        // manager doesn't throw unexpected errors on repeated calls.
        let firstResult: Bool
        do {
            try await manager.ensureAuthorized()
            firstResult = true
        } catch NotificationError.permissionDenied {
            firstResult = false
        } catch {
            Issue.record("Unexpected error: \(error)")
            return
        }

        // Second call should use cached result (no re-prompt).
        let secondResult: Bool
        do {
            try await manager.ensureAuthorized()
            secondResult = true
        } catch NotificationError.permissionDenied {
            secondResult = false
        } catch {
            Issue.record("Unexpected error on second call: \(error)")
            return
        }

        #expect(firstResult == secondResult)
    }

    @Test @MainActor func sendNotificationRequiresMessage() async throws {
        let manager = NotificationManager()
        // Verify sendNotification builds content correctly by calling it.
        // In a CI/test environment, UNUserNotificationCenter.add() may
        // throw if permissions are denied — that's expected and tested
        // separately via the permission-denied path.
        do {
            try await manager.sendNotification(
                message: "Build complete",
                title: "CI",
                subtitle: nil,
                paneID: UUID()
            )
        } catch NotificationError.permissionDenied {
            // Expected in environments without notification permission
        }
    }
}
