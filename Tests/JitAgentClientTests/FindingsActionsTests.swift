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

    func testRequestsOfOneScopeWaitingTogetherBecomeOneRun() {
        var queue = ScanQueue()
        _ = queue.ask(ScanRequest(wholeMac: true, kind: .afterProtect, deep: false), running: true)
        _ = queue.ask(ScanRequest(wholeMac: true, kind: .afterProtect, deep: false), running: true)
        XCTAssertEqual(queue.next(), ScanRequest(wholeMac: true, kind: .afterProtect, deep: false))
        XCTAssertNil(queue.next())
    }

    /// Review of #63: a folder the user picked, folded into a Protect's
    /// whole-Mac rescan, was never shown (a whole-Mac report does not
    /// replace a folder on screen), and a deep one read the vault for the
    /// whole Mac.
    func testAFolderScanIsNeverWidenedToTheWholeMac() {
        var queue = ScanQueue()
        let folder = ScanRequest(wholeMac: false, kind: .deep, deep: true)
        let rescan = ScanRequest(wholeMac: true, kind: .afterProtect, deep: false)
        _ = queue.ask(folder, running: true)
        _ = queue.ask(rescan, running: true)
        XCTAssertEqual(queue.next(), folder, "the folder the user picked runs first, as picked")
        XCTAssertEqual(queue.next(), rescan, "the rescan still runs, after it")
        XCTAssertNil(queue.next())
    }

    func testADeepRequestKeepsItsKindWhenARegularOneFollows() {
        let deep = ScanRequest(wholeMac: true, kind: .deep, deep: true)
        let regular = ScanRequest(wholeMac: true, kind: .afterProtect, deep: false)
        XCTAssertEqual(deep.merged(with: regular), deep)
        XCTAssertEqual(regular.merged(with: deep), deep)
    }

    private func front(
        findings: Bool = false, decoys: Bool = false, agents: Bool = false, agentsOpen: Bool = false, toolsOpen: Bool = false
    ) -> OutcomeWindow {
        OutcomeWindow.front(
            findingsKey: findings, decoysKey: decoys, agentsKey: agents, agentsVisible: agentsOpen, toolsVisible: toolsOpen
        )
    }

    func testTheWindowInFrontIsShowResultsOwnRule() {
        XCTAssertEqual(front(findings: true, agentsOpen: true), .findings)
        XCTAssertEqual(front(decoys: true), .decoys)
        XCTAssertEqual(front(agents: true, toolsOpen: true), .agents)
        XCTAssertEqual(front(agentsOpen: true), .agents)
        XCTAssertEqual(front(agentsOpen: true, toolsOpen: true), .tools)
        XCTAssertEqual(front(), .tools)
    }

    /// Review of #63: with no window in front, the failure went to the
    /// Findings banner where the success would have gone to Tools.
    func testOnlyFindingsAndDecoysNeedTheFailureAsTheirBanner() {
        XCTAssertTrue(OutcomeWindow.findings.needsFailureBanner)
        XCTAssertTrue(OutcomeWindow.decoys.needsFailureBanner)
        XCTAssertFalse(OutcomeWindow.agents.needsFailureBanner)
        XCTAssertFalse(OutcomeWindow.tools.needsFailureBanner)
    }
}
