// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Rows a Protect removed stay removed until a scan that started after it
/// lands, and only files the migrate vouches for leave at all.
final class ProtectedSinceScanTests: XCTestCase {
    private let alpha = "/Users/me/alpha/.env"
    private let beta = "/Users/me/beta/.env"

    private func report(_ paths: [String]) throws -> ScanReport {
        let rows = paths.enumerated().map { index, path in
            #"{"record_type":"finding","record_id":"r\#(index)","finding_type":"env_file_present","severity":"high","#
                + #""file_path":"\#(path)","evidence":"contains a credential","remedy":"migrate","archived":false,"test_fixture":false}"#
        }
        let summary = #"{"record_type":"scan_summary","total_findings":\#(paths.count),"risk_level":"high","exposure_score":40,"#
            + #""secrets_total":2,"secrets_protected":0,"secrets_migratable":2,"files_scanned":9}"#
        return try ScanReport.parse(Data((rows + [summary]).joined(separator: "\n").utf8))
    }

    /// Protect A, scan S1 starts, Protect B finishes, S1 lands, S2 lands.
    func testAScanIsTheWordOnlyOnWhatWasProtectedBeforeItStarted() throws {
        var pending = ProtectedSinceScan()
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        pending.add(files: [alpha], tools: [], at: t0)
        let s1 = t0.addingTimeInterval(1)
        pending.add(files: [beta], tools: [], at: t0.addingTimeInterval(2))

        // S1 read the disk after A moved (A's row is its own finding, kept
        // as scanned) but maybe before B did (B's row is filtered).
        let landed1 = try pending.land(report([alpha, beta]), startedAt: s1)
        XCTAssertEqual(landed1.findings.map(\.filePath), [alpha])
        XCTAssertEqual(pending.entries.map(\.files), [[beta]], "B waits for a scan that started after it")

        let landed2 = try pending.land(report([beta]), startedAt: t0.addingTimeInterval(3))
        XCTAssertEqual(landed2.findings.map(\.filePath), [beta], "S2 started after B: its word stands")
        XCTAssertTrue(pending.entries.isEmpty)
    }

    private func migrate(_ targets: [String], errors: [String] = []) -> MigrateReport {
        MigrateReport(targets: targets, applied: true, vaulted: ["TOKEN"], caches: .init(), errors: errors, report: "")
    }

    /// A report says its errors for the whole run, so one with a real error
    /// vouches for none of its files; a cache-sweep error touched no file.
    func testOnlyFilesTheMigrateVouchesForLeave() {
        XCTAssertEqual(ProtectRun(reports: [migrate([alpha, beta])]).protectedFiles, [alpha, beta])
        XCTAssertEqual(ProtectRun(reports: [migrate([alpha, beta], errors: ["\(beta): permission denied"])]).protectedFiles, [])
        XCTAssertEqual(
            ProtectRun(reports: [migrate([alpha], errors: ["clearing AI agent caches: a file is busy"])]).protectedFiles,
            [alpha]
        )
        var notApplied = migrate([alpha])
        notApplied.applied = false
        XCTAssertEqual(ProtectRun(reports: [notApplied]).protectedFiles, [])
    }
}
