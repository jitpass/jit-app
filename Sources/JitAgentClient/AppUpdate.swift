// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A JitPass version: the bundled jit's three parts plus an optional fourth
/// for an app-only release (1.6.2, 1.6.1.3). Compared part by part with a
/// missing part as zero, so 1.6.2 is newer than 1.6.1.3.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    public init?(_ text: String) {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (3 ... 4).contains(parts.count), parts.allSatisfy({ $0 != nil }) else {
            return nil
        }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".")
    }

    /// A local build stamps 0.0.0, and a check against it would call every
    /// release an update.
    public var isDevelopment: Bool {
        parts.allSatisfy { $0 == 0 }
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0 ..< count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// Where a newer JitPass comes from. GitHub's `releases/latest` answers with
/// a redirect to the release's tag page, so one request with the redirect
/// left unfollowed says which version is current without an API token or a
/// rate limit. The download goes through dl.jitpass.com, the same one-hop
/// redirect the cask uses; GitHub stays the only origin serving bytes.
public enum AppUpdate {
    public static let latestReleaseURL = URL(string: "https://github.com/jitpass/jit-app/releases/latest")!
    public static let downloadURL = URL(string: "https://dl.jitpass.com/jitpass/jit-app/releases/latest/download/JitPass-arm64.zip")!
    public static let releasesPageURL = URL(string: "https://github.com/jitpass/jit-app/releases")!

    /// The version a `releases/latest` redirect points at: its Location is
    /// `https://github.com/jitpass/jit-app/releases/tag/v1.6.3`.
    public static func version(fromRedirect location: String) -> AppVersion? {
        guard let url = URL(string: location), url.host == "github.com" else {
            return nil
        }
        let parts = url.pathComponents
        guard parts.count >= 2, parts[parts.count - 2] == "tag" else {
            return nil
        }
        return AppVersion(parts[parts.count - 1])
    }

    /// The newer version when `latest` is one, nil when this copy is current
    /// or is a development build.
    public static func available(current: AppVersion, latest: AppVersion) -> AppVersion? {
        guard !current.isDevelopment, current < latest else {
            return nil
        }
        return latest
    }
}
