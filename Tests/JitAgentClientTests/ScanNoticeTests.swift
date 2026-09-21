// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// A scheduled run that finds something new is announced once, naming what
/// it found; one that changes nothing is silent.
final class ScanNoticeTests: XCTestCase {
    // Sunday 2027-01-24 03:00 UTC.
    private let ran = Date(timeIntervalSince1970: 1_800_759_600)
    private let home = "/Users/me"
    private var calendar: Calendar {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        utc.locale = Locale(identifier: "en_US_POSIX")
        return utc
    }

    private let locale = Locale(identifier: "en_US_POSIX")

    private func finding(
        _ id: String, path: String, type: String = "env_file_present", agent: String? = nil, area: String? = nil
    ) throws -> ScanFinding {
        var fields = [
            "\"record_type\":\"finding\"", "\"record_id\":\"\(id)\"", "\"finding_type\":\"\(type)\"",
            "\"severity\":\"high\"", "\"file_path\":\"\(path)\"", "\"evidence\":\"e\"", "\"remedy\":\"manual\""
        ]
        if let agent {
            fields.append("\"agent\":\"\(agent)\"")
        }
        if let area {
            fields.append("\"cache_area\":\"\(area)\"")
        }
        let json = "{" + fields.joined(separator: ",") + "}"
        return try JSONDecoder().decode(ScanFinding.self, from: Data(json.utf8))
    }

    private func make(_ new: [ScanFinding], now: Date) -> ScanNotice? {
        ScanNotices.make(new: new, at: ran, home: home, now: now, calendar: calendar, locale: locale)
    }

    func testNothingNewIsSilent() {
        XCTAssertNil(make([], now: ran))
    }

    func testFilesOnly() throws {
        let notice = try make([finding("1", path: "/Users/me/notion/.env")], now: ran.addingTimeInterval(9 * 3600))
        XCTAssertEqual(notice?.title, "Today's scan found 1 secret in the open")
        XCTAssertEqual(notice?.body, "~/notion/.env. Click to open Findings.")
    }

    func testCopiesOnlyGroupedByAgentAndArea() throws {
        let copies = try [
            finding("c1", path: "/Users/me/.claude/a.jsonl", type: "agent_cached_secret", agent: "Claude Code", area: "transcripts"),
            finding("c2", path: "/Users/me/.claude/b.jsonl", type: "agent_cached_secret", agent: "Claude Code", area: "transcripts"),
            finding("c3", path: "/Users/me/.claude/h", type: "agent_cached_secret", agent: "Claude Code", area: "edit history"),
            finding("c4", path: "/Users/me/.cursor/db", type: "agent_cached_secret", agent: "Cursor", area: "chat database")
        ]
        let notice = make(copies, now: ran.addingTimeInterval(2 * 86400))
        XCTAssertEqual(notice?.title, "Sunday's scan found 4 new cached copies of your secrets")
        XCTAssertEqual(
            notice?.body,
            "3 copies in Claude Code's transcripts and edit history, and 1 copy in Cursor's chat database. Click to open Findings."
        )
    }

    func testBothNamesTheFirstTwoFilesThenTheCopies() throws {
        let new = try [
            finding("1", path: "/Users/me/notion/.env"),
            finding("2", path: "/Users/me/.aws/old"),
            finding("3", path: "/opt/x/.env"),
            finding("c1", path: "/Users/me/.claude/a.jsonl", type: "agent_cached_secret", agent: "Claude Code", area: "transcripts")
        ]
        let notice = make(new, now: ran.addingTimeInterval(20 * 86400))
        XCTAssertEqual(notice?.title, "Jan 24's scan found 3 secrets in the open, and 1 cached copy")
        XCTAssertEqual(notice?.body, "~/notion/.env, ~/.aws/old, 1 more, and 1 copy in Claude Code's transcripts. Click to open Findings.")
    }

    func testDayWord() {
        func day(_ now: Date) -> String {
            ScanWording.dayWord(ran, now: now, calendar: calendar, locale: locale)
        }
        XCTAssertEqual(day(ran.addingTimeInterval(3600)), "today")
        XCTAssertEqual(day(ran.addingTimeInterval(86400)), "yesterday")
        XCTAssertEqual(day(ran.addingTimeInterval(3 * 86400)), "Sunday")
        XCTAssertEqual(day(ran.addingTimeInterval(20 * 86400)), "Jan 24")
        XCTAssertEqual(day(ran.addingTimeInterval(400 * 86400)), "Jan 24, 2027")
    }
}
