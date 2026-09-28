// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// A dev build beside the installed app runs its own jit while the service
/// runs the installed one: Restart Service from the dev build was refused
/// every time (2026-09-28). It is offered only when the two are one file.
final class ServiceOwnerTests: XCTestCase {
    private let installed = "/Applications/JitPass.app/Contents/Helpers/JitPassAgent.app/Contents/MacOS/jit"

    func testARestartIsOfferedOnlyForTheAppsOwnJitOrWhenUnknown() throws {
        XCTAssertNil(ServiceOwner.elsewhere(service: installed, own: installed), "same file: a real restart")
        XCTAssertEqual(ServiceOwner.elsewhere(service: installed, own: "/Users/me/dev/JitPass.app/Contents/MacOS/jit"), installed)
        XCTAssertNil(ServiceOwner.elsewhere(service: nil, own: installed), "an older service says nothing: as before")
        XCTAssertNil(ServiceOwner.elsewhere(service: installed, own: nil))

        // The app's MacOS/jit is a symlink to the helper's: the same file.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("jit").path
        FileManager.default.createFile(atPath: real, contents: Data())
        let link = dir.appendingPathComponent("link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
        XCTAssertNil(ServiceOwner.elsewhere(service: real, own: link))
    }

    func testThePlaceIsTheAppThatHoldsThatJit() {
        XCTAssertEqual(ServiceOwner.place(installed, home: "/Users/me"), "/Applications/JitPass.app")
        XCTAssertEqual(ServiceOwner.place("/Users/me/dev/JitPass.app/Contents/MacOS/jit", home: "/Users/me"), "~/dev/JitPass.app")
        XCTAssertEqual(ServiceOwner.place("/opt/homebrew/bin/jit", home: "/Users/me"), "/opt/homebrew/bin/jit")
    }

    func testDoctorsServiceCardSaysWhereToRestartInsteadOfOfferingIt() throws {
        let json = #"""
        {"ok":true,"problems":[],"warnings":[
          {"kind":"service",
           "detail":"The background service is running a different build than this CLI (service 2.3.2, CLI dev).",
           "action":"`jit service restart` to move it now instead of waiting",
           "fixes":[{"command":"jit service restart","argv":["service","restart"],"external":false,"destructive":false,"presence":false}]}]}
        """#
        let report = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
        let board = DoctorBoard.make(report, home: "/Users/me")
        let card = try XCTUnwrap(board.cards.first { $0.items.contains { $0.kind == "service" } })
        XCTAssertEqual(card.primary?.title, "Restart Service", "the same jit: the button stays")
        let elsewhere = try XCTUnwrap(board.restartingElsewhere(installed, home: "/Users/me").cards.first { $0.id == card.id })
        XCTAssertNil(elsewhere.primary)
        XCTAssertTrue(elsewhere.reason?.hasSuffix("The service runs the jit in /Applications/JitPass.app; restart it from there.") == true)
        XCTAssertEqual(board.restartingElsewhere(nil), board, "unknown: as before")
    }

    /// Restart Service anywhere on a service card: its ⋯ when Show Log is
    /// the primary, and each row's buttons and menu on a card of several
    /// service findings. None is left for a service jit won't restart.
    func testRestartIsGoneFromTheMenuAndEveryRow() throws {
        let restart = DoctorButton(
            "Restart Service",
            .run([DoctorAction("Restart Service", "jit service restart", argv: [["service", "restart"]])])
        )
        let log = DoctorButton("Show Log", .run([DoctorAction("Show Log", "jit service log", argv: [["service", "log"]])]))
        var card = DoctorCard(id: "service", tier: .recommended, title: "Background service", items: [
            DoctorItem(kind: "service", detail: "a different build"), DoctorItem(kind: "service", detail: "the binary is gone")
        ])
        card.primary = log
        card.menu = [.button(restart), .separator, .button(log)]
        card.rows = [
            DoctorCardRow(id: "a", text: "a different build", mono: false, buttons: [restart, log], menu: [.button(restart)]),
            DoctorCardRow(id: "b", text: "the binary is gone", mono: false, buttons: [restart])
        ]
        let board = DoctorBoard(headline: "1 warning", mark: .amber, cards: [card])
        let out = try XCTUnwrap(board.restartingElsewhere(installed, home: "/Users/me").cards.first)
        XCTAssertEqual(out.primary, log, "Show Log stays")
        XCTAssertEqual(out.menu, [.button(log)], "no restart, and no separator left leading")
        XCTAssertEqual(out.rows.map(\.buttons), [[log], []])
        XCTAssertEqual(out.rows[0].menu, [])
        XCTAssertTrue(out.reason?.contains("restart it from there") == true)
    }
}
