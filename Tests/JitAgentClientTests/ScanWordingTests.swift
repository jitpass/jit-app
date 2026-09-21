// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The Findings header owns the schedule: when the run happened, when the
/// next is due, what is new. Every sentence is decided here.
final class ScanWordingTests: XCTestCase {
    // Sunday 2027-01-24 03:00 UTC, so "Sunday 03:00" is a real answer.
    private let ran = Date(timeIntervalSince1970: 1_800_759_600)
    private var calendar: Calendar {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        utc.locale = Locale(identifier: "en_US_POSIX")
        return utc
    }

    private let locale = Locale(identifier: "en_US_POSIX")

    private func when(_ date: Date, now: Date) -> String {
        ScanWording.when(date, now: now, calendar: calendar, locale: locale)
    }

    func testWhenSpeaksInAPersonsUnitsInBothDirections() {
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(30)), "just now")
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(-30)), "in a moment")
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(5 * 60)), "5 min ago")
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(-5 * 60)), "in 5 min")
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(3600)), "1 hour ago")
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(-3 * 3600)), "in 3 hours")
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(2 * 86400)), "Sunday 03:00")
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(-6 * 86400)), "Sunday 03:00")
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(20 * 86400)), "Jan 24")
        XCTAssertEqual(when(ran, now: ran.addingTimeInterval(400 * 86400)), "Jan 24, 2027")
    }

    func testNextRunFollowsTheSchedule() {
        XCTAssertEqual(ScanSchedule.daily.nextRun(after: ran), ran.addingTimeInterval(86400))
        XCTAssertNil(ScanSchedule.off.nextRun(after: ran))
        XCTAssertNil(ScanSchedule.launch.nextRun(after: ran))

        let now = ran.addingTimeInterval(2 * 3600)
        func next(_ s: ScanSchedule, now: Date) -> String {
            ScanWording.nextRunFact(schedule: s, last: ran, now: now, calendar: calendar, locale: locale)
        }
        XCTAssertEqual(next(.weekly, now: now), "next Sunday 03:00")
        XCTAssertEqual(next(.daily, now: now), "next in 22 hours")
        XCTAssertEqual(next(.hourly, now: now), "next at the first chance", "the app slept through it")
        XCTAssertEqual(next(.launch, now: now), "next when JitPass starts")
        XCTAssertEqual(next(.off, now: now), "no schedule")
    }

    func testWholeMacSublineNamesTheRunTheNextAndWhatIsNew() {
        let now = ran.addingTimeInterval(9 * 3600)
        let previous = ran.addingTimeInterval(-7 * 86400 + 60)
        let line = ScanWording.wholeMacSubline(
            ScanRun(kind: .scheduled, at: ran, schedule: .weekly, newCount: 2, previousAt: previous, excludes: 1, fullDiskAccess: true),
            now: now, calendar: calendar, locale: locale
        )
        XCTAssertEqual(
            line,
            "Scheduled scan · ran 9 hours ago · next Sunday 03:00 · 2 new since Jan 17 · excluding 1 folder. "
                + "jit reads your home folder, shell configs, credential files and agent caches."
        )
    }

    func testWholeMacSublineForAClickAndAProtect() {
        let now = ran.addingTimeInterval(20)
        let click = ScanWording.wholeMacSubline(
            ScanRun(
                kind: .byHand, at: ran, schedule: .daily, newCount: 0, previousAt: ran.addingTimeInterval(-86400),
                excludes: 0, fullDiskAccess: false
            ),
            now: now, calendar: calendar, locale: locale
        )
        XCTAssertEqual(
            click,
            "Scanned by hand · just now · next Monday 03:00 · nothing new since Saturday 03:00. "
                + "Without Full Disk Access, macOS asks once per protected folder."
        )
        let protect = ScanWording.wholeMacSubline(
            ScanRun(kind: .afterProtect, at: ran, schedule: .off, newCount: nil, previousAt: nil, excludes: 0, fullDiskAccess: true),
            now: now, calendar: calendar, locale: locale
        )
        XCTAssertTrue(protect.hasPrefix("Scanned after Protect · just now · no schedule. "), protect)
        XCTAssertFalse(protect.contains("new"), "no previous run, so nothing is said about what is new")
    }

    func testNewCountWithoutAPreviousTimeStillCounts() {
        let line = ScanWording.wholeMacSubline(
            ScanRun(kind: .scheduled, at: ran, schedule: .daily, newCount: 3, previousAt: nil, excludes: 0, fullDiskAccess: true),
            now: ran, calendar: calendar, locale: locale
        )
        XCTAssertTrue(line.contains(" · 3 new. "), line)
    }

    func testFolderSublineHasNoSchedule() {
        let line = ScanWording.folderSubline(
            folder: "~/proj", at: ran, excludes: 2, fullDiskAccess: true,
            now: ran.addingTimeInterval(120), calendar: calendar, locale: locale
        )
        XCTAssertEqual(
            line,
            "~/proj · 2 min ago · excluding 2 folders. jit reads your home folder, shell configs, credential files and agent caches."
        )
    }

    func testEmptyMessageNamesTheSchedule() {
        XCTAssertTrue(ScanWording.emptyMessage(schedule: .daily)
            .hasPrefix("A scan runs on its own every day and reports here. Run one now"))
        XCTAssertTrue(ScanWording.emptyMessage(schedule: .weekly).hasPrefix("A scan runs on its own every week"))
        XCTAssertTrue(ScanWording.emptyMessage(schedule: .launch).hasPrefix("A scan runs each time JitPass starts"))
        XCTAssertTrue(ScanWording.emptyMessage(schedule: .off).hasPrefix("Nothing runs on its own. Scan to see where you stand"))
        for schedule in ScanSchedule.allCases {
            XCTAssertTrue(ScanWording.emptyMessage(schedule: schedule).hasSuffix("nothing leaves this Mac."), "\(schedule)")
        }
    }

    func testRunKindLabels() {
        XCTAssertEqual(ScanRunKind.scheduled.label, "Scheduled scan")
        XCTAssertEqual(ScanRunKind.byHand.label, "Scanned by hand")
        XCTAssertEqual(ScanRunKind.afterProtect.label, "Scanned after Protect")
        XCTAssertEqual(ScanRunKind.setup.label, "Scanned during setup")
    }
}

