// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class ScanReportTests: XCTestCase {
    private let finding = #"""
    {"record_type":"finding","record_id":"finding:1","finding_type":"env_file_present","severity":"low",
     "file_path":"/Users/me/app/.env","value_preview":"sk_live_abc","evidence":"10 plaintext variables",
     "remedy":"migrate","fix_command":"jit migrate ~/app/.env","archived":false}
    """#
    private let manual = #"""
    {"record_type":"finding","record_id":"finding:2","finding_type":"shell_history_secret","severity":"high",
     "file_path":"/Users/me/.zsh_history","evidence":"value matches a token format","remedy":"manual","archived":false}
    """#
    private let fixture = #"""
    {"record_type":"finding","record_id":"finding:3","finding_type":"exposed_secret","severity":"high",
     "file_path":"/Users/me/app/internal/tokenpatterns_test.go","evidence":"value matches AWS Access Key ID's known token format",
     "remedy":"manual","archived":false,"test_fixture":true,"source_example":false}
    """#
    private let summary = #"""
    {"record_type":"scan_summary","total_findings":2,"risk_level":"critical","exposure_score":100,
     "secrets_total":47,"secrets_protected":39,"secrets_migratable":2,"files_scanned":45094,"scan_time":"2026-09-16T18:39:12.649Z"}
    """#

    private func stream(_ lines: [String]) -> Data {
        Data(lines.map { $0.replacingOccurrences(of: "\n", with: "") }.joined(separator: "\n").utf8)
    }

    func testParsesFindingsAndSummary() throws {
        let r = try ScanReport.parse(stream([finding, #"{"record_type":"future_thing"}"#, manual, summary]))
        XCTAssertEqual(r.findings.count, 2)
        XCTAssertEqual(r.migratable.map(\.id), ["finding:1"])
        XCTAssertEqual(r.manual.map(\.id), ["finding:2"])
        XCTAssertEqual(r.summary.exposureScore, 100)
        XCTAssertEqual(r.summary.riskLevel, "critical")
        XCTAssertEqual(r.summary.filesScanned, 45094)
    }

    func testScaffoldingIsSetApartFromTheOtherGroups() throws {
        let r = try ScanReport.parse(stream([finding, manual, fixture, summary]))
        XCTAssertEqual(r.scaffolding.map(\.id), ["finding:3"])
        XCTAssertEqual(r.manual.map(\.id), ["finding:2"], "a fixture is not something the user must fix")
        XCTAssertEqual(r.findings.count, 3, "but it is still counted, as the scanner counts it")
    }

    func testValuePreviewIsNeverDecoded() throws {
        let r = try ScanReport.parse(stream([finding, summary]))
        let mirror = Mirror(reflecting: r.findings[0])
        XCTAssertFalse(mirror.children.contains { "\($0.value)".contains("sk_live") })
        XCTAssertFalse(mirror.children.contains { $0.label == "valuePreview" })
    }

    func testMissingSummaryIsAnError() {
        XCTAssertThrowsError(try ScanReport.parse(stream([finding]))) { error in
            XCTAssertEqual(error as? ScanReportError, .noSummary)
        }
    }
}
