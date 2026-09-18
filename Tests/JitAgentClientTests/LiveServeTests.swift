// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The live `serve_start` notice and the `serve` record that follows it an
/// hour later describe one read. The audit and the Decoys count must show
/// it exactly once, whichever of the two exists.
final class LiveServeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_700_000)

    private func notice(at time: Int64, undelivered: Bool? = nil) -> SessionEvent {
        SessionEvent(
            unixTime: time, kind: SessionEvent.serveStartKind, op: "decoy", by: "/u/bin/python3.13", byPID: 7,
            launchedBy: "uv", labels: ["~/mcp/.env"], count: 1, undelivered: undelivered
        )
    }

    func testDecodesTheStreamedNotice() throws {
        let json = """
        {"unix_time": 1789699990, "kind": "serve_start", "op": "decoy", "by": "/u/bin/python3.13", "by_pid": 7,
         "labels": ["~/mcp/.env"], "count": 1, "undelivered": true}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.kind, SessionEvent.serveStartKind)
        XCTAssertEqual(event.undelivered, true)
        XCTAssertFalse(event.readDecoy, "a reader that received nothing got no decoy")
        XCTAssertTrue(notice(at: 1).readDecoy)
    }

    func testANoticeWithoutItsRecordBecomesAServeRow() {
        let report = AuditReport(commands: [], authEvents: [])
            .addingLive([notice(at: 1_789_699_990)], filter: AuditFilter(kinds: ["serve"], since: "7d"), now: now)
        XCTAssertEqual(report.authEvents.map(\.kind), ["serve"])
        XCTAssertEqual(report.rows.first?.title, "decoy served to python3.13")
        XCTAssertEqual(report.rows.first?.status, "decoy")
    }

    func testTheRecordReplacesItsNotice() {
        var record = notice(at: 1_789_699_990)
        record.kind = "serve"
        record.count = 37
        record.launchedBy = "a launcher found later"
        let report = AuditReport(commands: [], authEvents: [record])
            .addingLive([notice(at: 1_789_699_990)], filter: AuditFilter(), now: now)
        XCTAssertEqual(report.authEvents.count, 1)
        XCTAssertEqual(report.authEvents.first?.count, 37)
    }

    func testTheFilterStillApplies() {
        let live = [notice(at: 1_789_699_990), notice(at: 1_789_690_000)]
        let unlocks = AuditReport(commands: [], authEvents: [])
            .addingLive(live, filter: AuditFilter(kinds: ["unlock"]), now: now)
        XCTAssertTrue(unlocks.authEvents.isEmpty)
        let byParent = AuditReport(commands: [], authEvents: [])
            .addingLive(live, filter: AuditFilter(parent: "claude"), now: now)
        XCTAssertTrue(byParent.authEvents.isEmpty)
        let lastHour = AuditReport(commands: [], authEvents: [])
            .addingLive(live, filter: AuditFilter(since: "1h"), now: now)
        XCTAssertEqual(lastHour.authEvents.map(\.unixTime), [1_789_699_990])
    }

    func testAReadOfNothingIsNamedAsSuch() {
        var event = notice(at: 1, undelivered: true)
        event.kind = "serve"
        XCTAssertEqual(AuditReport.title(for: event), "opened by python3.13, nothing read")
        XCTAssertTrue(event.isDecoyServe, "the verdict still files it under decoys, as jit audit does")
        XCTAssertFalse(event.readDecoy)
    }
}
