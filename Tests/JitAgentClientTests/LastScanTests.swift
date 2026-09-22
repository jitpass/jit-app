// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The last scan survives a relaunch, and carries no value with it.
final class LastScanTests: XCTestCase {
    func testTheRecordRoundTripsAndKeepsNoValue() throws {
        let finding = [
            #"{"record_type":"finding","record_id":"f1","finding_type":"vault_copy","severity":"high","#,
            #""file_path":"/Users/me/.claude/h.jsonl","line":7,"evidence":"an exact copy of the vaulted secret wiz/X","#,
            #""remedy":"manual","archived":false,"test_fixture":false,"key_name":"wiz/X","agent":"Claude Code","#,
            #""cache_area":"local store","value_preview":"sk-live-********"}"#
        ].joined()
        let summary = [
            #"{"record_type":"scan_summary","total_findings":1,"risk_level":"high","exposure_score":40,"#,
            #""secrets_total":2,"secrets_protected":1,"secrets_migratable":0,"files_scanned":10,"deep":true,"vault_secrets_checked":9}"#
        ].joined()
        let report = try ScanReport.parse(Data((finding + "\n" + summary).utf8))
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let record = LastScan(report: report, at: at, kind: .deep, deepAt: at)
        let data = try record.encoded()
        XCTAssertEqual(try LastScan.decode(data), record)
        let text = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        XCTAssertFalse(text.contains("value_preview"), "the app never decodes a preview, so it never writes one")
        XCTAssertFalse(text.contains("sk-live"))
        XCTAssertTrue(text.contains("wiz/X"))
    }
}
