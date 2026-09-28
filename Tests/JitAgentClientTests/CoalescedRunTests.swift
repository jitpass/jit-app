// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class CoalescedRunTests: XCTestCase {
    /// Several vault reloads in a row: one walk of home, then one more, so
    /// no older walk can land after a newer one.
    func testAsksWhileRunningFoldIntoOneRerun() {
        var run = CoalescedRun()
        XCTAssertTrue(run.ask())
        XCTAssertFalse(run.ask())
        XCTAssertFalse(run.ask())
        XCTAssertTrue(run.finished(), "one rerun for the asks it missed")
        XCTAssertTrue(run.ask(), "the rerun starts")
        XCTAssertFalse(run.finished(), "and nothing after it")
    }
}
