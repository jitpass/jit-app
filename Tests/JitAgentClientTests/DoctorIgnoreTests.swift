// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Doctor ignore (jit 2.1): every card can be ignored from its ⋯ menu,
/// ignored findings fold into one line and count toward nothing, and a
/// profile nobody has logged into is advice with a terminal login. On
/// jit 2.1.0's own output (DoctorIgnoreFixture).
final class DoctorIgnoreTests: XCTestCase {
    private func report(_ json: String = DoctorIgnoreFixture.json) throws -> DoctorReport {
        try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
    }

    private func board() throws -> DoctorBoard {
        try DoctorBoard.make(report(), home: "/Users/me")
    }

    private func card(_ id: String) throws -> DoctorCard {
        let cards = try board().cards
        return try XCTUnwrap(cards.first { $0.id == id }, "no \(id) in \(cards.map(\.id))")
    }

    func testDecodesTheIgnoreFields() throws {
        let report = try report()
        XCTAssertEqual(report.problems.first?.ignore?.argv, ["jit", "doctor", "ignore", "--kind", "missing", "mcp-okta-mcp-server"])
        let dev = try XCTUnwrap(report.warnings.first { $0.profile == "aws-dev" })
        XCTAssertEqual(dev.kind, "not_logged_in")
        XCTAssertEqual(dev.ignoreChanged, true, "ignored, then [profile dev] changed")
        XCTAssertEqual(report.ignored.map(\.profile), ["aws-admin"])
        XCTAssertEqual(report.ignored.first?.ignoredSince, "2026-09-19")
        XCTAssertEqual(report.ignored.first?.severity, "warning")
        XCTAssertFalse(report.warnings.contains { $0.profile == "aws-admin" }, "an ignored finding counts toward nothing")
        let old = try self.report(#"{"ok":true,"problems":[],"warnings":[]}"#)
        XCTAssertEqual(old.ignored, [], "an older jit has none")
    }

    func testEveryCardCanBeIgnored() throws {
        let board = try board()
        XCTAssertFalse(board.cards.isEmpty)
        for card in board.cards {
            guard case let .button(last)? = card.menu.last else {
                return XCTFail("\(card.id) has no Ignore")
            }
            XCTAssertEqual(last.title, "Ignore", card.id)
        }
        XCTAssertEqual(try card("missing:mcp-okta-mcp-server").ignoreButton?.command, .ignore([
            ["doctor", "ignore", "--kind", "missing", "mcp-okta-mcp-server", "--format", "json"]
        ]), "the profile's two missing secrets are one ignore")
        XCTAssertEqual(try card("not_logged_in").ignoreButton?.command, .ignore([
            ["doctor", "ignore", "--kind", "not_logged_in", "aws-dev", "--format", "json"]
        ]))
        XCTAssertTrue(try card("not_logged_in").changedSinceIgnored)
        XCTAssertFalse(try card("missing:mcp-okta-mcp-server").changedSinceIgnored)
    }

    /// A problem asks once, in one line; advice is ignored unasked.
    func testOnlyAProblemAsks() throws {
        XCTAssertEqual(
            try card("missing:mcp-okta-mcp-server").ignoreConfirmation,
            "okta-mcp-server still fails; Doctor just stops counting it."
        )
        XCTAssertEqual(
            try card("profile_missing:/Users/me/.aws/config|aws").ignoreConfirmation,
            "aws --profile qa still fails; Doctor just stops counting it."
        )
        var tools = try card("missing:mcp-okta-mcp-server")
        tools.tools = ["a", "b"]
        XCTAssertEqual(tools.ignoreConfirmation, "a and b still fail; Doctor just stops counting them.")
        tools.tools = []
        tools.title = "Profile x can't start its tool"
        XCTAssertEqual(tools.ignoreConfirmation, "It still fails; Doctor just stops counting it.")
        XCTAssertNil(try card("not_logged_in").ignoreConfirmation)
        XCTAssertNil(try card("record:/Users/me/Security-Ops/.mcp.json").ignoreConfirmation)
    }

    /// Only exactly `jit doctor ignore|unignore …` is ever run.
    func testOnlyDoctorIgnoreRuns() {
        XCTAssertNil(DoctorIgnoreCommand(argv: ["jit", "vault", "rm", "x"]).arguments("ignore"))
        XCTAssertNil(DoctorIgnoreCommand(argv: ["sh", "doctor", "ignore", "x"]).arguments("ignore"))
        XCTAssertNil(DoctorIgnoreCommand(argv: ["jit", "doctor", "unignore", "x"]).arguments("ignore"))
        XCTAssertNil(DoctorIgnoreCommand(argv: ["jit", "doctor", "ignore"]).arguments("ignore"))
        XCTAssertEqual(
            DoctorIgnoreCommand(argv: ["jit", "doctor", "ignore", "--kind", "backup", "backup"]).arguments("ignore"),
            ["doctor", "ignore", "--kind", "backup", "backup", "--format", "json"]
        )
    }

    /// An ignored row says where jit says the finding would be, from its
    /// severity.
    func testIgnoredRows() throws {
        let board = try board()
        XCTAssertEqual(board.ignored.map(\.text), ["aws-admin · Recommended · since 2026-09-19"])
        XCTAssertEqual(board.ignored.first?.showAgain, DoctorButton("Show Again", .unignore([
            "doctor", "unignore", "--kind", "not_logged_in", "aws-admin", "--format", "json"
        ])))
        let problem = try report(#"{"ok":false,"problems":[],"warnings":[],"ignored":[{"kind":"backup","severity":"problem"}]}"#)
        XCTAssertEqual(DoctorBoard.make(problem).ignored.first?.section, .broken, "jit's severity, not a guess from the kind")
        let loggedOut = try XCTUnwrap(board.cards.first { $0.id == "not_logged_in" })
        XCTAssertEqual(loggedOut.rows.count, 1, "aws-admin is ignored, only aws-dev is counted")
    }

    /// Ignored is a tab after Tidy up, there only while something is
    /// ignored, and the only place that counts the ignored findings.
    func testIgnoredIsItsOwnTab() throws {
        let board = try board()
        XCTAssertEqual(board.tabs.map(\.title), ["All", "Broken now", "Recommended", "Tidy up", "Ignored"])
        XCTAssertEqual(board.tabs.map(\.count), [board.cards.count, 2, 2, 1, 1])
        XCTAssertEqual(board.tabs.last?.tab, .ignored)
        XCTAssertEqual(board.tabs.last?.enabled, true)
        let none = try DoctorBoard.make(report(#"{"ok":true,"problems":[],"warnings":[]}"#))
        XCTAssertEqual(none.tabs.map(\.title), ["All", "Broken now", "Recommended", "Tidy up"], "no Ignored tab when none is")
        XCTAssertEqual(none.tabs.map(\.enabled), [true, false, false, false])
    }

    /// All is the three tiers: an ignored finding is on no card and in no
    /// count but its own tab's; the Ignored tab shows no tier.
    func testAllLeavesTheIgnoredOut() throws {
        let board = try board()
        XCTAssertFalse(board.cards.contains { card in card.items.contains { $0.profile == "aws-admin" } })
        XCTAssertEqual(board.tabs.first?.count, board.cards.count)
        for tier in DoctorBoard.Tier.allCases {
            XCTAssertTrue(board.shows(tier, on: .all))
            XCTAssertFalse(board.shows(tier, on: .ignored))
            XCTAssertEqual(board.shows(tier, on: .tier(.broken)), tier == .broken)
        }
        XCTAssertEqual(board.showing(.ignored), .ignored)
    }

    /// The last ignored row shown again: the Ignored tab falls back to All.
    func testIgnoredFallsBackToAll() throws {
        var board = try board()
        board.ignored = []
        XCTAssertEqual(board.showing(.ignored), .all)
        XCTAssertTrue(board.shows(.broken, on: .ignored), "what All shows")
        XCTAssertEqual(board.showing(.tier(.tidy)), .tier(.tidy), "a tier's tab stays put")
    }

    func testNotLoggedInLogsInInTheTerminal() throws {
        let card = try card("not_logged_in")
        XCTAssertEqual(card.tier, .recommended)
        XCTAssertEqual(card.title, "1 profile isn't logged in")
        XCTAssertEqual(card.reason, "Its tool fails until you log in again. Logging in opens the terminal.")
        XCTAssertEqual(card.rows.map(\.text), ["aws --profile dev · ~/.aws/config [profile dev]"])
        XCTAssertEqual(card.rows.first?.buttons, [DoctorButton("Log In in Terminal", .terminal("clisso get dev"))])
    }

    func testIgnoreResult() throws {
        let done = try DoctorIgnoreResult.parse(Data(DoctorIgnoreFixture.ignored.utf8))
        XCTAssertEqual(done.ignored.map(\.name), ["aws-dev"])
        XCTAssertNil(done.error)
        let back = try DoctorIgnoreResult.parse(Data(DoctorIgnoreFixture.unignored.utf8))
        XCTAssertEqual(back.unignored.map(\.name), ["aws-admin"])
        let refused = try DoctorIgnoreResult.parse(Data(#"{"ignored":[],"unignored":[],"error":"no such finding"}"#.utf8))
        XCTAssertEqual(refused.error, "no such finding")
    }

    /// The window for this report, for a reviewer.
    func testRendersTheBoard() throws {
        let board = try board()
        print(DoctorBoardTests.render(board) + "\n\n[Ignored] \(board.ignored.count)\n"
            + board.ignored.map { "● \($0.text)  [\($0.showAgain?.title ?? "")]" }.joined(separator: "\n"))
    }
}
