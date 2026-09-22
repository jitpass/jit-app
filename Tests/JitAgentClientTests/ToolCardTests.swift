// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// One card per wrapped tool: which tier, what jit hands it, and one fact
/// from the audit — health, last use, other readers, sessions.
final class ToolCardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_100_000)

    private func wrapped(
        _ tool: String, shim: String = "ok", kind: String = "shim", capture: String? = nil, addedDaysAgo: Double = 20
    ) -> ToolRecord {
        var record = ToolRecord(
            tool: tool, kind: kind, wrapped: true, shim: shim,
            injects: [ToolInject(
                name: "TOKEN",
                vaultPath: "wrap-\(tool)/TOKEN",
                stored: true
            )], capture: capture, verifyHint: "\(tool) --version"
        )
        record.addedUnix = Int64(now.timeIntervalSince1970 - addedDaysAgo * 86400)
        return record
    }

    func testActivityCountsReadsOfTheToolsPathsAndNamesOtherReaders() throws {
        let json = """
        {"commands":[],"auth_events":[
          {"unix_time":1790000000,"kind":"use","op":"unwrap","by":"jit","launched_by":"gh","labels":["wrap-gh/GH_TOKEN"]},
          {"unix_time":1790050000,"kind":"use","op":"unwrap","by":"/usr/bin/python3 x.py","labels":["wrap-gh/GH_TOKEN","other/THING"]},
          {"unix_time":1790060000,"kind":"use","op":"unwrap","by":"jit","launched_by":"gh","labels":["wrap-gh/GH_TOKEN"]},
          {"unix_time":1790070000,"kind":"use","op":"unwrap","by":"jit","launched_by":"claude","labels":["other/THING"]},
          {"unix_time":1790080000,"kind":"serve","op":"decoy","labels":["~/x/.env"]}]}
        """
        let audit = try JSONDecoder().decode(AuditReport.self, from: Data(json.utf8))
        let activity = audit.toolActivity(vaultPaths: ["wrap-gh/GH_TOKEN"])
        XCTAssertEqual(activity.reads, 3)
        XCTAssertEqual(activity.lastRead, Date(timeIntervalSince1970: 1_790_060_000))
        XCTAssertEqual(activity.readers, ["gh", "python3"])
        XCTAssertEqual(activity.others(than: "gh"), ["python3"])
        XCTAssertEqual(audit.toolActivity(vaultPaths: []), ToolActivity())
    }

    func testAHealthyReadToolIsWorkingAndSaysWhoRead() {
        let activity = ToolActivity(reads: 41, lastRead: now.addingTimeInterval(-7200), readers: ["gh"])
        let card = ToolCard.make(wrapped("gh"), sessions: [], activity: activity, now: now)
        XCTAssertEqual(card.tier, .working)
        XCTAssertEqual(card.detail, "wrap-gh/TOKEN")
        XCTAssertEqual(card.fact, "last read 2 hours ago by gh · 41 reads this week · no other program")
        XCTAssertEqual(card.verb, .verify)
        XCTAssertNil(card.todo)

        let shared = ToolCard.make(
            wrapped("gh"),
            sessions: [],
            activity: ToolActivity(reads: 2, lastRead: now, readers: ["gh", "python3"]),
            now: now
        )
        XCTAssertTrue(shared.fact.hasSuffix("also read by python3"))
    }

    func testAWrappedToolNeverReadIsSilent() {
        let card = ToolCard.make(wrapped("terraform", addedDaysAgo: 21), sessions: [], activity: ToolActivity(), now: now)
        XCTAssertEqual(card.tier, .silent)
        XCTAssertTrue(card.fact.hasPrefix("0 reads since "), card.fact)
        XCTAssertEqual(card.todo, "terraform is wrapped but has never read its key")
        XCTAssertEqual(ToolCard.make(wrapped("gh"), sessions: [], activity: nil, now: now).fact, "reads not checked yet")
    }

    func testABrokenShimAndAnExpiredSessionAreFixNow() {
        var broken = wrapped("gh", shim: "missing")
        broken.shimDetail = "the shim file is gone"
        let card = ToolCard.make(broken, sessions: [], activity: nil, now: now)
        XCTAssertEqual(card.tier, .fixNow)
        XCTAssertEqual(card.fact, "shim missing · the shim file is gone")
        XCTAssertEqual(card.verb, .repair)
        XCTAssertEqual(card.todo, "gh's shim is missing")

        let sessions = [
            CLISession(profile: "aws-stage", expiresUnix: Int64(now.timeIntervalSince1970 - 7200), live: false, mint: "clisso get stage"),
            CLISession(profile: "aws-prod", expiresUnix: Int64(now.timeIntervalSince1970 + 5 * 3600), live: true, mint: "clisso get prod")
        ]
        let capture = ToolCard.make(
            wrapped("clisso", kind: "capture", capture: "aws-stage · aws-prod"),
            sessions: sessions,
            activity: nil,
            now: now
        )
        XCTAssertEqual(capture.tier, .fixNow)
        XCTAssertEqual(capture.detail, "captures aws-stage · aws-prod")
        XCTAssertEqual(capture.fact, "aws-stage expired 2 hours ago · aws-prod live, 5h left · 2 sessions")
        XCTAssertEqual(capture.verb, .logIn("clisso get stage"))
        XCTAssertEqual(capture.todo, "aws-stage's session ran out 2 hours ago")

        let live = ToolCard.make(wrapped("clisso", kind: "capture", capture: "aws-prod"), sessions: [sessions[1]], activity: nil, now: now)
        XCTAssertEqual(live.tier, .working)
        XCTAssertEqual(live.fact, "aws-prod live, 5h left")
    }
}
