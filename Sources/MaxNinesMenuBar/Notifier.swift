import Foundation
import MaxNinesKit
import UserNotifications

/// Shows notifications when alerts start and end, and does what their buttons say.
@MainActor
final class Notifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    var onAcknowledge: (Int) -> Void = { _ in }
    var onOpen: (String) -> Void = { _ in }
    /// Whether macOS lets the app show notifications, once it's known.
    @Published private(set) var allowed: Bool?

    private static let firing = "firing"
    private static let other = "other"
    private static let acknowledge = "acknowledge"
    private static let open = "open"

    /// Notifications only work from inside an app bundle, and asking for them
    /// outside one stops the program, as when it's run straight from a build.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    /// Sets up the buttons, and asks to show notifications if any are wanted.
    func start(asking: Bool) {
        guard let center else { return }
        center.delegate = self
        let open = UNNotificationAction(identifier: Notifier.open, title: "Open in MaxNines")
        let acknowledge = UNNotificationAction(identifier: Notifier.acknowledge, title: "Acknowledge")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Notifier.firing, actions: [acknowledge, open], intentIdentifiers: []),
            UNNotificationCategory(identifier: Notifier.other, actions: [open], intentIdentifiers: []),
        ])
        if asking {
            ask()
        } else {
            Task { await checkAllowed() }
        }
    }

    /// Asks macOS to show them, which it only asks the person about once.
    func ask() {
        guard let center else { return }
        Task {
            allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    private func checkAllowed() async {
        guard let center else { return }
        let status = await center.notificationSettings().authorizationStatus
        allowed = status == .notDetermined ? nil : [.authorized, .provisional].contains(status)
    }

    func post(_ notice: Notice) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.sound = .default
        content.categoryIdentifier = notice.acknowledges == nil ? Notifier.other : Notifier.firing
        content.userInfo = ["path": notice.path, "alert": notice.acknowledges ?? 0]
        center.add(UNNotificationRequest(identifier: notice.id, content: content, trigger: nil))
    }

    /// Shown even while the menu is open, as the app never stops being active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let path = info["path"] as? String ?? "/alerts"
        let alert = info["alert"] as? Int ?? 0
        let action = response.actionIdentifier
        await MainActor.run {
            if action == Notifier.acknowledge, alert != 0 {
                onAcknowledge(alert)
            } else if action == Notifier.open || action == UNNotificationDefaultActionIdentifier {
                onOpen(path)
            }
        }
    }
}
