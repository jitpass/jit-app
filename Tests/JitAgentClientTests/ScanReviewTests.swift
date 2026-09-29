// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Findings' review marks: which findings may carry one, the arguments
/// that mark exactly them, and the report once they are marked.
final class ScanReviewTests: XCTestCase {
    private func line(
        _ id: String, path: String, line: Int?, remedy: String = "manual", fixture: Bool = true, extra: String = ""
    ) -> String {
        let at = line.map { #","line":\#($0)"# } ?? ""
        return #"{"record_type":"finding","record_id":"\#(id)","finding_type":"exposed_secret","severity":"high","file_path":"\#(path)","#
            + #""evidence":"value matches AWS Access Key ID's known token format","remedy":"\#(remedy)","archived":false,"#
            + #""test_fixture":\#(fixture)\#(at)\#(extra)}"#
    }

    private func report(_ lines: [String], schema: String = "0.25.0") throws -> ScanReport {
        let summary = #"{"record_type":"scan_summary","schema_version":"\#(schema)","total_findings":\#(lines.count),"#
            + #""risk_level":"high","exposure_score":40,"secrets_total":1,"secrets_protected":0,"secrets_migratable":0,"#
            + #""files_scanned":9,"reviewed":2}"#
        return try ScanReport.parse(Data((lines + [summary]).joined(separator: "\n").utf8))
    }

    func testTargetsNameEachLineOnceAndAWholeFileForALinelessFinding() throws {
        let r = try report([
            line("a", path: "/u/t/p_test.go", line: 10),
            line("a", path: "/u/t/p_test.go", line: 10),
            line("b", path: "/u/t/p_test.go", line: 12),
            line("c", path: "/u/docs/README.md", line: nil)
        ])
        XCTAssertEqual(ScanReview.targets(r.findings), ["/u/t/p_test.go:10", "/u/t/p_test.go:12", "/u/docs/README.md"])
    }

    /// Marking one of two lines that share a record id leaves the other,
    /// and the summary counts what left.
    func testMarkedFindingsLeaveTheReportAndAreCounted() throws {
        let r = try report([line("a", path: "/u/x.go", line: 1), line("a", path: "/u/x.go", line: 2), line("b", path: "/u/y.go", line: 3)])
        let after = r.removingReviewed([r.findings[0]])
        XCTAssertEqual(after.findings.map(\.line), [2, 3])
        XCTAssertEqual(after.summary.reviewed, 3)
    }

    /// jit skipped one of the three: only the two it names leave.
    func testOnlyTheFindingsJitMarkedLeave() throws {
        let r = try report([
            line("a", path: "/u/x.go", line: 1),
            line("b", path: "/u/x.go", line: 2),
            line("c", path: "/u/y.go", line: nil)
        ])
        let answer = #"{"reviewed":[{"id":"m1","path":"/u/x.go","line":2,"finding_type":"exposed_secret","label":"k","reviewed_at":1},"#
            + #"{"id":"m2","path":"/u/y.go","finding_type":"exposed_secret","label":"k","reviewed_at":1}],"skipped":1}"#
        let result = try JSONDecoder().decode(ScanReviewResult.self, from: Data(answer.utf8))
        XCTAssertEqual(ScanReview.marked(r.findings, by: result).map(\.id), ["b", "c"])
    }

    /// A row that moved since the scan comes back as missed, and stays: jit
    /// marked the rest instead of failing them all.
    func testARowThatMovedIsMissedAndStays() throws {
        let r = try report([line("a", path: "/u/x.go", line: 1), line("b", path: "/u/x.go", line: 9)])
        let answer = #"{"reviewed":[{"id":"m1","path":"/u/x.go","line":1,"finding_type":"exposed_secret","label":"k","reviewed_at":1}],"#
            + #""missed":["~/x.go:9"]}"#
        let result = try JSONDecoder().decode(ScanReviewResult.self, from: Data(answer.utf8))
        XCTAssertEqual(result.missed, ["~/x.go:9"])
        XCTAssertEqual(ScanReview.marked(r.findings, by: result).map(\.id), ["a"])
    }

    func testOnlyFixturesAndFindingsOnlyYouCanFixAreReviewable() throws {
        let r = try report([
            line("fixture", path: "/u/x_test.go", line: 1),
            line("manual", path: "/u/notes.txt", line: 1, fixture: false),
            line("protect", path: "/u/.env", line: nil, remedy: "migrate", fixture: false),
            line("cache", path: "/u/.claude/t.jsonl", line: 4, fixture: false, extra: #","agent":"Claude Code","cache_area":"transcripts""#)
        ])
        XCTAssertEqual(r.findings.filter(\.reviewable).map(\.id), ["fixture", "manual"])
    }

    func testAnOlderEngineOffersNoMarks() throws {
        XCTAssertTrue(try ScanReview.supported(report([]).summary))
        XCTAssertTrue(try ScanReview.supported(report([], schema: "0.31.2").summary))
        XCTAssertFalse(try ScanReview.supported(report([], schema: "0.24.0").summary))
        XCTAssertFalse(try ScanReview.supported(report([], schema: "0.9.0").summary))
    }

    func testTheListDecodesEachMarksOwnIDWithoutAValue() throws {
        let json = #"{"reviewed":["#
            + #"{"id":"9f1c","path":"/u/x_test.go","line":40,"finding_type":"exposed_secret","#
            + #""label":"value matches GitHub Personal Access Token's known token format","reviewed_at":1790576144},"#
            + #"{"id":"a07e","path":"/u/x_test.go","line":40,"finding_type":"exposed_secret","#
            + #""label":"value matches AWS Access Key ID's known token format","reviewed_at":1790576144}],"skipped":1}"#
        let result = try JSONDecoder().decode(ScanReviewResult.self, from: Data(json.utf8))
        let entries = try XCTUnwrap(result.reviewed)
        XCTAssertEqual(entries.map(\.id), ["9f1c", "a07e"], "two marks on one line are two rows")
        XCTAssertEqual(result.skipped, 1)
    }

    /// Only the picked findings are marked: `--only` names each record
    /// once, and a lineless finding sends its bare file, safe beside it.
    func testArgumentsMarkOnlyThePickedFindings() throws {
        let r = try report([
            line("a", path: "/u/t/p_test.go", line: 10),
            line("a", path: "/u/t/p_test.go", line: 11),
            line("c", path: "/u/docs/README.md", line: nil)
        ])
        XCTAssertEqual(ScanReview.arguments(for: r.findings), [
            "review", "--only", "a", "--only", "c",
            "/u/t/p_test.go:10", "/u/t/p_test.go:11", "/u/docs/README.md",
            "--format", "json"
        ])
        XCTAssertEqual(ScanReview.unreviewArguments(["9f1c", "a07e"]), ["unreview", "--id", "9f1c", "--id", "a07e", "--format", "json"])
        XCTAssertEqual(ScanReview.listArguments, ["review", "--list", "--format", "json"])
    }

    func testAnEntryWithoutAnIDStillHasADistinctRow() {
        let first = ScanReviewEntry(path: "/u/x", line: nil, findingType: "exposed_secret", label: "A", reviewedAt: 1)
        let second = ScanReviewEntry(path: "/u/x", line: nil, findingType: "exposed_secret", label: "B", reviewedAt: 1)
        XCTAssertNotEqual(first.id, second.id)
    }
}
