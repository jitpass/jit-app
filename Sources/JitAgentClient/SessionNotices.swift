// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One thing to say about a captured session: it is about to run out, or
/// it has. Keyed by profile, expiry and stage, so a renewed session (a new
/// expiry) is new news and a relaunch is not.
public struct SessionNotice: Equatable, Sendable {
    public enum Stage: String, Sendable {
        case soon, expired
    }

    public var profile: String
    public var expiresUnix: Int64
    public var stage: Stage
    public var mint: String?

    public var key: String {
        "\(profile):\(expiresUnix):\(stage.rawValue)"
    }
}

/// Decides the session notices from expiry stamps alone, so the minute
/// timer behind them costs no `jit` run: every `jit status` is a line in
/// `jit audit`, and one a minute was most of that log.
public enum SessionNotices {
    /// A session within this of its end is announced as about to expire.
    public static let warning: TimeInterval = 15 * 60

    /// A session that ran out longer ago than this is old news: `jit
    /// status` lists every session it has ever captured, so without a
    /// limit the first launch after an update (or a lost preference)
    /// would announce every stale profile at once.
    public static let staleAfter: TimeInterval = 24 * 3600

    /// The notices due at `now` that `told` does not already hold, at
    /// most one per session: the later stage wins.
    public static func due(_ sessions: [CLISession], now: Date, told: Set<String>) -> [SessionNotice] {
        sessions.compactMap { session in
            guard let expires = session.expiresUnix, expires > 0 else {
                return nil
            }
            let left = TimeInterval(expires) - now.timeIntervalSince1970
            let stage: SessionNotice.Stage
            if left <= 0 {
                guard -left <= staleAfter else {
                    return nil
                }
                stage = .expired
            } else if left <= warning {
                stage = .soon
            } else {
                return nil
            }
            let notice = SessionNotice(profile: session.profile, expiresUnix: expires, stage: stage, mint: session.mint)
            return told.contains(notice.key) ? nil : notice
        }
    }

    /// The keys worth keeping: those of sessions still listed. A renewed or
    /// deleted session's keys can never match again.
    public static func pruned(_ told: Set<String>, keeping sessions: [CLISession]) -> Set<String> {
        let live = Set(sessions.compactMap { session in session.expiresUnix.map { "\(session.profile):\($0):" } })
        return told.filter { key in
            live.contains { key.hasPrefix($0) }
        }
    }
}
