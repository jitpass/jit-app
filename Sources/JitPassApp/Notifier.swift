// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import UserNotifications

/// macOS notifications, one kind so far: a decoy was served to a reader
/// outside any grant. Opt-in through Settings; the permission prompt
/// appears the first time it is turned on. Clicking one opens the audit
/// on the serve events.
@MainActor
enum Notifier {
    static let decoyPreferenceKey = "NotifyDecoys"

    /// On by default: a decoy serve is the event the whole design exists
    /// for, and a user who never opens the audit would otherwise never
    /// learn something read their protected file.
    static var decoysEnabled: Bool {
        UserDefaults.standard.object(forKey: decoyPreferenceKey) as? Bool ?? true
    }

    static var onActivate: () -> Void = {}
    private static let delegate = Delegate()

    static func install() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _: UNUserNotificationCenter, didReceive _: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void
        ) {
            Task { @MainActor in
                Notifier.onActivate()
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
