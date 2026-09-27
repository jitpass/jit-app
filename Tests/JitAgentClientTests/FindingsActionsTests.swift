// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// A Findings action that fails says so in Findings, and the rescan it
/// asks for is never lost to a scan already running (2026-09-27: a Clean
/// Caches that jit refused changed nothing and said nothing; one that
/// worked left its rows on screen until the window was reopened).
final class FindingsActionsTests: XCTestCase {
    func testAFailureNamesTheVerbAndJitsOwnLine() {
        XCTAssertEqual(
            ScanWording.actionFailed("Clean Caches", line: "the vault is locked: Touch ID was cancelled\n"),
            "Clean Caches failed · the vault is locked: Touch ID was cancelled"
        )
    }

    func testAFailureWithNoLineSaysJitDidNotSayWhy() {
        XCTAssertEqual(ScanWording.actionFailed("Undo", line: "  "), "Undo failed · jit did not say why")
    }

    func testARequestStartsAtOnceWhenNothingRuns() {
        var queue = ScanQueue()
        let request = ScanRequest(wholeMac: true, kind: .afterProtect, deep: false)
        XCTAssertEqual(queue.ask(request, running: false), request)
        XCTAssertNil(queue.next())
    }

    func testARescanAskedForDuringAScanWaitsAndRunsNext() {
        var queue = ScanQueue()
        let rescan = ScanRequest(wholeMac: true, kind: .afterProtect, deep: false)
        XCTAssertNil(queue.ask(rescan, running: true), "it must not start over the running scan")
        XCTAssertEqual(queue.next(), rescan, "and it must not be dropped")
        XCTAssertNil(queue.next(), "it runs once")
    }

    func testRequestsWaitingTogetherBecomeOneRunThatAnswersBoth() {
        var queue = ScanQueue()
        _ = queue.ask(ScanRequest(wholeMac: false, kind: .byHand, deep: false), running: true)
        _ = queue.ask(ScanRequest(wholeMac: true, kind: .afterProtect, deep: false), running: true)
        XCTAssertEqual(queue.next(), ScanRequest(wholeMac: true, kind: .afterProtect, deep: false))
    }

    func testADeepRequestKeepsItsKindWhenARegularOneFollows() {
        let deep = ScanRequest(wholeMac: true, kind: .deep, deep: true)
        let regular = ScanRequest(wholeMac: true, kind: .afterProtect, deep: false)
        XCTAssertEqual(deep.merged(with: regular), deep)
        XCTAssertEqual(regular.merged(with: deep), deep)
    }
}
