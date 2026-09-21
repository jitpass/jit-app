// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import UserNotifications

/// What macOS allows this app, as Settings needs to say it.
enum NotificationPermission {
    case unknown, allowed, denied, notAsked
}

/// Where a clicked notification takes the user.
enum NotificationTarget: String {
    case audit, agents, tools, findings
}

/// macOS notifications: a decoy served to a reader outside any grant, a
/// captured session expiring, a scheduled scan finding something the
/// previous one did not. Two switches in Settings; the permission prompt
/// appears the first time one is turned on. Clicking one opens the window
/// that shows the event.
@MainActor
enum Notifier {
    static let decoyPreferenceKey = "NotifyDecoys"
    static let changesPreferenceKey = "NotifyChanges"
    /// The session notices already posted, so a relaunch does not repeat
    /// them (SessionNotices keys).
    static let sessionsToldKey = "SessionNoticesTold"
    /// The counted finding ids of the last whole-Mac scan, and when it
    /// ran, so the next scan can say what is new and a notification can
    /// name it. Ids only, never a value or a path.
    static let knownFindingsKey = "KnownFindingIDs"
    static let knownFindingsAtKey = "KnownFindingsAt"

    /// On by default: a decoy serve is the event the whole design exists
    /// for, and a user who never opens the audit would otherwise never
    /// learn something read their protected file.
    static var decoysEnabled: Bool {
        UserDefaults.standard.object(forKey: decoyPreferenceKey) as? Bool ?? true
    }

    /// Sessions and new findings: the panel already shows a dot for both;
    /// this says it out loud for a user who does not open the panel.
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

    /// macOS asks once; after an answer this returns at once with it.
    /// `then` runs on the main actor when the question is settled.
    static func requestPermission(then done: (@MainActor () -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in done?() }
        }
    }

    /// Whether macOS will show what `post` sends. Asked fresh each time:
    /// the answer lives in System Settings and changes behind the app.
    static func readPermission(_ done: @escaping @MainActor (NotificationPermission) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let permission: NotificationPermission = switch settings.authorizationStatus {
            case .authorized, .provisional: .allowed
            case .denied: .denied
            case .notDetermined: .notAsked
            @unknown default: .unknown
            }
            Task { @MainActor in done(permission) }
        }
    }

    /// System Settings › Notifications, at this app's page.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.jitpass.app"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
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
