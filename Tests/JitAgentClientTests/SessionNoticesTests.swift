// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class SessionNoticesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_700_000)

    private func session(_ profile: String, expiresIn seconds: Int64?) -> CLISession {
        CLISession(
            profile: profile,
            expiresUnix: seconds.map { 1_789_700_000 + $0 },
            live: (seconds ?? 1) > 0,
            mint: "clisso get \(profile)"
        )
    }

    func testEachStageIsDueOnce() {
        let sessions = [session("soon", expiresIn: 10 * 60), session("gone", expiresIn: -60), session("later", expiresIn: 3600)]
        let due = SessionNotices.due(sessions, now: now, told: [])
        XCTAssertEqual(due.map(\.profile), ["soon", "gone"])
        XCTAssertEqual(due.map(\.stage), [.soon, .expired])
        XCTAssertEqual(due.first?.mint, "clisso get soon")
        XCTAssertTrue(SessionNotices.due(sessions, now: now, told: Set(due.map(\.key))).isEmpty)
    }

    /// `jit status` lists every session ever captured. One that ran out
    /// days ago must not be announced on every launch.
    func testALongExpiredSessionIsOldNews() {
        XCTAssertTrue(SessionNotices.due([session("stage", expiresIn: -3 * 86400)], now: now, told: []).isEmpty)
    }

    func testNoStampNoNotice() {
        XCTAssertTrue(SessionNotices.due([session("prod", expiresIn: nil)], now: now, told: []).isEmpty)
    }

    /// Told about "soon", then it expires: that is a second, different notice.
    func testExpiryFollowsTheWarning() {
        let soon = SessionNotices.due([session("stage", expiresIn: 60)], now: now, told: [])
        let later = now.addingTimeInterval(120)
        let expired = SessionNotices.due([session("stage", expiresIn: 60)], now: later, told: Set(soon.map(\.key)))
        XCTAssertEqual(expired.map(\.stage), [.expired])
    }

    /// A renewal has a new expiry, so a new key; the old one is dropped.
    func testPruningKeepsOnlyListedSessions() {
        let old = SessionNotice(profile: "stage", expiresUnix: 1_789_700_060, stage: .soon)
        let other = SessionNotice(profile: "prod", expiresUnix: 1_789_000_000, stage: .expired)
        let renewed = session("stage", expiresIn: 7200)
        XCTAssertEqual(SessionNotices.pruned([old.key, other.key], keeping: [renewed]), [])
        let same = session("stage", expiresIn: 60)
        XCTAssertEqual(SessionNotices.pruned([old.key, other.key], keeping: [same]), [old.key])
    }
}
