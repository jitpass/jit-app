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
    /// The session notices already posted, so a relaunch does not repeat
    /// them (SessionNotices keys).
    static let sessionsToldKey = "SessionNoticesTold"

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

    /// Whether the user has ever set either switch, in setup or Settings.
    /// Until then the defaults read as on, but macOS must not ask yet:
    /// setup's finish screen is where that question belongs.
    static var chosen: Bool {
        UserDefaults.standard.object(forKey: decoyPreferenceKey) != nil
            || UserDefaults.standard.object(forKey: changesPreferenceKey) != nil
    }

    static var sessionsTold: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: sessionsToldKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: sessionsToldKey) }
    }

    static var onActivate: (NotificationTarget) -> Void = { _ in }
    private static let delegate = Delegate()

    static func install() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `thread` groups a kind together in Notification Center, so several
    /// decoy readers stack instead of lining up one by one.
    static func post(title: String, body: String, id: String, thread: String, target: NotificationTarget = .audit) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = thread
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
