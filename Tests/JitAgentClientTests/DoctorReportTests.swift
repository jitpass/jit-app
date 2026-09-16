// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class DoctorReportTests: XCTestCase {
    private let json = #"""
    {"schema_version":1,"tool":{"version":"1.5.2","build":"98910ac9456f","signature":"signed CZC6BH93GJ"},
     "profiles_checked":24,"secrets_checked":71,"ok":false,
     "problems":[{"kind":"missing","profile":"mcp-caido-2","scope":"global","variable":"CAIDO_URL",
                  "path":"mcp-caido-2/CAIDO_URL","detail":"","action":"`jit vault set mcp-caido-2/CAIDO_URL`, or `jit migrate <path>`"}],
     "warnings":[{"kind":"mount_stale","scope":"mount","path":"/Users/me/x/.env",
                  "detail":"the mount at ~/x/.env is still registered, but its profile is gone",
                  "action":"`jit vault orphans --prune` clears it, or `jit unmount ~/x/.env`"}]}
    """#

    func testDecodesSectionsAndVerdict() throws {
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.tool?.signature, "signed CZC6BH93GJ")
        XCTAssertEqual(r.profilesChecked, 24)
        XCTAssertEqual(r.verdict, "1 problem, 1 warning")
        XCTAssertEqual(r.brokenProfiles, ["mcp-caido-2": "missing: CAIDO_URL"])
    }

    func testItemsSummariseAndNameTheOneCommand() throws {
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
        XCTAssertEqual(r.problems[0].summary, "profile \"mcp-caido-2\": CAIDO_URL missing")
        XCTAssertEqual(r.problems[0].command, "jit vault set mcp-caido-2/CAIDO_URL")
        XCTAssertEqual(r.warnings[0].command, "jit vault orphans --prune")
        XCTAssertEqual(r.warnings[0].summary, "the mount at ~/x/.env is still registered, but its profile is gone")
    }

    func testCleanReportReadsAllGood() throws {
        let r = try JSONDecoder().decode(DoctorReport.self, from: Data(#"{"ok":true}"#.utf8))
        XCTAssertEqual(r.verdict, "all good")
    }
}
