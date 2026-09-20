// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The Doctor window redesign, at the layer that can be tested: what the
/// header counts, what a row says, what the one question asks, and where
/// jit's own words go now that no terminal pane opens.
final class DoctorWindowTests: XCTestCase {
    /// Four leftover records in four folders, worded the way jit words
    /// them: the file first, then the group named twice.
    private func leftovers(_ folders: [String], home: String = NSHomeDirectory()) throws -> DoctorBoard {
        let findings = folders.map { folder in
            let file = "\(home)/Security-Ops/ai_tooling/mcp_servers/\(folder)/.env.pointers"
            let shown = "~/Security-Ops/ai_tooling/mcp_servers/\(folder)/.env.pointers"
            return #"{"kind":"stale_pointers","file":"\#(file)","path":"\#(folder)","#
                + #""detail":"\#(shown) lists 2 secrets under \#(folder)/, and the vault has nothing under \#(folder)/","#
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

    // MARK: - The header

    /// "1 problem to fix" in red, over four files that break nothing, was
    /// contradicted by the card's own note two lines below. A kind that
    /// knows better words its own header, and picks its own mark with it.
    func testAKindWithItsOwnWordsSaysThemInTheHeader() throws {
        let board = try leftovers(["google-workspace", "okta-mcp-server-2", "descope", "jamf"])
        XCTAssertEqual(board.headline, "4 leftover files to clear")
        XCTAssertEqual(board.subline, "Nothing is failing. jit wrote these notes, and the secrets they name are gone from the vault.")
        XCTAssertEqual(board.mark, .amber, "nothing is failing, so the mark must not say something is")
        let one = try leftovers(["jamf"])
        XCTAssertEqual(one.headline, "1 leftover file to clear")
    }

    /// Every other kind keeps the count it had: this is not a licence to
    /// call a broken tool a tidy-up.
    func testAKindWithoutItsOwnWordsStillCountsProblemsInRed() throws {
        let board = try DoctorBoardTests.board(
            #"{"schema_version":2,"ok":false,"problems":[{"kind":"vault_error","detail":"the vault won't open"}],"warnings":[]}"#
        )
        XCTAssertEqual(board.headline, "1 problem to fix")
        XCTAssertEqual(board.mark, .red)
    }

    /// One count, counted once. The header, the filter and the card count
    /// the same things: four files, not one card.
    func testTheHeaderTheFilterAndTheCardAgree() throws {
        let board = try leftovers(["a", "b", "c", "d"])
        let card = try card(board)
        XCTAssertEqual(card.toFix, 4)
        XCTAssertEqual(board.toFix, 4)
        XCTAssertEqual(board.tabs.first { $0.title == "Fix now" }?.count, 4)
        XCTAssertTrue(board.headline.hasPrefix("4 "), board.headline)
    }

    /// A tier with nothing in it is left out of the filter, not greyed
    /// out: "Recommended 0" was a control that could never be pressed.
    func testAnEmptyTierIsNoPillAtAll() throws {
        let board = try leftovers(["a"])
        XCTAssertEqual(board.tabs.map(\.title), ["All", "Fix now"])
    }

    // MARK: - The rows

    /// Four rows that opened with the same six words and truncated the
    /// part that told them apart. Now: the file, the folders that differ,
    /// and one clause of fact.
    func testARowIsItsFileItsFolderAndOneFact() throws {
        let board = try leftovers(["google-workspace", "okta-mcp-server-2"])
        let card = try card(board)
        let row = try XCTUnwrap(card.rows.first)
        XCTAssertEqual(row.name, ".env.pointers")
        XCTAssertEqual(row.folder, "mcp_servers/google-workspace", "the two folders that tell it from its sibling")
        XCTAssertEqual(row.fact, "Lists 2 secrets under google-workspace/ · the vault holds none")
        XCTAssertNotEqual(card.rows[0].folder, card.rows[1].folder, "rows must differ in their first four words")
    }

    /// The clause is compressed only when jit actually repeated itself.
    /// A sentence it words differently is left exactly as it wrote it.
    func testTheVaultClauseIsOnlyShortenedWhenItRepeats() {
        let repeated = "lists 2 secrets under jamf/, and the vault has nothing under jamf/"
        XCTAssertEqual(DoctorAdvice.shortenVaultClause(repeated), "lists 2 secrets under jamf/ · the vault holds none")
        let different = "lists 2 secrets under jamf/, and the vault has nothing under okta/"
        XCTAssertEqual(DoctorAdvice.shortenVaultClause(different), different, "a different group is not a repeat")
        let plain = "expects 3 values under wiz/, and the vault has nothing there"
        XCTAssertEqual(DoctorAdvice.shortenVaultClause(plain), plain, "jit's other wording survives untouched")
    }

    /// Only a row that IS a file reads as one. Everything else keeps the
    /// sentence it had.
    func testOnlyAFileRowIsSplit() throws {
        let mounts = try DoctorBoardTests.board(
            #"{"schema_version":2,"ok":true,"problems":[],"warnings":["#
                + #"{"kind":"mount_stale","path":"/Users/me/a/.env","detail":"project gone"},"#
                + #"{"kind":"mount_stale","path":"/Users/me/b/.env","detail":"project gone"}]}"#
        )
        let card = try XCTUnwrap(mounts.cards.first { $0.id.contains("mount_stale") })
        XCTAssertNil(card.rows.first?.name, "a mount row is a path, not a file to read")
    }

    /// Show in Finder, Copy Path and Ignore move off the row and into its
    /// ⋯, where a mis-click costs nothing. The two verbs stay.
    func testARowKeepsTwoVerbsAndPutsTheRestBehindTheEllipsis() throws {
        let card = try card(leftovers(["jamf", "descope"]))
        let row = try XCTUnwrap(card.rows.first)
        XCTAssertEqual(row.buttons.map(\.title), ["Edit", "Delete…"], "the safe verb first, the one that asks second")
        let menu = row.menu.compactMap { entry -> String? in
            if case let .button(button) = entry {
                return button.title
            }
            return nil
        }
        XCTAssertEqual(menu, ["Show File in Finder", "Copy Path"])
    }

    /// Four rows were four questions. `jit migrate forget` takes them all,
    /// so the card offers one, and never as its blue call to action.
    func testManyLeftoversOfferOneDeleteForAllOfThem() throws {
        let home = NSHomeDirectory()
        let many = try card(leftovers(["jamf", "descope"], home: home))
        XCTAssertEqual(many.primary?.title, "Delete All 2…")
        XCTAssertFalse(many.primaryProminent, "a destructive action is never the card's blue button")
        XCTAssertEqual(many.primary?.steps.first?.argv, [[
            "migrate", "forget", "--yes",
            "\(home)/Security-Ops/ai_tooling/mcp_servers/jamf/.env.pointers",
            "\(home)/Security-Ops/ai_tooling/mcp_servers/descope/.env.pointers"
        ]])
        let lone = try card(leftovers(["jamf"]))
        XCTAssertEqual(lone.primary?.title, "Edit", "one file needs no Delete All, and reading it is still the first move")
    }

    // MARK: - The question

    /// The question names the thing and keeps the command one click away.
    /// It used to open with "This runs: jit migrate forget ~/…".
    func testTheQuestionNamesTheFileAndNeverOpensWithTheCommand() throws {
        let card = try card(leftovers(["jamf"]))
        let action = try XCTUnwrap(card.menu.compactMap { entry -> DoctorAction? in
            if case let .button(button) = entry, button.title.hasPrefix("Delete File") {
                return button.steps.first
            }
            return nil
        }.first)
        let question = DoctorAdvice.confirm(action)
        XCTAssertEqual(question.question, "Delete this file?")
        XCTAssertEqual(question.lead, "The file goes. Nothing else does: no secret, no profile, no mount.")
        XCTAssertFalse(question.lead.contains("jit migrate"), "the command explains jit to itself")
        XCTAssertEqual(question.button, "Delete File", "the button is the verb, never OK")
        XCTAssertEqual(question.files.count, 1, "the file the question is about, drawn as a file")
        XCTAssertTrue(question.files[0].hasSuffix("/jamf/.env.pointers"), question.files[0])
        // Refusals are promises: they are the reason this is safe to press.
        XCTAssertEqual(question.checks.count, 2)
        XCTAssertTrue(question.checks.allSatisfy { $0.contains("jit stops and deletes nothing") }, "\(question.checks)")
        // One click away, and only one click: the exact line, --yes and all.
        XCTAssertTrue(question.command.hasPrefix("jit migrate forget --yes "), question.command)
        XCTAssertFalse(question.presence, "no secret is read, so no Touch ID")
    }

    /// Several files, one question, every one of them named. A question
    /// saying one path while jit deletes four understates a delete.
    func testAQuestionAboutSeveralFilesNamesEveryOne() throws {
        let card = try card(leftovers(["jamf", "descope", "okta"]))
        let question = try DoctorAdvice.confirm(XCTUnwrap(card.primary?.steps.first))
        XCTAssertEqual(question.question, "Delete these 3 files?")
        XCTAssertEqual(question.files.count, 3)
        for folder in ["jamf", "descope", "okta"] {
            XCTAssertTrue(question.text.contains("/\(folder)/.env.pointers"), "\(folder) is not in \(question.text)")
        }
    }

    // MARK: - Saying what happened

    /// A failure used to open a black pane, and the line quoted jit inside
    /// the app's own sentence. Now the row keeps the app's words and jit's
    /// own go verbatim underneath.
    func testAFailurePutsJitsWordsInTheirOwnBlockNotInTheSentence() throws {
        let card = try card(leftovers(["jamf"]))
        let button = try XCTUnwrap(card.primary)
        let failed = card.outcome(
            key: card.id, button: button, completed: 0,
            output: "jit migrate forget: refused\nmount active at ~/Security-Ops/custom_scripts/jamf", failed: true
        )
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.said, "jit migrate forget: refused\nmount active at ~/Security-Ops/custom_scripts/jamf")
        XCTAssertNil(failed.line, "with jit's words in their own block the sentence says nothing twice")
        XCTAssertFalse(failed.title.contains("jit says"), failed.title)
        let silent = card.outcome(key: card.id, button: button, completed: 0, output: "", failed: true)
        XCTAssertNil(silent.said)
        XCTAssertEqual(silent.line, "jit stopped without saying why.")
        let cancelled = card.outcome(key: card.id, button: button, completed: 0, output: "cancelled", failed: true)
        XCTAssertNil(cancelled.said, "a cancelled Touch ID is not a diagnosis")
    }

    // MARK: - Copy Report

    /// What the ⋯ menu's Open in Terminal was really being asked for.
    func testCopyReportIsTheWindowAsText() throws {
        let board = try leftovers(["jamf", "descope"])
        let text = board.reportText
        XCTAssertTrue(text.hasPrefix("2 leftover files to clear"), text)
        XCTAssertTrue(text.contains("[Fix now] Leftover jit records"), text)
        XCTAssertTrue(text.contains(".env.pointers · mcp_servers/jamf ·"), text)
        XCTAssertTrue(text.contains("the vault holds none"), text)
    }
}
