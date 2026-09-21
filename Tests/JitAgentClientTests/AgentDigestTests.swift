// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// One row per agent, four facts in a fixed order, one link to the home of
/// the fact that needs the reader.
final class AgentDigestTests: XCTestCase {
    private func input(
        key: ToolKeyState = .protected, wrapped: Bool = true, healthy: Bool = true, scanned: Bool = true,
        copies: Int = 0, areas: [String] = [], reads: Int? = 0, grant: Date? = nil
    ) -> AgentDigest.Input {
        AgentDigest.Input(
            tool: "claude", key: key, wrapped: wrapped, healthy: healthy, stateLabel: "shim is missing",
            scanned: scanned, copies: copies, areas: areas, readsToday: reads, grantUntil: grant, home: "/Users/me"
        )
    }

    func testAllClearHasFourGreenFactsAndNoLink() {
        let digest = AgentDigest.make(input())
        XCTAssertEqual(digest.facts, ["Key wrapped", "no cached copies", "no decoy reads today", "no grant"])
        XCTAssertEqual(digest.state, .green)
        XCTAssertNil(digest.link)
    }

    func testCopiesAreRedAndLinkToFindings() {
        let digest = AgentDigest.make(input(copies: 7, areas: ["transcripts", "edit history"], reads: 2))
        XCTAssertEqual(digest.facts[1], "7 cached copies in its transcripts and edit history")
        XCTAssertEqual(digest.facts[2], "2 decoy reads today")
        XCTAssertEqual(digest.state, .red)
        XCTAssertEqual(digest.link, .findings)
    }

    func testAKeyInTheOpenIsAmberAndLinksToTools() {
        let open = AgentDigest.make(input(key: .found("/Users/me/.cursor/settings.json"), wrapped: false))
        XCTAssertEqual(open.facts[0], "Key in the open, ~/.cursor/settings.json")
        XCTAssertEqual(open.state, .amber)
        XCTAssertEqual(open.link, .tools)

        let login = AgentDigest.make(input(key: .found("keychain"), wrapped: false))
        XCTAssertEqual(login.facts[0], "Key in claude's own login, not in the vault")
        XCTAssertEqual(login.link, .tools)

        let broken = AgentDigest.make(input(healthy: false))
        XCTAssertEqual(broken.facts[0], "Key wrapped, but the shim is missing")
        XCTAssertEqual(broken.state, .amber)
    }

    func testCopiesOutrankAKeyInTheOpen() {
        let digest = AgentDigest.make(input(key: .found("/Users/me/x"), wrapped: false, copies: 1))
        XCTAssertEqual(digest.state, .red)
        XCTAssertEqual(digest.link, .findings, "the link goes to the worst fact's home")
    }

    func testUncheckedFactsLowerNothing() {
        let digest = AgentDigest.make(input(key: .unknown, wrapped: false, scanned: false, reads: nil))
        XCTAssertEqual(digest.facts, ["Key not checked yet", "caches not searched yet", "reads not checked yet", "no grant"])
        XCTAssertEqual(digest.state, .green)
        XCTAssertNil(digest.link)
    }

    func testAGrantIsNamedAndLinkedWhenNothingElseNeedsYou() {
        let until = Date(timeIntervalSince1970: 1_800_759_600)
        let digest = AgentDigest.make(input(grant: until))
        XCTAssertEqual(digest.facts[3], "grant until " + SessionState.clock(until))
        XCTAssertEqual(digest.link, .grants)
        XCTAssertEqual(digest.state, .green)
        XCTAssertEqual(AgentDigest.Home.grants.title, "Grants")
    }
}
