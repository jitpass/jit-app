// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class RedactReportTests: XCTestCase {
    private func report(removed: [MigrateReport.CacheFile], left: [MigrateReport.CacheFile] = [], errors: [String] = []) -> RedactReport {
        RedactReport(files: [], applied: !removed.isEmpty, caches: .init(removed: removed, left: left), errors: errors, report: "")
    }

    private func file(_ agent: String, _ area: String, copies: Int? = nil, kind: String? = nil) -> MigrateReport.CacheFile {
        .init(agent: agent, area: area, path: "/h/x", copies: copies, kind: kind, reason: kind.map { "left: \($0)" })
    }

    func testOutcomeNamesTokensFilesPlacesAndWhatWasLeft() {
        let outcome = ScanWording.redactOutcome(report(
            removed: [
                file("Claude Code", "transcripts", copies: 5),
                file("Claude Code", "transcripts", copies: 1),
                file("Claude Code", "edit history", copies: 1)
            ],
            left: [file("Claude Code", "transcripts", kind: "live")]
        ))
        XCTAssertEqual(
            outcome.title,
            "Redacted 7 tokens in 3 files · Claude Code's transcripts and Claude Code's edit history · 1 left, Claude Code is writing it"
        )
        XCTAssertFalse(outcome.failed)
    }

    func testOutcomeWhenNothingAndOnError() {
        XCTAssertEqual(ScanWording.redactOutcome(report(removed: [])).title, "Nothing to redact")
        let binary = ScanWording.redactOutcome(report(removed: [], left: [file("Cursor", "chat database", kind: "binary")]))
        XCTAssertEqual(binary.title, "1 left, a binary store jit won't rewrite")
        let failed = ScanWording.redactOutcome(report(removed: [file("Claude Code", "transcripts", copies: 2)], errors: ["disk full"]))
        XCTAssertTrue(failed.failed)
        XCTAssertTrue(failed.title.hasPrefix("Redact did not finish · disk full · Redacted 2 tokens in 1 file"))
    }

    func testParseAndNotice() throws {
        let doc = """
        {"files":[],"applied":true,"caches":{"removed":[{"agent":"Claude Code","area":"transcripts","path":"/h/a","copies":7}],
         "left":[{"agent":"Claude Code","area":"transcripts","path":"/h/b","kind":"live","reason":"writing"}]},"errors":[],"report":"x"}
        """
        let report = try RedactReport.parse(doc)
        XCTAssertEqual(report.tokensRedacted, 7)
        let ran = Date(timeIntervalSince1970: 1_800_759_600) // Sunday 03:00 UTC
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let notice = ScanNotices.redacted(
            report,
            at: ran,
            now: ran.addingTimeInterval(3600),
            calendar: utc,
            locale: Locale(identifier: "en_US_POSIX")
        )
        XCTAssertEqual(notice?.title, "Today's scan redacted 7 tokens in Claude Code's caches")
        XCTAssertEqual(notice?.body, "1 file. 1 left: Claude Code was writing it. Click to open Findings.")
        XCTAssertNil(ScanNotices.redacted(RedactReport(files: [], applied: false, caches: .init(), errors: [], report: ""), at: ran))
    }
}
