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
        XCTAssertTrue(
            ScanWording.newScanMessage().hasPrefix("Your last findings stay until this scan replaces them."),
            "New Scan… over a report says first that the report is not gone"
        )
        for schedule in ScanSchedule.allCases {
            XCTAssertTrue(ScanWording.emptyMessage(schedule: schedule).hasSuffix("nothing leaves this Mac."), "\(schedule)")
        }
    }

    func testDeepSublineCountsTheVaultCopies() {
        let line = ScanWording.wholeMacSubline(
            ScanRun(
                kind: .deep,
                at: ran,
                schedule: .weekly,
                newCount: nil,
                previousAt: nil,
                excludes: 0,
                fullDiskAccess: true,
                vaultCopies: 2
            ),
            now: ran.addingTimeInterval(10), calendar: calendar, locale: locale
        )
        XCTAssertTrue(
            line.hasPrefix("Deep scan, by hand · just now · next Sunday 03:00. "),
            line
        )
        XCTAssertTrue(
            ScanWording.folderSubline(folder: "~/proj", at: nil, excludes: 0, fullDiskAccess: true, deep: true)
                .hasPrefix("Deep scan of ~/proj. ")
        )
    }

    func testDepthIsGatedOnTheFirstVaultedSecret() {
        XCTAssertFalse(ScanMode.deepAvailable(secretsStored: nil))
        XCTAssertFalse(ScanMode.deepAvailable(secretsStored: 0))
        XCTAssertTrue(ScanMode.deepAvailable(secretsStored: 1))
        XCTAssertTrue(ScanMode.fact(.deep, secretsStored: 0)
            .hasSuffix("Available once your vault holds a secret — protect something first."))
        XCTAssertTrue(ScanMode.fact(.deep, secretsStored: 1).contains("the 1 secret you've vaulted"))
        XCTAssertTrue(ScanMode.fact(.deep, secretsStored: 14).contains("the 14 secrets you've vaulted"))
        XCTAssertTrue(ScanMode.fact(.regular, secretsStored: nil).hasSuffix("No Touch ID."))
    }

    func testRunKindLabels() {
        XCTAssertEqual(ScanRunKind.deep.label, "Deep scan, by hand")
        XCTAssertEqual(ScanRunKind.scheduled.label, "Scheduled scan")
        XCTAssertEqual(ScanRunKind.byHand.label, "Scanned by hand")
        XCTAssertEqual(ScanRunKind.afterProtect.label, "Scanned after Protect")
        XCTAssertEqual(ScanRunKind.setup.label, "Scanned during setup")
        XCTAssertEqual(ScanRunKind.deepAfterProtect.label, "Deep scan after Protect")
    }

    /// 78 findings became 25 after a Redact of 2: the rescan ran regular
    /// and searched for none of the 53 vault copies the deep scan on
    /// screen had found. A Protect's rescan keeps a deep report's depth
    /// while the vault is open; locked, it runs regular and never prompts.
    func testAProtectsRescanKeepsADeepReportsDepthWhileTheVaultIsOpen() {
        for previous in [nil, .scheduled, .byHand, .afterProtect, .setup] as [ScanRunKind?] {
            XCTAssertEqual(ScanRunKind.afterProtect(replacing: previous, unlockedFor: nil), .afterProtect)
            XCTAssertEqual(ScanRunKind.afterProtect(replacing: previous, unlockedFor: 600), .afterProtect)
        }
        for deep in [ScanRunKind.deep, .deepAfterProtect] {
            XCTAssertEqual(ScanRunKind.afterProtect(replacing: deep, unlockedFor: 600), .deepAfterProtect)
            XCTAssertEqual(ScanRunKind.afterProtect(replacing: deep, unlockedFor: nil), .afterProtect, "locked: regular, no Touch ID")
            XCTAssertEqual(
                ScanRunKind.afterProtect(replacing: deep, unlockedFor: 5),
                .afterProtect,
                "a session about to end cannot carry a vault read"
            )
        }
        XCTAssertTrue(ScanRunKind.deepAfterProtect.isDeep)
        XCTAssertTrue(ScanRunKind.deepAfterProtect.isAfterProtect)
        XCTAssertTrue(ScanRunKind.afterProtect.isAfterProtect)
        XCTAssertFalse(ScanRunKind.afterProtect.isDeep)
        XCTAssertFalse(ScanRunKind.deep.isAfterProtect)

        XCTAssertNil(SessionState.locked(reason: nil).unlockedFor)
        XCTAssertNil(SessionState.notRunning.unlockedFor)
        XCTAssertEqual(SessionState.unlocked(expiresIn: 90, ceilingAt: nil).unlockedFor, 90)
    }

    /// The header names the run that found the copies: the deep rescan
    /// itself, or, on a regular run that carries them, the deep scan they
    /// came from.
    func testTheHeaderSaysWhichRunFoundTheVaultCopies() {
        let ran = Date(timeIntervalSince1970: 1_700_000_000)
        let line = ScanWording.wholeMacSubline(
            ScanRun(
                kind: .deepAfterProtect,
                at: ran,
                schedule: .off,
                newCount: nil,
                previousAt: nil,
                excludes: 0,
                fullDiskAccess: true,
                vaultCopies: 53
            ),
            now: ran.addingTimeInterval(10), calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(
            line.hasPrefix("Deep scan after Protect · just now · no schedule. "),
            line
        )

        let carried = ScanWording.wholeMacSubline(
            ScanRun(
                kind: .afterProtect, at: ran, schedule: .off, newCount: nil, previousAt: nil, excludes: 0, fullDiskAccess: true,
                vaultCopies: 53, vaultCopiesFrom: ran.addingTimeInterval(-4 * 3600)
            ),
            now: ran.addingTimeInterval(10), calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(
            carried.hasPrefix(
                "Scanned after Protect · just now · no schedule · copies of vaulted secrets from the deep scan 4 hours ago. "
            ),
            carried
        )
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
            "Also removes the copy the scan found in Claude Code's transcripts."
        )
        let many = try [
            copy("a", agent: "Claude Code", area: "transcripts", origin: "/h/notion/.env"),
            copy("b", agent: "Claude Code", area: "transcripts", origin: "/h/notion/.env"),
            copy("c", agent: "Claude Code", area: "edit history", origin: "/h/notion/.env"),
            copy("d", agent: "Cursor", area: "chat database", origin: "/h/notion/.env")
        ]
        XCTAssertEqual(
            ScanWording.sweepSentence(copies: many)?.hasPrefix(
                "Also removes the 4 copies the scan found in Claude Code's transcripts and edit history, and in Cursor's chat database."
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

    /// The copies themselves are a to-do line now; the sentence keeps the
    /// fixtures clause and, on a regular run, where its copies came from.
    func testTheSentenceCountsFixturesOutAndNamesNoCopies() {
        let ran = Date(timeIntervalSince1970: 1_700_000_000)
        let line = ScanWording.wholeMacSubline(
            ScanRun(
                kind: .deep,
                at: ran,
                schedule: .off,
                newCount: nil,
                previousAt: nil,
                excludes: 1,
                fullDiskAccess: true,
                vaultCopies: 35,
                fixtures: 8
            ),
            now: ran.addingTimeInterval(10), calendar: Calendar(identifier: .gregorian), locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(
            line.hasPrefix("Deep scan, by hand · just now · no schedule · 8 test fixtures, not counted · excluding 1 folder. "),
            line
        )
        XCTAssertTrue(
            ScanWording.folderSubline(folder: "~/proj", at: nil, excludes: 0, fullDiskAccess: true, fixtures: 1)
                .hasPrefix("~/proj · 1 test fixture, not counted. ")
        )
    }
}
