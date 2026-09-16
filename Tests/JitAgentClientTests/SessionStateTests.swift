// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class SessionStateTests: XCTestCase {
    private func response(unlocked: Bool, expires: Int64 = 0, lockCause: String? = nil) -> AgentResponse {
        var r = AgentResponse(ok: true)
        r.unlocked = unlocked
        r.expiresInSeconds = expires
        if let lockCause {
            r.lastLock = SessionEvent(unixTime: 0, kind: "lock", cause: lockCause)
        }
        return r
    }

    func testUnlockedCountsDown() {
        let s = SessionState(response: response(unlocked: true, expires: 252))
        XCTAssertEqual(s, .unlocked(expiresIn: 252, ceilingAt: nil))
        XCTAssertEqual(s.headline, "Unlocked")
        XCTAssertEqual(s.detail, "locks in 4:12", "no ceiling from an older agent, so none is claimed")
    }

    func testUnlockedNamesTheCeilingWhenReported() {
        var r = response(unlocked: true, expires: 252)
        r.ceilingInSeconds = 3600
        let now = Date(timeIntervalSince1970: 1_789_200_000)
        let s = SessionState(response: r, now: now)
        XCTAssertEqual(s.detail, "locks in 4:12 · no later than \(SessionState.clock(now.addingTimeInterval(3600)))")
    }

    func testLockedCarriesTheCause() {
        let s = SessionState(response: response(unlocked: false, lockCause: "screen locked"))
        XCTAssertEqual(s, .locked(reason: "screen locked"))
        XCTAssertEqual(s.detail, "screen locked")
    }

    func testCountdownNeverNegative() {
        XCTAssertEqual(SessionState.countdown(-5), "0:00")
        XCTAssertEqual(SessionState.countdown(61), "1:01")
    }
}
