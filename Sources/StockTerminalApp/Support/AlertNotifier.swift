import AppKit
import UserNotifications

/// 价格预警触发时的声音 + macOS 通知（需用户授权；失败时静默降级）。
@MainActor
enum AlertNotifier {
    private static var requestedAuth = false

    static func prepare() {
        guard !requestedAuth else { return }
        requestedAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(title: String, body: String) {
        // 系统提示音（不依赖自定义资源）
        NSSound.beep()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "stockterminal.alert.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
