// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The one request the app makes to the network: a HEAD to GitHub's
/// `releases/latest`, redirect left unfollowed, whose Location names the
/// current version. Nothing about this Mac goes with it beyond what any
/// HTTPS request carries. Daily, and off with one switch in Settings.
enum UpdateCheck {
    static let preferenceKey = "CheckForUpdates"
    static let lastCheckKey = "LastUpdateCheck"
    static let interval: TimeInterval = 24 * 60 * 60

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: preferenceKey) as? Bool ?? true
    }

    static var lastCheck: Date? {
        UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    static var isDue: Bool {
        guard enabled else {
            return false
        }
        guard let last = lastCheck else {
            return true
        }
        return Date().timeIntervalSince(last) >= interval
    }

    static var current: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    enum Outcome: Equatable {
        case upToDate
        case available(AppVersion)
        case failed(String)
    }

    /// Asks GitHub which version is latest and compares. Off the main
    /// thread; the redirect is captured, not followed.
    static func run() async -> Outcome {
        guard let current else {
            return .failed("this build has no version")
        }
        var request = URLRequest(url: AppUpdate.latestReleaseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        request.setValue("JitPass/\(current)", forHTTPHeaderField: "User-Agent")
        let catcher = RedirectCatcher()
        let session = URLSession(configuration: .ephemeral, delegate: catcher, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("unexpected response")
            }
            guard let location = http.value(forHTTPHeaderField: "Location"),
                  let latest = AppUpdate.version(fromRedirect: location)
            else {
                return .failed("GitHub answered \(http.statusCode) without a release")
            }
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            if let newer = AppUpdate.available(current: current, latest: latest) {
                return .available(newer)
            }
            return .upToDate
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Stops URLSession following the redirect so the 302 itself is the
    /// response the caller sees.
    private final class RedirectCatcher: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }
}
