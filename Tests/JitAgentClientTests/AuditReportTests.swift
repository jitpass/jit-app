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
                        {"unix_time":1789585100,"kind":"lock","cause":"5m0s idle timeout"}]}
        """#
        let r = try JSONDecoder().decode(AuditReport.self, from: Data(json.utf8))
        let rows = r.rows
        XCTAssertEqual(rows.map(\.kind), ["unlock", "cmd", "lock"])
        XCTAssertEqual(rows[0].title, "unlocked by JitPass")
        XCTAssertEqual(rows[1].title, "jit status")
        XCTAssertEqual(rows[1].detail, "launched by JitPass")
        XCTAssertEqual(rows[2].detail, "5m0s idle timeout")
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
        XCTAssertEqual(AuditFilter().arguments, ["audit", "--format", "json", "--limit", "200"])
        let f = AuditFilter(kinds: ["unlock", "use"], parent: "claude", since: "24h", limit: 50)
        XCTAssertEqual(
            f.arguments,
            ["audit", "--format", "json", "--limit", "50", "--kind", "unlock,use", "--parent", "claude", "--since", "24h"]
        )
    }
}
