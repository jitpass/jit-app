// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

final class GrantDraftTests: XCTestCase {
    private let caido = DiscoveredProfile(name: "mcp-caido", root: "/Users/me/Security-Ops", manifestPath: "/a", keys: ["CAIDO_URL"])
    private let urlscan = DiscoveredProfile(
        name: "mcp-urlscan",
        root: "/Users/me/Security-Ops",
        manifestPath: "/b",
        keys: ["URLSCAN_API_KEY"]
    )

    func testTheSentenceFillsInAsTheBlanksAreAnswered() {
        var draft = GrantDraft()
        XCTAssertEqual(draft.sentenceText, "Let a program under an app use some secrets, until you revoke it.")
        XCTAssertEqual(draft.missing, "Name a program and pick its app")

        draft.program = "claude"
        draft.anchorPID = 501
        draft.anchorName = "iTerm2"
        XCTAssertEqual(draft.missing, "Tick at least one profile")

        draft.profiles = [caido, urlscan]
        XCTAssertNil(draft.missing)
        XCTAssertTrue(draft.isComplete)
        XCTAssertEqual(draft.sentenceText, "Let claude under iTerm2 use mcp-caido and mcp-urlscan, until you revoke it.")
        XCTAssertEqual(draft.secretCount, 2)
        XCTAssertEqual(draft.grantProfiles, [caido.grantProfile, urlscan.grantProfile])
    }

    func testOneProcessAlwaysHasADeadline() {
        var draft = GrantDraft(cover: .oneProcess, pid: 57394, processName: "claude", profiles: [caido], term: .hours(8))
        XCTAssertNil(draft.missing)
        XCTAssertEqual(draft.sentenceText, "Let claude · pid 57394 use mcp-caido, for 8 hours.")
        XCTAssertEqual(draft.terms, [.hours(1), .hours(8), .hours(24), .hours(168)], "until revoked is not offered for one process")
        draft.term = .untilRevoked
        XCTAssertEqual(draft.missing, "One process always has a deadline")
        XCTAssertEqual(GrantDraft(cover: .everyCopy).terms.last, .untilRevoked)
    }

    func testTermWords() {
        XCTAssertEqual(GrantDraft.termPhrase(.hours(1)), "for 1 hour")
        XCTAssertEqual(GrantDraft.termPhrase(.hours(24)), "for 24 hours")
        XCTAssertEqual(GrantDraft.termPhrase(.hours(168)), "for 7 days")
        XCTAssertEqual(GrantDraft.termLabel(.hours(168)), "7d")
        XCTAssertEqual(GrantDraft.termLabel(.untilRevoked), "Until revoked")
        XCTAssertNil(GrantDraft.Term.untilRevoked.ttl)
        XCTAssertEqual(GrantDraft.Term.hours(8).ttl, 28800)
    }
}
