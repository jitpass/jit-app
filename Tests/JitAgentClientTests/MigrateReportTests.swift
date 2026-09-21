// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The banner after a Protect reads the migrate report's fields, never
/// its prose.
final class MigrateReportTests: XCTestCase {
    private let home = "/Users/me"
    private let document = """
    Scanning ~/notion/.env for secrets…
    {
      "targets": ["/Users/me/notion/.env"],
      "applied": true,
      "vaulted": ["NOTION_TOKEN"],
      "caches": {
        "removed": [
          {"agent": "Claude Code", "area": "transcripts", "path": "/Users/me/.claude/a.jsonl", "copies": 7},
          {"agent": "Claude Code", "area": "edit history", "path": "/Users/me/.claude/h", "copies": 1}
        ],
        "left": [
          {"agent": "Claude Code", "area": "transcripts", "path": "/Users/me/.claude/live.jsonl",
           "kind": "live", "reason": "the agent wrote to it while jit was working; left alone"}
        ]
      },
      "errors": [],
      "report": "jit migrate, plan\\n..."
    }
    """

    func testParsesTheDocumentOutOfWhateverElseReachedThePipe() throws {
        let report = try MigrateReport.parse(document)
        XCTAssertEqual(report.targets, ["/Users/me/notion/.env"])
        XCTAssertTrue(report.applied)
        XCTAssertEqual(report.vaulted, ["NOTION_TOKEN"])
        XCTAssertEqual(report.removedCopies, 8)
        XCTAssertEqual(report.caches.left.first?.kind, "live")
        XCTAssertEqual(report.report, "jit migrate, plan\n...")
        XCTAssertThrowsError(try MigrateReport.parse("no document here")) { error in
            XCTAssertEqual(error as? MigrateReportError, .noDocument)
        }
    }

    func testOutcomeNamesTheFileTheVarTheSweepAndWhatWasLeft() throws {
        let outcome = try ScanWording.protectOutcome(MigrateReport.parse(document), home: home)
        XCTAssertEqual(
            outcome.title,
            "Protected ~/notion/.env · NOTION_TOKEN is in the vault · 8 cached copies removed · 1 file left in Claude Code's transcripts"
        )
        XCTAssertFalse(outcome.failed)
    }

    func testOutcomeForSeveralFilesAndManyVars() {
        var report = MigrateReport(
            targets: ["/Users/me/a/.env", "/Users/me/b/.env"], applied: true,
            vaulted: ["A", "B", "C", "D"], caches: .init(), errors: [], report: ""
        )
        XCTAssertEqual(ScanWording.protectOutcome(report, home: home).title, "Protected 2 files · 4 secrets are in the vault")
        report.vaulted = ["A", "B"]
        XCTAssertEqual(ScanWording.protectOutcome(report, home: home).title, "Protected 2 files · A, B are in the vault")
    }

    func testOutcomeWhenNothingToProtectAndOnError() {
        let nothing = MigrateReport(targets: ["/Users/me/notes.txt"], applied: false, vaulted: [], caches: .init(), errors: [], report: "")
        XCTAssertEqual(ScanWording.protectOutcome(nothing, home: home).title, "Nothing to protect in ~/notes.txt")

        let failed = MigrateReport(
            targets: ["/Users/me/notion/.env"], applied: false, vaulted: ["NOTION_TOKEN"],
            caches: .init(removed: [.init(agent: "Claude Code", area: "transcripts", path: "/x", copies: 3)]),
            errors: ["jit migrate: could not finish clearing AI agent caches: disk full"], report: ""
        )
        let outcome = ScanWording.protectOutcome(failed, home: home)
        XCTAssertTrue(outcome.failed)
        XCTAssertEqual(
            outcome.title,
            "Protect did not finish · jit migrate: could not finish clearing AI agent caches: disk full · "
                + "NOTION_TOKEN is in the vault · 3 cached copies removed",
            "the partial result is real, so it is still named"
        )
    }

    func testCleanMessageNamesTheNextRun() throws {
        let ran = Date(timeIntervalSince1970: 1_800_759_600) // Sunday 03:00 UTC
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "en_US_POSIX")
        let now = ran.addingTimeInterval(60)
        XCTAssertEqual(
            ScanWording.cleanMessage(filesRead: 11884, schedule: .weekly, last: ran, now: now, calendar: utc, locale: locale),
            "11884 files read, including every agent cache. The next scheduled scan is Sunday 03:00."
        )
        XCTAssertEqual(
            ScanWording.cleanMessage(filesRead: 5, schedule: .off, last: ran, now: now, calendar: utc, locale: locale),
            "5 files read, including every agent cache. Nothing runs on its own; scan again whenever you like."
        )
        XCTAssertTrue(
            ScanWording.cleanMessage(filesRead: 5, schedule: .launch, last: ran, now: now, calendar: utc, locale: locale)
                .hasSuffix("The next scan runs when JitPass starts.")
        )
    }
}
