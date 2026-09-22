// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// One rule for every panel row: a number plus one or two words, the dot
/// the window's mark or none, a green dot never beside a number.
final class PanelValueTests: XCTestCase {
    func testEveryValueFitsTheBudgetAndGreenNeverCarriesANumber() throws {
        let rows: [PanelValue.Row] = try [
            PanelValue.vault(secrets: 25),
            PanelValue.agents(copies: 31, needing: 0, scanned: true),
            PanelValue.agents(copies: 0, needing: 2, scanned: true),
            PanelValue.agents(copies: 0, needing: 0, scanned: true),
            PanelValue.agents(copies: 0, needing: 0, scanned: false),
            PanelValue.tools(broken: 1, expired: 1, toProtect: 1, wrapped: 3),
            PanelValue.tools(broken: 0, expired: 2, toProtect: 1, wrapped: 3),
            PanelValue.tools(broken: 0, expired: 0, toProtect: 1, wrapped: 3),
            PanelValue.tools(broken: 0, expired: 0, toProtect: 0, wrapped: 3),
            PanelValue.tools(broken: 0, expired: 0, toProtect: 0, wrapped: 0),
            PanelValue.service(running: true), PanelValue.service(running: false),
            PanelValue.grants(active: 0), PanelValue.grants(active: 1),
            XCTUnwrap(PanelValue.decoys(files: 3, broken: 1, readsToday: 3)),
            XCTUnwrap(PanelValue.decoys(files: 3, broken: 0, readsToday: 3)),
            XCTUnwrap(PanelValue.decoys(files: 3, broken: 0, readsToday: 0)),
            PanelValue.doctor(problems: 3, warnings: 2, checked: true, checking: false),
            PanelValue.doctor(problems: 0, warnings: 2, checked: true, checking: false),
            PanelValue.doctor(problems: 0, warnings: 0, checked: true, checking: false),
            PanelValue.doctor(problems: 0, warnings: 0, checked: false, checking: true),
            PanelValue.findings(todos: 2, worst: .red, scanned: true, scanning: false),
            PanelValue.findings(todos: 0, worst: .none, scanned: true, scanning: false),
            PanelValue.findings(todos: 0, worst: .none, scanned: false, scanning: false)
        ]
        for row in rows {
            XCTAssertLessThanOrEqual(row.text.count, 14, row.text)
            XCTAssertLessThanOrEqual(row.text.split(separator: " ").count, 3, row.text)
            if row.tone == .green {
                XCTAssertNil(row.text.first(where: \.isNumber), "a green dot says why in words: \(row.text)")
            }
        }
    }

    func testTheWorstFactWinsAndACountClaimsNoState() {
        XCTAssertEqual(PanelValue.vault(secrets: 25), .init("25 secrets"))
        XCTAssertEqual(PanelValue.agents(copies: 31, needing: 2, scanned: true), .init("31 copies", .red))
        XCTAssertEqual(PanelValue.agents(copies: 0, needing: 1, scanned: true), .init("1 needs you", .amber))
        XCTAssertEqual(PanelValue.agents(copies: 0, needing: 0, scanned: true), .init("all set", .green))
        XCTAssertEqual(PanelValue.tools(broken: 1, expired: 2, toProtect: 0, wrapped: 3), .init("1 broken", .red))
        XCTAssertEqual(PanelValue.tools(broken: 0, expired: 0, toProtect: 0, wrapped: 0), .init("none wrapped"))
        XCTAssertEqual(
            PanelValue.tools(broken: 0, expired: 0, toProtect: 0, wrapped: 2),
            .init("2 wrapped"),
            "good news, still a count: no dot"
        )
        XCTAssertEqual(PanelValue.service(running: true), .init("running", .green))
        XCTAssertEqual(PanelValue.service(running: false), .init("not running", .red))
        XCTAssertEqual(PanelValue.grants(active: 1), .init("1 active"))
        XCTAssertNil(PanelValue.decoys(files: 0, broken: 0, readsToday: 0))
        XCTAssertEqual(PanelValue.decoys(files: 3, broken: 1, readsToday: 3), .init("1 broken", .red))
        XCTAssertEqual(PanelValue.decoys(files: 3, broken: 0, readsToday: 1), .init("1 read today", .amber))
        XCTAssertEqual(PanelValue.decoys(files: 3, broken: 0, readsToday: 0), .init("3 files"))
        XCTAssertEqual(PanelValue.doctor(problems: 3, warnings: 2, checked: true, checking: false), .init("3 problems", .red))
        XCTAssertEqual(PanelValue.doctor(problems: 0, warnings: 0, checked: true, checking: false), .init("healthy", .green))
        XCTAssertEqual(PanelValue.findings(todos: 2, worst: .amber, scanned: true, scanning: false), .init("2 to do", .amber))
        XCTAssertEqual(PanelValue.findings(todos: 0, worst: .none, scanned: true, scanning: false), .init("all clear", .green))
        XCTAssertEqual(PanelValue.findings(todos: 0, worst: .none, scanned: false, scanning: true), .init("scanning…"))
        XCTAssertEqual(PanelValue.findings(todos: 0, worst: .none, scanned: false, scanning: false), .init("not scanned", .amber))
        XCTAssertEqual(
            PanelValue.agents(copies: 0, needing: 0, scanned: false),
            .init("not scanned", .amber),
            "the same word and dot as Findings"
        )
    }
}
