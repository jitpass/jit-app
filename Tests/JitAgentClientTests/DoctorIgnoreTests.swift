// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Doctor ignore (jit 2.1): every card can be ignored from its ⋯ menu,
/// ignored findings fold into one line and count toward nothing, and a
/// profile whose login ran out is advice with a terminal login.
///
/// The fixture is written by hand to the contract jit 2.1 is being built
/// to (jitpass/jit branch doctor-ignore); recapture it from that build.
final class DoctorIgnoreTests: XCTestCase {
    private static func ignore(_ kind: String, _ name: String) -> String {
        #""ignore":{"kind":"\#(kind)","name":"\#(name)","argv":["jit","doctor","ignore","--kind","\#(kind)","\#(name)"]}"#
    }

    private static func unignore(_ kind: String, _ name: String) -> String {
        #""unignore":{"kind":"\#(kind)","name":"\#(name)","argv":["jit","doctor","unignore","--kind","\#(kind)","\#(name)"]}"#
    }

    private let json = #"""
    {"schema_version":2,"ok":false,"problems":[{"kind":"missing","profile":"mcp-okta","scope":"global","variable":"OKTA_ORG_URL",
    "path":"mcp-okta/OKTA_ORG_URL","detail":"","fixes":[{"command":"jit vault set mcp-okta/OKTA_ORG_URL",
    "argv":["vault","set","mcp-okta/OKTA_ORG_URL"],"destructive":false,"presence":true}],"ignore_changed":true,
    \#(ignore("missing", "mcp-okta/OKTA_ORG_URL"))},
    {"kind":"profile_missing","profile":"aws-dev","file":"/Users/me/.aws/config","launchers":[{"kind":"aws",
    "file":"/Users/me/.aws/config","detail":"[profile dev]","profile":"aws-dev"}],\#(ignore("profile_missing", "aws-dev"))}],
    "warnings":[{"kind":"not_logged_in","profile":"aws-prod","file":"/Users/me/.aws/config",
    "detail":"aws --profile prod · ~/.aws/config [profile prod]","action":"`clisso get prod` to log in again",
    "fixes":[{"command":"clisso get prod","argv":["clisso","get","prod"],"external":true,"destructive":false}],
    \#(ignore("not_logged_in", "aws-prod"))},
    {"kind":"backup","detail":"no vault export on record, so the vault only decrypts on this Mac.",
    "fixes":[{"command":"jit vault export <file>","argv":["vault","export","<file>"],"presence":true,"needs":"<file>",
    "destructive":false}],\#(ignore("backup", "backup"))}],
    "ignored":[{"kind":"legacy_envelope","detail":"11 secrets use an old format","ignored_since":"2026-09-12",
    \#(unignore("legacy_envelope", "legacy_envelope"))},{"kind":"missing","profile":"k8s","variable":"CERT","path":"k8s/CERT",
    "ignored_since":"2026-09-18",\#(unignore("missing", "k8s/CERT"))},{"kind":"missing","profile":"k8s","variable":"CERT",
    "path":"k8s/CERT","ignored_since":"2026-09-18",\#(unignore("missing", "k8s/CERT"))}]}
    """#

    private func report() throws -> DoctorReport {
        try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
    }

    private func board() throws -> DoctorBoard {
        try DoctorBoard.make(report(), home: "/Users/me")
    }

    func testDecodesTheIgnoreFields() throws {
        let report = try report()
        XCTAssertEqual(report.problems.first?.ignore?.argv, ["jit", "doctor", "ignore", "--kind", "missing", "mcp-okta/OKTA_ORG_URL"])
        XCTAssertEqual(report.problems.first?.ignoreChanged, true)
        XCTAssertEqual(report.ignored.count, 3)
        XCTAssertEqual(report.ignored.first?.ignoredSince, "2026-09-12")
        XCTAssertEqual(report.verdict, "2 problems, 2 warnings", "the ignored ones count toward nothing")
        let old = try JSONDecoder().decode(DoctorReport.self, from: Data(#"{"ok":true,"problems":[],"warnings":[]}"#.utf8))
        XCTAssertEqual(old.ignored, [], "an older jit has none")
    }

    func testEveryCardCanBeIgnored() throws {
        let board = try board()
        for card in board.cards {
            guard case let .button(last)? = card.menu.last else {
                return XCTFail("\(card.id) has no Ignore")
            }
            XCTAssertEqual(last.title, "Ignore", card.id)
        }
        let okta = try XCTUnwrap(board.cards.first { $0.id == "missing:mcp-okta" })
        XCTAssertEqual(okta.ignoreButton?.command, .ignore([
            ["doctor", "ignore", "--kind", "missing", "mcp-okta/OKTA_ORG_URL", "--format", "json"]
        ]))
        XCTAssertTrue(okta.changedSinceIgnored)
        XCTAssertFalse(board.cards.first { $0.id == "backup" }?.changedSinceIgnored ?? true)
    }

    /// A problem asks once, in one line; advice is ignored unasked.
    func testOnlyAProblemAsks() throws {
        let board = try board()
        XCTAssertEqual(
            board.cards.first { $0.id == "missing:mcp-okta" }?.ignoreConfirmation,
            "It still fails; Doctor just stops counting it.", "no tool known: the profile's own card"
        )
        XCTAssertEqual(
            board.cards.first { $0.id.hasPrefix("profile_missing") }?.ignoreConfirmation,
            "aws --profile dev still fails; Doctor just stops counting it."
        )
        var tool = try XCTUnwrap(board.cards.first { $0.id == "missing:mcp-okta" })
        tool.tools = ["okta-mcp-server"]
        XCTAssertEqual(tool.ignoreConfirmation, "okta-mcp-server still fails; Doctor just stops counting it.")
        tool.tools = ["a", "b"]
        XCTAssertEqual(tool.ignoreConfirmation, "a and b still fail; Doctor just stops counting them.")
        XCTAssertNil(board.cards.first { $0.id == "backup" }?.ignoreConfirmation)
        XCTAssertNil(board.cards.first { $0.id == "not_logged_in" }?.ignoreConfirmation)
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

    func testIgnoredFoldIntoOneList() throws {
        let board = try board()
        XCTAssertEqual(board.ignored.map(\.text), [
            "legacy_envelope · Tidy up · since 2026-09-12", "k8s/CERT · Broken now · since 2026-09-18"
        ], "one row per kind and name")
        XCTAssertEqual(board.ignored.last?.showAgain, DoctorButton("Show Again", .unignore([
            "doctor", "unignore", "--kind", "missing", "k8s/CERT", "--format", "json"
        ])))
        XCTAssertEqual(board.headline, "2 problems to fix")
        XCTAssertEqual(DoctorBoard.Tier.allCases.map { board.cards(in: $0).count }, [2, 1, 1], "tabs count no ignored card")
    }

    func testNotLoggedInLogsInInTheTerminal() throws {
        let card = try XCTUnwrap(board().cards.first { $0.id == "not_logged_in" })
        XCTAssertEqual(card.tier, .recommended)
        XCTAssertEqual(card.title, "1 profile isn't logged in")
        XCTAssertEqual(card.reason, "Its tool fails until you log in again. Logging in opens the terminal.")
        XCTAssertEqual(card.rows.map(\.text), ["aws --profile prod · ~/.aws/config [profile prod]"])
        XCTAssertEqual(card.rows.first?.buttons, [DoctorButton("Log In in Terminal", .terminal("clisso get prod"))])
    }

    func testIgnoreResult() throws {
        let done = try DoctorIgnoreResult.parse(Data(#"{"ignored":[{"kind":"backup","name":"backup"}],"unignored":[]}"#.utf8))
        XCTAssertEqual(done.ignored.map(\.name), ["backup"])
        XCTAssertNil(done.error)
        let refused = try DoctorIgnoreResult.parse(Data(#"{"ignored":[],"unignored":[],"error":"no such finding"}"#.utf8))
        XCTAssertEqual(refused.error, "no such finding")
    }
}
