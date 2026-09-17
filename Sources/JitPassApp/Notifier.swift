// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import UserNotifications

/// Where a clicked notification takes the user.
enum NotificationTarget: String {
    case audit, agents, tools
}

/// macOS notifications: a decoy served to a reader outside any grant, a
/// captured session expiring, a scan finding new cached copies. Two
/// switches in Settings; the permission prompt appears the first time one
/// is turned on. Clicking one opens the window that shows the event.
@MainActor
enum Notifier {
    static let decoyPreferenceKey = "NotifyDecoys"
    static let changesPreferenceKey = "NotifyChanges"

    /// On by default: a decoy serve is the event the whole design exists
    /// for, and a user who never opens the audit would otherwise never
    /// learn something read their protected file.
    static var decoysEnabled: Bool {
        UserDefaults.standard.object(forKey: decoyPreferenceKey) as? Bool ?? true
    }

    /// Sessions and caches: the panel already shows a dot for both; this
    /// says it out loud for a user who does not open the panel.
    static var changesEnabled: Bool {
        UserDefaults.standard.object(forKey: changesPreferenceKey) as? Bool ?? true
    }

    static var onActivate: (NotificationTarget) -> Void = { _ in }
    private static let delegate = Delegate()

    static func install() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, id: String, target: NotificationTarget = .audit) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["target": target.rawValue]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void
        ) {
            let raw = response.notification.request.content.userInfo["target"] as? String ?? ""
            let target = NotificationTarget(rawValue: raw) ?? .audit
            Task { @MainActor in
                Notifier.onActivate(target)
                done()
            }
        }

        func userNotificationCenter(
            _: UNUserNotificationCenter, willPresent _: UNNotification,
            withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            done([.banner, .sound])
        }
    }
}
