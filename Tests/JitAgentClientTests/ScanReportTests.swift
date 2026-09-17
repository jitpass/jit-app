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

extension ScanReportTests {
    /// One finding record from the fields a test cares about.
    private static func record(
        _ id: String, path: String, line: Int? = nil, severity: String = "low",
        remedy: String = "manual", fix: String? = nil, fixture: Bool = false
    ) -> String {
        var fields = [
            "\"record_type\":\"finding\"", "\"record_id\":\"\(id)\"", "\"finding_type\":\"exposed_secret\"",
            "\"severity\":\"\(severity)\"", "\"file_path\":\"\(path)\"", "\"evidence\":\"e\"", "\"remedy\":\"\(remedy)\"",
            "\"line\":" + (line.map(String.init) ?? "null")
        ]
        if let fix {
            fields.append("\"fix_command\":\"\(fix)\"")
        }
        if fixture {
            fields.append("\"test_fixture\":true")
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private static let closing = #"{"record_type":"scan_summary","total_findings":0,"risk_level":"low","exposure_score":1,"#
        + #""secrets_total":0,"secrets_protected":0,"secrets_migratable":0,"files_scanned":1}"#

    private func parse(_ records: [String]) throws -> ScanReport {
        try ScanReport.parse(Data((records + [Self.closing]).joined(separator: "\n").utf8))
    }

    func testLineIsDecodedAndManualFindingsGroupByFile() throws {
        let r = try parse([
            Self.record("4", path: "/Users/me/r.html", line: 12, severity: "high"),
            Self.record("5", path: "/Users/me/r.html", line: 40, severity: "critical"),
            Self.record("6", path: "/Users/me/a.tfvars", severity: "medium")
        ])
        XCTAssertEqual(r.findings.map(\.line), [12, 40, nil])
        let groups = r.manualByFile
        XCTAssertEqual(groups.map(\.filePath), ["/Users/me/r.html", "/Users/me/a.tfvars"], "first-seen order, one row per file")
        XCTAssertEqual(groups[0].findings.map(\.line), [12, 40])
        XCTAssertEqual(groups[0].severity, "critical", "the row carries the worst severity in the file")
        XCTAssertEqual(groups[1].severity, "medium")
    }

    func testProtectAllFoldsMigratesIntoOneCommandAndKeepsWrapsOnce() throws {
        let r = try parse([
            Self.record("a", path: "/Users/me/a/.env", remedy: "migrate", fix: "jit migrate ~/a/.env"),
            Self.record("b", path: "/Users/me/.clisso", remedy: "migrate", fix: "jit wrap clisso"),
            Self.record("c", path: "/Users/me/b dir/.env", remedy: "migrate", fix: "jit migrate '~/b dir/.env'"),
            Self.record("d", path: "/Users/me/.clisso2", remedy: "migrate", fix: "jit wrap clisso"),
            Self.record("e", path: "/Users/me/a/.env", remedy: "migrate", fix: "jit migrate ~/a/.env"),
            Self.record("f", path: "/Users/me/t_test.go", remedy: "migrate", fix: "jit migrate ~/t_test.go", fixture: true)
        ])
        XCTAssertEqual(r.protectAllCommands, ["jit migrate ~/a/.env '~/b dir/.env'", "jit wrap clisso"])
        XCTAssertEqual(try parse([]).protectAllCommands, [])
    }

    func testProtectPlanUsesTheFindingsOwnPathsAndEachWrapOnce() throws {
        let r = try parse([
            Self.record("a", path: "/Users/me/a/.env", remedy: "migrate", fix: "jit migrate ~/a/.env"),
            Self.record("b", path: "/Users/me/.clisso", remedy: "migrate", fix: "jit wrap clisso"),
            Self.record("c", path: "/Users/me/b dir/.env", remedy: "migrate", fix: "jit migrate '~/b dir/.env'"),
            Self.record("d", path: "/Users/me/.clisso2", remedy: "migrate", fix: "jit wrap clisso"),
            Self.record("e", path: "/Users/me/a/.env", remedy: "migrate", fix: "jit migrate ~/a/.env"),
            Self.record("f", path: "/Users/me/t_test.go", remedy: "migrate", fix: "jit migrate ~/t_test.go", fixture: true)
        ])
        XCTAssertEqual(r.protectPlan, ProtectPlan(migrate: ["/Users/me/a/.env", "/Users/me/b dir/.env"], wrap: ["clisso"]))
        XCTAssertEqual(r.protectPlan.count, 3)
        XCTAssertEqual(r.findings[1].wrapTool, "clisso")
        XCTAssertNil(r.findings[0].wrapTool)
        XCTAssertTrue(try parse([]).protectPlan.isEmpty)
    }

    /// The same ledger arithmetic as the CLI: 39 of 47 is 82%, one command
    /// lifts it to 87%, and the rest is the user's; a Mac jit knows nothing
    /// about is 100%.
    func testCoverageMatchesTheCLI() throws {
        let r = try ScanReport.parse(stream([summary]))
        XCTAssertEqual(r.summary.percent, 82)
        XCTAssertEqual(r.summary.percentAfterMigrate, 87)
        XCTAssertEqual(r.summary.secretsManual, 6)
        XCTAssertEqual(r.summary.toFullLine, "to 100%: one command +5% · 6 secrets only you can fix +13%")
        let clean = ScanSummary(totalFindings: 0, riskLevel: "low", exposureScore: 0, secretsTotal: 0,
                                secretsProtected: 0, secretsMigratable: 0, filesScanned: 10, scanTime: nil)
        XCTAssertEqual(clean.percent, 100)
        XCTAssertNil(clean.toFullLine)
    }
}