/// The Protect dialog names the cache copies it will also remove — the fix
/// for "Protect cleared my AI-cache alerts".
extension ScanWordingTests {
    private func copy(_ id: String, agent: String, area: String, origin: String) throws -> ScanFinding {
        let json = """
        {"record_type":"finding","record_id":"\(id)","finding_type":"agent_cached_secret","severity":"high",
         "file_path":"/h/.claude/\(id)","evidence":"a copy","remedy":"manual","agent":"\(agent)","cache_area":"\(area)",
         "origin_path":"\(origin)"}
        """.replacingOccurrences(of: "\n", with: "")
        return try JSONDecoder().decode(ScanFinding.self, from: Data(json.utf8))
    }

    func testSweepSentenceIsAbsentWithoutCopies() {
        XCTAssertNil(ScanWording.sweepSentence(copies: []))
    }

    func testSweepSentenceCountsAndPlacesTheCopies() throws {
        let one = try [copy("a", agent: "Claude Code", area: "transcripts", origin: "/h/notion/.env")]
        XCTAssertEqual(
            ScanWording.sweepSentence(copies: one),
            "It also removes the copy the scan found in Claude Code's transcripts. "
                + "A copy it can't safely rewrite is left in place and named when it's done."
        )
        let many = try [
            copy("a", agent: "Claude Code", area: "transcripts", origin: "/h/notion/.env"),
            copy("b", agent: "Claude Code", area: "transcripts", origin: "/h/notion/.env"),
            copy("c", agent: "Claude Code", area: "edit history", origin: "/h/notion/.env"),
            copy("d", agent: "Cursor", area: "chat database", origin: "/h/notion/.env")
        ]
        XCTAssertEqual(
            ScanWording.sweepSentence(copies: many)?.hasPrefix(
                "It also removes the 4 copies the scan found in Claude Code's transcripts and edit history, and in Cursor's chat database. "
            ),
            true
        )
    }

    func testCopiesFromAFileAreTheOnesTheDialogNames() throws {
        let summary = #"{"record_type":"scan_summary","total_findings":3,"risk_level":"high","exposure_score":50,"#
            + #""secrets_total":3,"secrets_protected":1,"secrets_migratable":1,"files_scanned":10}"#
        let copies = try [
            copy("a", agent: "Claude Code", area: "transcripts", origin: "/h/notion/.env"),
            copy("b", agent: "Claude Code", area: "transcripts", origin: "/h/other/.env"),
            copy("c", agent: "Cursor", area: "chat database", origin: "/h/notion/.env")
        ]
        let report = try ScanReport(findings: copies, summary: JSONDecoder().decode(ScanSummary.self, from: Data(summary.utf8)))
        XCTAssertEqual(report.copies(from: ["/h/notion/.env"]).map(\.id), ["a", "c"])
        XCTAssertEqual(report.copies(from: ["/h/nothing"]), [])
    }
}
