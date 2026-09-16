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
        XCTAssertEqual(s, .unlocked(expiresIn: 252))
        XCTAssertEqual(s.headline, "Unlocked")
        XCTAssertEqual(s.detail, "locks in 4:12")
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
