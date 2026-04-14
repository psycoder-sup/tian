import UserNotifications

enum NotificationError: Error {
    case permissionDenied
}

@MainActor
final class NotificationManager {
    private var isAuthorized: Bool?

    func ensureAuthorized() async throws {
        if let isAuthorized {
            if !isAuthorized { throw NotificationError.permissionDenied }
            return
        }
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
        isAuthorized = granted
        if !granted { throw NotificationError.permissionDenied }
    }

    func sendNotification(message: String, title: String?, subtitle: String?, paneID: UUID) async throws {
        try await ensureAuthorized()

        let content = UNMutableNotificationContent()
        content.title = title ?? "tian"
        if let subtitle { content.subtitle = subtitle }
        content.body = message
        content.sound = .default
        content.userInfo = ["paneId": paneID.uuidString]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}
