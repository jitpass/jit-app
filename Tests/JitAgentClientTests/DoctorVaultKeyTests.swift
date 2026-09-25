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
        XCTAssertEqual(card.reason, "In the keychain, a program running as you could read it. Touch ID moves it.")
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

    /// jit's `vault_move` finding (jitpass/jit#169), as doctor.go writes it:
    /// the fix is derived from its action, presence true, not destructive.
    static let moveReport = #"""
    {"schema_version":2,"ok":false,"problems":[{"kind":"vault_move","detail":"moving the vault key into the Secure \#
    Enclave did not finish, so every command that changes the vault will refuse until it does.","action":"`jit vault \#
    rekey --wrapper secure-enclave` to finish it","fixes":[{"command":"jit vault rekey --wrapper secure-enclave","argv":\#
    ["vault","rekey","--wrapper","secure-enclave"],"destructive":false,"presence":true}]}],"warnings":[]}
    """#

    /// jit's `vault_restore` finding: secrets sealed to the lost key that
    /// no import has brought back; the import is destructive and needs a file.
    static let restoreReport = #"""
    {"schema_version":2,"ok":false,"problems":[{"kind":"vault_restore","detail":"3 secrets were sealed to a key this \#
    Mac no longer has, so they can't be opened. A recovery file brings them back.","action":"`jit vault import <file>` \#
    from a `jit vault export` backup","fixes":[{"command":"jit vault import <file>","argv":["vault","import","<file>"],\#
    "destructive":true,"presence":true,"needs":"<file>"}]}],"warnings":[]}
    """#

    /// The unfinished move's card runs the Settings row's own Finish Move,
    /// toward jit's target, and nothing that reads as a rotation: a
    /// rotation's `jit vault rekey` refuses to finish a move.
    func testAnUnfinishedMoveIsFixNowWithFinishMove() throws {
        let board = try DoctorBoard.make(report(Self.moveReport))
        let card = try XCTUnwrap(board.cards.first)
        XCTAssertEqual(board.cards.count, 1)
        XCTAssertEqual(card.tier, .broken)
        XCTAssertEqual(card.title, "Unfinished vault key move")
        XCTAssertEqual(
            card.reason,
            "Moving the vault key into the Secure Enclave did not finish, "
                + "so every command that changes the vault will refuse until it does."
        )
        let finish = try XCTUnwrap(card.primary)
        XCTAssertEqual(finish.title, "Finish Move")
        XCTAssertTrue(card.primaryProminent)
        XCTAssertEqual(finish.steps.first?.argv, [VaultKeyPlace.secureEnclave.moveArguments])
        XCTAssertEqual(finish.steps.first?.presence, true)
        XCTAssertEqual(finish.steps.first?.destructive, false)
        let titles = [card.primary?.title] + card.menu.map { entry -> String? in
            if case let .button(button) = entry {
                return button.title
            }
            return nil
        }
        XCTAssertFalse(titles.contains("Finish Rotation"))
    }

    /// The way back, from jit's own fix.
    func testAnUnfinishedMoveBackFinishesTowardTheKeychain() throws {
        let json = Self.moveReport.replacingOccurrences(of: "secure-enclave", with: "keychain")
        let card = try XCTUnwrap(try DoctorBoard.make(report(json)).cards.first)
        XCTAssertEqual(card.primary?.steps.first?.argv, [VaultKeyPlace.keychain.moveArguments])
    }

    /// A pending restore offers the lost card's restore without `jit vault
    /// init`: the key exists already, and init would refuse or replace it.
    func testAPendingRestoreIsFixNowWithTheImportAlone() throws {
        let board = try DoctorBoard.make(report(Self.restoreReport))
        let card = try XCTUnwrap(board.cards.first)
        XCTAssertEqual(card.tier, .broken)
        XCTAssertEqual(card.title, "Secrets this Mac can't open")
        XCTAssertEqual(
            card.reason, "3 secrets were sealed to a key this Mac no longer has, so they can't be opened. A recovery file brings them back."
        )
        let restore = try XCTUnwrap(card.primary)
        XCTAssertEqual(restore.title, "Restore from Recovery File…")
        XCTAssertEqual(restore.steps.first?.argv, [["vault", "import", "<file>", "--stdin", "--yes"]])
        XCTAssertEqual(restore.steps.first?.needs, .existingPath(placeholder: "<file>"))
        XCTAssertEqual(restore.steps.first?.destructive, true)
        XCTAssertEqual(restore.steps.first?.input, .passphrase(prompt: "The recovery file's passphrase"))
    }

    /// A keychain key that is gone keeps its own card: no init, no enclave.
    func testAKeyGoneFromTheKeychainIsUnchanged() throws {
        let card = try XCTUnwrap(try DoctorBoard.make(report(VaultKeyTests.goneFromKeychainReport)).cards.first)
        XCTAssertEqual(card.title, "Master key missing")
        XCTAssertEqual(card.primary?.title, "Import a Backup…")
        XCTAssertEqual(card.primary?.steps.first?.argv, [["vault", "import", "<file>", "--stdin", "--yes"]])
    }
}
