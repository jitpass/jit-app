// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class AuditReportTests: XCTestCase {
    func testMergesBothHalvesNewestFirst() throws {
        let json = #"""
        {"commands":[{"unix_nano":1789585235325819000,"command":"jit status","args":["status"],"user":"me","uid":502,
                      "pid":1,"ppid":2,"parent":"JitPass","launched_by":"JitPass","duration_ms":22,"success":true}],
         "auth_events":[{"unix_time":1789585300,"kind":"unlock","op":"unlock",
                         "by":"/Applications/JitPass.app/Contents/MacOS/JitPass","by_pid":9},
                        {"unix_time":1789585100,"kind":"lock","cause":"5 min idle timeout"}]}
        """#
        let r = try JSONDecoder().decode(AuditReport.self, from: Data(json.utf8))
        let rows = r.rows
        XCTAssertEqual(rows.map(\.kind), ["unlock", "cmd", "lock"])
        XCTAssertEqual(rows[0].title, "unlocked by JitPass")
        XCTAssertEqual(rows[1].title, "jit status")
        XCTAssertEqual(rows[1].detail, "launched by JitPass")
        XCTAssertEqual(rows[2].detail, "5 min idle timeout")
    }

    func testTitlesNameWhatHappenedWithoutACaller() {
        XCTAssertEqual(AuditReport.title(for: SessionEvent(unixTime: 0, kind: "use", op: "serve_mounts")), "served mounts (a secret)")
        XCTAssertEqual(
            AuditReport.title(for: SessionEvent(unixTime: 0, kind: "use", op: "unwrap", by: "/usr/bin/aws", labels: ["aws/default"])),
            "aws used aws/default"
        )
        XCTAssertEqual(AuditReport.title(for: SessionEvent(unixTime: 0, kind: "lock", cause: "screen locked")), "locked")
        XCTAssertEqual(AuditReport.title(for: SessionEvent(unixTime: 0, kind: "start")), "service started")
    }

    func testFilterRendersOnlyWhatIsSet() {
        // No range means everything, so the cap is off; an hour or a day
        // keeps the cap, a week drops it (200 entries fit in one afternoon).
        XCTAssertEqual(AuditFilter().arguments, ["audit", "--format", "json", "--limit", "0"])
        XCTAssertEqual(AuditFilter(since: "1h").effectiveLimit, 200)
        XCTAssertEqual(AuditFilter(since: "7d").effectiveLimit, 0)
        let f = AuditFilter(kinds: ["unlock", "use"], parent: "claude", since: "24h", limit: 50)
        XCTAssertEqual(
            f.arguments,
            ["audit", "--format", "json", "--limit", "50", "--kind", "unlock,use", "--parent", "claude", "--since", "24h"]
        )
    }
}

extension AuditReportTests {
    /// A decoy serve is named as such: who read what, and that they got
    /// fake values. The row's status drives the amber glyph.
    func testDecoyServeIsNamedAndMarked() throws {
        let json = """
        {"unix_time": 1789108207, "kind": "serve", "op": "decoy", "by": "/u/.local/bin/python3.13", "by_pid": 55227,
         "launched_by": "uv", "cause": "no jit run grant or consent approval covered the reader",
         "labels": ["~/mcp/urlscan/.env"], "count": 2}
        """
        let event = try JSONDecoder().decode(SessionEvent.self, from: Data(json.utf8))
        XCTAssertTrue(event.isDecoyServe)
        XCTAssertEqual(AuditReport.title(for: event), "decoy served to python3.13")
        XCTAssertEqual(AuditReport.detail(for: event), "~/mcp/urlscan/.env · 2 reads · launched by uv")
        let row = AuditReport(commands: [], authEvents: [event]).rows[0]
        XCTAssertEqual(row.status, "decoy")
    }
}
