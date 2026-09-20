// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The scan window draws one card per tier and one line of fact per row.
/// Both are decided here, where a test can hold them.
final class ScanTiersTests: XCTestCase {
    private func finding(
        _ id: String,
        type: String = "exposed_secret",
        path: String = "/Users/me/app/tokenpatterns_test.go",
        line: Int? = nil,
        fixture: Bool = false,
        evidence: String = "value matches AWS Access Key ID's known token format",
        remedy: String = "manual",
        agent: String? = nil
    ) -> String {
        var fields: [String] = [
            #""record_type":"finding""#,
            #""record_id":"\#(id)""#,
            #""finding_type":"\#(agent == nil ? type : "agent_cached_secret")""#,
            #""severity":"high""#,
            #""file_path":"\#(path)""#,
            #""evidence":"\#(evidence)""#,
            #""remedy":"\#(remedy)""#,
            #""archived":false"#,
            #""test_fixture":\#(fixture)"#
        ]
        if let line {
            fields.append(#""line":\#(line)"#)
        }
        if let agent {
            fields.append(#""agent":"\#(agent)""#)
            fields.append(#""cache_area":"edit history""#)
        }
        return "{" + fields.joined(separator: ",") + "}"
    }

    private let summary = #"""
    {"record_type":"scan_summary","total_findings":0,"risk_level":"low","exposure_score":0,
    "secrets_total":7,"secrets_protected":7,"secrets_migratable":0,"files_scanned":7792}
    """#

    private func report(_ lines: [String]) throws -> ScanReport {
        try ScanReport.parse(Data((lines + [summary.replacingOccurrences(of: "\n", with: "")]).joined(separator: "\n").utf8))
    }

    func testOnlyTiersWithFindingsArePresent() throws {
        let r = try report([
            finding("f1", type: "env_file_present", path: "/Users/me/app/.env", evidence: "10 plaintext variables", remedy: "migrate"),
            finding("f2", type: "shell_history_secret", path: "/Users/me/.zsh_history", line: 8812),
            finding("f3", line: 56, fixture: true)
        ])
        XCTAssertEqual(r.tiersPresent, [.protect, .needsYou, .testFixtures])
        XCTAssertEqual(r.count(in: .protect), 1)
        XCTAssertEqual(r.count(in: .agentCaches), 0, "no agent copies means no card and no pill")
        XCTAssertTrue(r.showsTierFilter)
    }

    func testACleanScanHasNoTiersAndNoFilter() throws {
        let r = try report([])
        XCTAssertEqual(r.tiersPresent, [])
        XCTAssertFalse(r.showsTierFilter, "a filter over nothing is furniture")
    }

    func testOneTierDoesNotEarnAFilter() throws {
        let r = try report([finding("f1", line: 56, fixture: true), finding("f2", line: 67, fixture: true)])
        XCTAssertEqual(r.tiersPresent, [.testFixtures])
        XCTAssertFalse(r.showsTierFilter)
        XCTAssertEqual(r.count(in: .testFixtures), 2, "two findings in one file are still two findings")
    }

    func testAgentCopiesAreCountedButNotGroupedByFile() throws {
        let r = try report([finding("f1", path: "/Users/me/.claude/history.jsonl", agent: "Claude Code")])
        XCTAssertEqual(r.count(in: .agentCaches), 1)
        XCTAssertTrue(r.groups(in: .agentCaches).isEmpty, "the window draws that tier from agentCacheGroups")
    }

    func testVendorNameIsTakenOutOfTheEvidenceSentence() throws {
        let r = try report([
            finding("f1", line: 56),
            finding("f2", line: 67, evidence: "contains a value matching GitHub Personal Access Token's known token format"),
            finding("f3", line: 89, evidence: "value matches Database connection string with embedded credentials's known token format"),
            finding("f4", line: 90, evidence: "10 plaintext variables (10 active, 0 commented out)")
        ])
        XCTAssertEqual(r.findings[0].vendorName, "AWS Access Key ID")
        XCTAssertEqual(r.findings[1].vendorName, "GitHub Personal Access Token")
        XCTAssertEqual(
            r.findings[2].vendorName,
            "Database connection string with embedded credentials",
            "the name keeps its own trailing s; only the possessive comes off"
        )
        XCTAssertNil(r.findings[3].vendorName, "evidence that is not a format match stays whole")
        XCTAssertEqual(r.findings[3].shortEvidence, "10 plaintext variables (10 active, 0 commented out)")
    }

    func testOneFlaggedLineReadsAsItself() throws {
        let r = try report([finding("f1", line: 100, fixture: true, evidence: "value matches Doppler Service Token's known token format")])
        XCTAssertEqual(r.groups(in: .testFixtures).first?.fact, "line 100 · Doppler Service Token")
    }

    func testAFileLevelFindingNamesItsType() throws {
        let r = try report([
            finding("f1", type: "env_file_present", path: "/Users/me/app/.env", evidence: "10 plaintext variables", remedy: "migrate")
        ])
        XCTAssertEqual(r.groups(in: .protect).first?.fact, "Env file present · 10 plaintext variables")
    }

    func testSeveralLinesNameThreeAndCountTheRest() throws {
        let r = try report([
            finding("f1", line: 56, fixture: true),
            finding("f2", line: 67, fixture: true, evidence: "value matches SendGrid API Key's known token format"),
            finding("f3", line: 87, fixture: true, evidence: "value matches JSON Web Token (JWT)'s known token format"),
            finding(
                "f4",
                line: 89,
                fixture: true,
                evidence: "value matches Database connection string with embedded credentials's known token format"
            ),
            finding("f5", line: 478, fixture: true, evidence: "value matches Doppler Service Token's known token format")
        ])
        let group = try XCTUnwrap(r.groups(in: .testFixtures).first)
        XCTAssertEqual(group.fact, "5 flagged lines · AWS Access Key ID, SendGrid API Key, JSON Web Token (JWT) and 2 more")
        XCTAssertEqual(group.firstLine, 56, "Open jumps to the first line the scanner numbered")
    }
}
