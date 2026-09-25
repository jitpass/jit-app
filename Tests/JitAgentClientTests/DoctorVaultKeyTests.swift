// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Doctor's two vault key cards (frame H of the Secure Enclave mockup):
/// the Recommended offer to move the key, and Fix now for a key this
/// Mac's Secure Enclave does not have.
final class DoctorVaultKeyTests: XCTestCase {
    private func report(_ json: String) throws -> DoctorReport {
        try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
    }

    private let clean = #"{"schema_version":2,"ok":true,"problems":[],"warnings":[]}"#

    func testTheOfferIsARecommendedCardWithMoveAndDontSuggestAgain() throws {
        let board = try DoctorBoard.make(report(clean), offersVaultKeyMove: true)
        let card = try XCTUnwrap(board.cards.first)
        XCTAssertEqual(board.cards.count, 1)
        XCTAssertEqual(card.tier, .recommended)
        XCTAssertEqual(card.title, "Keep the vault key in the Secure Enclave")
        XCTAssertEqual(card.reason, "In the keychain, a program running as you could read it. One Touch ID moves it.")
        XCTAssertEqual(card.primary, DoctorButton("Move…", .moveVaultKey))
        XCTAssertFalse(card.primaryProminent)
        XCTAssertEqual(card.menu, [.button(DoctorButton("Don't Suggest Again", .dismissVaultKeyOffer))])
        // Nothing is broken, so the header is amber and says so.
        XCTAssertEqual(board.mark, .amber)
        XCTAssertEqual(board.headline, "Nothing is broken")
    }

    func testNoOfferUnlessAsked() throws {
        XCTAssertTrue(try DoctorBoard.make(report(clean)).cards.isEmpty)
    }

    /// The offer sits with the other Recommended cards, after Fix now.
    func testTheOfferComesAfterFixNow() throws {
        let board = try DoctorBoard.make(report(VaultKeyTests.goneFromKeychainReport), offersVaultKeyMove: true)
        XCTAssertEqual(board.cards.map(\.tier), [.broken, .recommended])
    }

    func testALostKeyIsFixNowWithRestore() throws {
        let board = try DoctorBoard.make(report(VaultKeyTests.lostReport))
        let card = try XCTUnwrap(board.cards.first)
        XCTAssertEqual(card.tier, .broken)
        XCTAssertEqual(card.title, "This Mac's Secure Enclave doesn't have the vault key")
        XCTAssertEqual(card.reason, "The vault can't open here. A recovery file brings every secret back.")
        let restore = try XCTUnwrap(card.primary)
        XCTAssertEqual(restore.title, "Restore from Recovery File…")
        XCTAssertTrue(card.primaryProminent)
        XCTAssertEqual(restore.steps.first?.argv, [["vault", "init"], ["vault", "import", "<file>", "--stdin", "--yes"]])
        XCTAssertEqual(restore.steps.first?.needs, .existingPath(placeholder: "<file>"))
    }

    /// A keychain key that is gone keeps its own card: no init, no enclave.
    func testAKeyGoneFromTheKeychainIsUnchanged() throws {
        let card = try XCTUnwrap(try DoctorBoard.make(report(VaultKeyTests.goneFromKeychainReport)).cards.first)
        XCTAssertEqual(card.title, "Master key missing")
        XCTAssertEqual(card.primary?.title, "Import a Backup…")
        XCTAssertEqual(card.primary?.steps.first?.argv, [["vault", "import", "<file>", "--stdin", "--yes"]])
    }
}
