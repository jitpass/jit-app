// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The Doctor window's board on a real jit 2.0.0 report: which cards,
/// in which tier, saying what, with which buttons.
final class DoctorBoardTests: XCTestCase {
    static func board(_ json: String = DoctorBoardFixture.json) throws -> DoctorBoard {
        try DoctorBoard.make(JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8)), home: "/Users/me")
    }

    /// The board as text, the way the window reads top to bottom.
    static func render(_ board: DoctorBoard) -> String {
        var lines = ["\(board.headline)", board.subline.map { "  \($0)" } ?? ""]
        for tier in DoctorBoard.Tier.allCases {
            let cards = board.cards(in: tier)
            lines.append("\n[\(tier.title)] \(cards.count)")
            for card in cards {
                let primary = card.primary.map { "  [\($0.title)]" + (card.primaryProminent ? " (blue)" : "") } ?? ""
                lines.append("● \(card.title)" + primary)
                card.reason.map { lines.append("  \($0)") }
                card.detail.map { lines.append("  `\($0)`") }
                for row in card.rows {
                    lines.append("  └ \(row.text)" + row.buttons.map { "  [\($0.title)]" }.joined())
                }
                if !card.listed.isEmpty {
                    lines.append("  \(card.disclosure(open: false))")
                    lines += card.listed.map { "    \($0.name) · \($0.note)" }
                }
                let menu = card.menu.map { entry -> String in
                    if case let .button(button) = entry {
                        return button.title
                    }
                    return "—"
                }
                if !menu.isEmpty {
                    lines.append("  ⋯ " + menu.joined(separator: " | "))
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private func card(_ board: DoctorBoard, _ id: String) throws -> DoctorCard {
        try XCTUnwrap(board.cards.first { $0.id == id }, "no card \(id) in \(board.cards.map(\.id))")
    }

    private func titles(_ entries: [DoctorMenuEntry]) -> [String] {
        entries.map { entry in
            if case let .button(button) = entry {
                return button.title
            }
            return "—"
        }
    }

    func testHeadlineNamesTheToolsThatWontStart() throws {
        let board = try Self.board()
        XCTAssertEqual(board.headline, "2 tools won't start")
        XCTAssertEqual(board.subline, "google-workspace-investigate and okta-mcp-server · aws --profile dev and admin fail too")
        XCTAssertEqual(board.mark, .red)
        XCTAssertEqual(DoctorBoard.Tier.allCases.map { board.cards(in: $0).count }, [4, 2, 3], "tabs count cards, not findings")
        XCTAssertEqual(board.cards.count, 9)
    }

    /// A missing secret's card is its tool, found in the report's other
    /// findings: the nested-wrapper sentence and the record's tools.
    func testMissingSecretsAreTheToolThatWontStart() throws {
        let board = try Self.board()
        let okta = try card(board, "missing:mcp-okta-mcp-server")
        XCTAssertEqual(okta.tier, .broken)
        XCTAssertEqual(okta.title, "okta-mcp-server won't start")
        XCTAssertEqual(okta.reason, "Its profile names 2 secrets the vault doesn't hold: OKTA_ORG_URL, OKTA_SCOPES")
        XCTAssertEqual(okta.detail, "~/Security-Ops/.mcp.json · profile mcp-okta-mcp-server")
        XCTAssertEqual(okta.primary?.title, "Set Values…")
        XCTAssertTrue(okta.primaryProminent)
        XCTAssertEqual(okta.primary?.steps.map(\.argv), [
            [["vault", "set", "mcp-okta-mcp-server/OKTA_ORG_URL", "--stdin", "--yes"]],
            [["vault", "set", "mcp-okta-mcp-server/OKTA_SCOPES", "--stdin", "--yes"]]
        ], "the existing Set Value, once per secret, each its own hidden field")
        XCTAssertEqual(okta.primary?.presence, true)
        // Set Values… stays the prominent primary, and its opposite is ONE
        // control carrying every variable — not one per row. `jit profile
        // drop` takes VAR..., so the click cost of the two answers matches
        // instead of the remove costing a click and a dialog per variable.
        XCTAssertEqual(titles(okta.menu), [
            "Show Config in Finder", "Show Profile File", "Copy Path", "—", "Migrate a File…",
            "Remove 2 Variables…", "Open in Terminal"
        ])
        XCTAssertEqual(
            okta.menu.dropLast().last,
            .button(DoctorButton("Remove 2 Variables…", .run([DoctorAdvice.removeVariables(
                "mcp-okta-mcp-server", ["OKTA_ORG_URL", "OKTA_SCOPES"]
            )])))
        )
        XCTAssertEqual(okta.menu.last, .button(DoctorButton("Open in Terminal", .terminal(
            "jit vault set mcp-okta-mcp-server/OKTA_ORG_URL\njit vault set mcp-okta-mcp-server/OKTA_SCOPES"
        ))))
        XCTAssertEqual(
            okta.menu[1],
            .button(DoctorButton("Show Profile File", .reveal("/Users/me/.jit/profiles/mcp-okta-mcp-server.yaml")))
        )
        XCTAssertEqual(okta.file, "/Users/me/Security-Ops/.mcp.json")
        XCTAssertTrue(okta.restartsInEditor)

        let google = try card(board, "missing:mcp-google-workspace-investigate")
        XCTAssertEqual(google.title, "google-workspace-investigate won't start")
        XCTAssertEqual(google.reason, "Its profile names a secret the vault doesn't hold: GOOGLE_CLOUD_PROJECT")
        XCTAssertEqual(google.primary?.title, "Set Value…")
    }

    /// jit 2.1 puts the tools on the finding itself: the card names them
    /// with no other finding to borrow from, and a project store (where
    /// the profile lives) is not a tool.
    func testAMissingSecretNamesItsOwnTools() throws {
        let launchers = #"[{"kind":"project_store","file":"/Users/me/Security-Ops","profile":"mcp-okta-mcp-server"},"#
            + #"{"kind":"mcp","file":"/Users/me/Security-Ops/.mcp.json","detail":"okta-mcp-server","profile":"mcp-okta-mcp-server"}]"#
        let finding = { (name: String) in
            #"{"kind":"missing","profile":"mcp-okta-mcp-server","scope":"global","variable":"\#(name)","#
                + #""path":"mcp-okta-mcp-server/\#(name)","launchers":\#(launchers)}"#
        }
        let board = try Self.board(#"{"schema_version":2,"ok":false,"problems":["# + finding("OKTA_ORG_URL") + ","
            + finding("OKTA_SCOPES") + #"],"warnings":[]}"#)
        let okta = try card(board, "missing:mcp-okta-mcp-server")
        XCTAssertEqual(okta.title, "okta-mcp-server won't start")
        XCTAssertEqual(okta.detail, "~/Security-Ops/.mcp.json · profile mcp-okta-mcp-server")
        XCTAssertEqual(okta.tools, ["okta-mcp-server"])
        XCTAssertTrue(okta.restartsInEditor)
        XCTAssertEqual(board.headline, "1 tool won't start")
        let aws = BoardContext.ownTools([DoctorItem(
            kind: "missing", profile: "aws-dev",
            launchers: [DoctorLauncher(kind: "aws", file: "/Users/me/.aws/config", detail: "[profile dev]", profile: "aws-dev")]
        )])
        XCTAssertEqual(aws.map(\.name), ["aws --profile dev"])
    }

    func testAMissingSecretWithNoKnownToolNamesItsProfile() throws {
        let json = #"{"schema_version":2,"ok":false,"problems":[{"kind":"corrupt","profile":"k8s","scope":"global","variable":"CERT","#
            + #""path":"k8s/CERT"},{"kind":"corrupt","profile":"k8s","scope":"global","variable":"KEY","path":"k8s/KEY"}],"warnings":[]}"#
        let board = try Self.board(json)
        let k8s = try card(board, "corrupt:k8s")
        XCTAssertEqual(k8s.title, "Profile k8s can't start its tool")
        XCTAssertEqual(k8s.reason, "Its profile names 2 secrets the vault can't read: CERT, KEY")
        XCTAssertEqual(k8s.detail, "profile k8s")
        XCTAssertEqual(k8s.primary?.title, "Replace Values…")
        XCTAssertEqual(k8s.primary?.destructive, true, "each still confirmed as before")
        XCTAssertEqual(board.headline, "1 problem to fix")
        XCTAssertEqual(board.subline, "Profile k8s can't start its tool")
    }

    func testMissingProfilesByFileAndKind() throws {
        let aws = try card(Self.board(), "profile_missing:/Users/me/.aws/config|aws")
        XCTAssertEqual(aws.title, "aws --profile dev and admin fail")
        XCTAssertEqual(
            aws.reason,
            "~/.aws/config names aws-dev and aws-admin, and jit has neither. Mint them again, or delete those [profile] blocks."
        )
        XCTAssertEqual(aws.primary, DoctorButton("Show in Finder", .reveal("/Users/me/.aws/config")))
        XCTAssertFalse(aws.primaryProminent, "it only shows the file")
        XCTAssertTrue(aws.tools.isEmpty)

        let context = BoardContext(all: [], home: "/Users/me")
        XCTAssertEqual(
            context.missingProfileTitle(kind: "aws", details: ["[profile dev]"], file: "", count: 1).0,
            "aws --profile dev fails"
        )
        XCTAssertEqual(context.missingProfileTitle(kind: "mcp", details: ["linear"], file: "", count: 1).0, "linear won't start")
        XCTAssertEqual(context.missingProfileTitle(kind: "kube", details: ["user ops"], file: "", count: 1).0, "kubectl fails as user ops")
        XCTAssertEqual(
            context.missingProfileTitle(kind: "shell_rc", details: ["line 4"], file: "/Users/me/.zshrc", count: 1).0,
            "A line in ~/.zshrc fails"
        )
    }

    func testPointerFilesAreOneCardOfRows() throws {
        let pointers = try card(Self.board(), "pointer_missing")
        XCTAssertEqual(pointers.title, "2 files point at secrets the vault doesn't have")
        XCTAssertNil(pointers.primary)
        XCTAssertEqual(pointers.rows.map(\.text), [
            "~/Documents/jitpass-playground/.env.bak · jitpass-playground-bak/API_KEY", "~/.clisso.yaml · wrap-clisso/acme-client-secret"
        ])
        XCTAssertEqual(pointers.rows.map { $0.buttons.map(\.title) }, [["Set Value…"], ["Set Value…"]])
        XCTAssertEqual(pointers.rows.map(\.file), ["/Users/me/Documents/jitpass-playground/.env.bak", "/Users/me/.clisso.yaml"])
    }

    /// Every profile one Attach records the config on, deleted record or
    /// none, is one card with one button that counts them all.
    func testOneAttachCardForTheConfig() throws {
        let board = try Self.board()
        let records = board.cards.filter { $0.id.hasPrefix("record:") }
        XCTAssertEqual(records.map(\.id), ["record:/Users/me/Security-Ops/.mcp.json"])
        let attach = try XCTUnwrap(records.first)
        XCTAssertEqual(attach.tier, .recommended)
        XCTAssertEqual(attach.title, "7 profiles don't record the config that starts them")
        XCTAssertEqual(attach.reason, "5 record ~/Documents/ai_security_workspace/.mcp.json, which is deleted, and 2 record none. "
            + "~/Security-Ops/.mcp.json starts their tools now. Nothing is broken; no secret changes.")
        XCTAssertEqual(attach.primary?.title, "Attach 7…")
        XCTAssertEqual(attach.primary?.steps.first?.planned, .attach(config: "/Users/me/Security-Ops/.mcp.json"))
        XCTAssertEqual(attach.disclosure(open: false), "Show the 7 profiles")
        XCTAssertEqual(attach.disclosure(open: true), "Hide the 7 profiles")
        XCTAssertEqual(attach.listed.map(\.note).filter { $0 == "records no config" }.count, 2)
        XCTAssertEqual(attach.listed.first, DoctorListedRow(name: "mcp-caido", note: "records a deleted config"))
    }

    func testRecordCardWordsWhenAllAgree() throws {
        let rows = try Self.board().cards.first { $0.id.hasPrefix("record:") }?.items ?? []
        let context = BoardContext(all: rows, home: "/Users/me")
        let deleted = context.recordCard(rows.filter { $0.kind == "config_deleted" })
        XCTAssertEqual(deleted.title, "5 profiles record a deleted config")
        XCTAssertEqual(deleted.reason, "They record ~/Documents/ai_security_workspace/.mcp.json, which is deleted. "
            + "~/Security-Ops/.mcp.json starts their tools now. Nothing is broken; no secret changes.")
        let bare = context.recordCard(rows.filter { $0.kind == "config_not_recorded" })
        XCTAssertEqual(bare.title, "2 profiles record no config")
        XCTAssertEqual(bare.reason, "~/Security-Ops/.mcp.json starts their tools, but they record no config. "
            + "Nothing is broken; no secret changes.")
    }

    func testNestedWrappersMigrateInTheAppAndAttachFirst() throws {
        let nested = try card(Self.board(), "mcp_nested:/Users/me/Security-Ops/.mcp.json")
        XCTAssertEqual(nested.tier, .recommended)
        XCTAssertEqual(nested.title, "3 MCP servers start jit inside jit")
        XCTAssertEqual(
            nested.reason,
            "Still working. Migrating ~/Security-Ops/.mcp.json again collapses each to one wrapper. Attach first."
        )
        XCTAssertEqual(nested.detail, "caido · google-workspace-investigate · okta-mcp-server")
        XCTAssertEqual(nested.primary?.title, "Migrate…")
        XCTAssertTrue(nested.primaryProminent)
        let migrate = try XCTUnwrap(nested.primary?.steps.first)
        XCTAssertEqual(migrate.planned, .migrate(targets: ["/Users/me/Security-Ops/.mcp.json"]))
        XCTAssertEqual(migrate.argv, [["migrate", "--yes", "/Users/me/Security-Ops/.mcp.json"]])
        XCTAssertEqual(titles(nested.menu), ["Show Config in Finder", "Copy Path", "—", "Open in Terminal"])
        XCTAssertEqual(nested.menu.last, .button(DoctorButton("Open in Terminal", .terminal("jit migrate ~/Security-Ops/.mcp.json"))))
    }

    func testTidyRows() throws {
        let tidy = try Self.board().cards(in: .tidy)
        XCTAssertEqual(tidy.map(\.title), ["2 profiles no tool uses", "No recovery file yet", "11 secrets in the older format"])
        XCTAssertEqual(tidy.map(\.reason), [
            "k8s-docker-desktop, token", "the vault only opens on this Mac", "can't tell if a value was swapped on disk"
        ])
        XCTAssertEqual(tidy.map { $0.primary?.title }, ["Review…", "Save…", "Re-encrypt…"])
        XCTAssertEqual(tidy[0].primary?.command, .review)
        XCTAssertEqual(tidy[1].primary?.steps.first?.argv, [["vault", "export", "<file>", "--stdin"]], "the existing export")
        XCTAssertEqual(tidy.map(\.primaryProminent), [false, false, false], "grey in Tidy up")
    }

    /// The tier is the engine's split: any problem is Broken now, a
    /// warning kind the app doesn't know is Tidy up.
    func testUnknownKindsFollowTheEnginesSplit() throws {
        let json = #"{"schema_version":2,"ok":false,"problems":[{"kind":"brand_new","detail":"something broke","fixes":[]}],"#
            + #""warnings":[{"kind":"also_new","detail":"a nudge","fixes":[]},{"kind":"service","detail":"old build","#
            + #""action":"`jit service restart`","fixes":[{"command":"jit service restart","argv":["service","restart"],"#
            + #""destructive":false}]}]}"#
        let board = try Self.board(json)
        XCTAssertEqual(board.cards.map(\.tier), [.broken, .recommended, .tidy])
        XCTAssertEqual(board.cards.map(\.title), ["Brand New", "Background service", "Also New"])
        XCTAssertEqual(board.cards[0].reason, "something broke")
        XCTAssertEqual(board.cards[1].primary?.title, "Restart Service")
        XCTAssertEqual(board.cards[2].reason, "a nudge")
        XCTAssertEqual(board.headline, "1 problem to fix")
    }

    func testNothingToFix() throws {
        let empty = try Self.board(#"{"schema_version":2,"ok":true,"problems":[],"warnings":[]}"#)
        XCTAssertEqual(empty.headline, "Nothing needs you")
        XCTAssertNil(empty.subline)
        XCTAssertEqual(empty.mark, .green)
        XCTAssertTrue(empty.isEmpty)
        let backup = try Self.board(#"{"ok":true,"problems":[],"warnings":[{"kind":"backup","detail":"no export"}]}"#)
        XCTAssertEqual(backup.headline, "Nothing needs you")
        XCTAssertEqual(backup.subline, "1 thing to tidy")
        let nested = try Self.board(#"{"ok":true,"problems":[],"warnings":[{"kind":"mcp_nested","path":"/p/.mcp.json"}]}"#)
        XCTAssertEqual(nested.headline, "Nothing is broken")
        XCTAssertEqual(nested.mark, .amber)
    }

    func testCardIDsAreStableAcrossARecheck() throws {
        XCTAssertEqual(try Self.board().cards.map(\.id), try Self.board().cards.map(\.id))
        XCTAssertEqual(try Set(Self.board().cards.map(\.id)).count, 9)
    }

    /// The board as the window reads, for a reviewer.
    func testRendersTheBoard() throws {
        let text = try Self.render(Self.board())
        XCTAssertTrue(text.hasPrefix("2 tools won't start"))
        print(text)
    }
}

/// Leftover `.pointers` records: the card a lone one produces, which is the
/// common case and was the broken one.
final class DoctorStalePointersCardTests: XCTestCase {
    private func board(_ count: Int) throws -> DoctorBoard {
        let findings = (0 ..< count).map { n in
            let file = "/Users/me/Security-Ops/custom_scripts/wiz\(n)/.env.pointers"
            return #"{"kind":"stale_pointers","file":"\#(file)","path":"wiz\#(n)","#
                + #""detail":"~/x/.env.pointers expects 3 values under wiz\#(n)/, and the vault has nothing there","#
                + #""action":"store those values, or `jit migrate forget <file>`","#
                + #""fixes":[{"command":"jit migrate forget \#(file)","#
                + #""argv":["migrate","forget","\#(file)"],"destructive":true}]}"#
        }
        return try DoctorBoardTests.board(
            #"{"schema_version":2,"ok":false,"problems":[\#(findings.joined(separator: ","))],"warnings":[]}"#
        )
    }

    private func card(_ board: DoctorBoard) throws -> DoctorCard {
        try XCTUnwrap(board.cards.first { $0.id.contains("stale_pointers") }, "no card in \(board.cards.map(\.id))")
    }

    /// The regression: Edit was built only on ROWS, and a single finding
    /// renders as a card with no rows. So the one stale record — much the
    /// commonest shape — offered no way to read the file, and the card's
    /// single prominent button was the one that deletes it.
    func testALoneRecordOffersEditFirstAndNeverAProminentDelete() throws {
        let card = try card(board(1))
        XCTAssertEqual(card.primary?.title, "Edit", "reading the file is the first move")
        XCTAssertFalse(card.primaryProminent, "a destructive action must never be the card's blue call to action")
        if case let .edit(path) = card.primary?.command {
            XCTAssertEqual(path, "/Users/me/Security-Ops/custom_scripts/wiz0/.env.pointers")
        } else {
            XCTFail("Edit must open the file itself, got \(String(describing: card.primary?.command))")
        }
        let menu = card.menu.map { entry -> String in
            if case let .button(button) = entry {
                return button.title
            }
            return "—"
        }
        XCTAssertTrue(menu.contains { $0.hasPrefix("Delete File") }, "\(menu)")
        XCTAssertTrue(menu.contains("Show File in Finder"), "jit's own file is not somebody's config: \(menu)")
    }

    /// The title and note the kind never had: it fell through to a bare,
    /// capitalized "Stale Pointers" with no explanation at all.
    func testTheCardSaysWhatALeftoverRecordIs() throws {
        let card = try card(board(1))
        XCTAssertEqual(card.title, "Leftover jit records")
        let reason = try XCTUnwrap(card.reason)
        XCTAssertFalse(reason.isEmpty)
        XCTAssertFalse(card.title.contains("Pointers"), "jit's own noun must not be the heading")
    }

    /// Several records keep a per-row Edit, which is where it already was.
    func testEveryRowKeepsItsOwnEdit() throws {
        let card = try card(board(3))
        XCTAssertEqual(card.rows.count, 3)
        for row in card.rows {
            XCTAssertEqual(row.buttons.first?.title, "Edit", "\(row.buttons.map(\.title))")
            XCTAssertTrue(row.buttons.contains { $0.title.hasPrefix("Delete File") }, "\(row.buttons.map(\.title))")
        }
    }
}
