// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The vault key states where jit names no fix, or not the usual one: a
/// restore jit could not check (`restore_check_error`), and an unfinished
/// change of the key this jit doesn't understand (doctor's `rekey_unknown`).
/// No decisions in the app: it offers only what jit's finding names.
final class VaultKeyBlockedTests: XCTestCase {
    private func report(_ json: String) throws -> DoctorReport {
        try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
    }

    private func vault(_ store: String = "keychain", restore: Bool? = true, checkError: String? = nil) -> CLIVaultStatus {
        CLIVaultStatus(
            secretsStored: 5, initialized: "yes", keyStore: store, restorePending: restore, restoreCheckError: checkError
        )
    }

    private static let checkError = "reading the lost key's record: open /Users/me/.jit/vault/lost-key.json: permission denied"

    /// doctorsections.go's vault_restore when the check failed: the detail
    /// says why, and there is no action and no fix.
    static let uncheckedReport = #"""
    {"schema_version":2,"ok":false,"problems":[{"kind":"vault_restore","detail":"couldn't check the vault for secrets \#
    sealed to a lost key: reading the lost key's record: permission denied"}],"warnings":[]}
    """#

    /// The same from jitpass/jit se-status-gaps, which names its way out:
    /// `jit vault import --finish` (doctorsections.go, doctorfixes.go: not
    /// destructive, no Touch ID). It imports nothing, so it is not the
    /// restore the app must not add.
    static let finishReport = #"""
    {"schema_version":2,"ok":false,"problems":[{"kind":"vault_restore","detail":"couldn't check the vault for secrets \#
    sealed to a lost key: reading the lost key's record: permission denied","action":"`jit vault import --finish` once \#
    you've imported every recovery file you have","fixes":[{"command":"jit vault import --finish","argv":["vault",\#
    "import","--finish"],"destructive":false,"presence":false}]}],"warnings":[]}
    """#

    // MARK: - A restore jit could not check

    func testDecodesTheRestoreCheckError() throws {
        let json = #"""
        {"vault":{"initialized":"yes","key_store":"keychain","restore_pending":true,
         "restore_check_error":"reading the lost key's record: permission denied","secrets_stored":4}}
        """#
        let status = try JSONDecoder().decode(CLIStatus.self, from: Data(json.utf8))
        XCTAssertEqual(status.vault?.restoreCheckError, "reading the lost key's record: permission denied")
        let plain = try JSONDecoder().decode(CLIStatus.self, from: Data(#"{"vault":{"secrets_stored":4}}"#.utf8))
        XCTAssertNil(plain.vault?.restoreCheckError)
    }

    /// With the error the row is its own state, carrying jit's words; the
    /// control is the same status without it, which keeps the restore.
    func testACheckErrorIsItsOwnRowState() {
        XCTAssertEqual(
            VaultKeyRow.state(vault(checkError: Self.checkError), bundledHelper: true, keyLost: false),
            .restoreUnchecked(Self.checkError)
        )
        XCTAssertEqual(VaultKeyRow.state(vault(), bundledHelper: true, keyLost: false), .restorePending)
        XCTAssertEqual(VaultKeyRow.state(vault(checkError: ""), bundledHelper: true, keyLost: false), .restorePending)
    }

    /// Never Restore from Recovery File while jit says it could not check:
    /// not from status alone, not from doctor's finding without a fix, and
    /// not from an older report's import either. Controls: the same status
    /// without the error keeps today's import, and so does jit's import fix.
    func testNoRestoreIsOfferedThatJitDidNotName() throws {
        XCTAssertNil(VaultKeyRow.restore(vault(checkError: Self.checkError), report: nil))
        XCTAssertNil(try VaultKeyRow.restore(vault(checkError: Self.checkError), report: report(Self.uncheckedReport)))
        XCTAssertNil(
            try VaultKeyRow.restore(vault(checkError: Self.checkError), report: report(DoctorVaultKeyTests.restoreReport))
        )

        XCTAssertEqual(VaultKeyRow.restore(vault(), report: nil)?.action, DoctorAdvice.importRecoveryFile)
        XCTAssertEqual(
            try VaultKeyRow.restore(vault(), report: report(DoctorVaultKeyTests.restoreReport))?.action.argv,
            DoctorAdvice.importRecoveryFile.argv
        )
        XCTAssertNil(VaultKeyRow.restore(vault(restore: nil), report: nil))
    }

    /// The fix jit names is the one offered, and nothing beside it: its
    /// Finish Restore, in the terminal, where jit lists what may not open
    /// before its own y/N. Not mistaken for the import it is not.
    func testJitsFinishIsTheOneOffered() throws {
        let restore = try XCTUnwrap(VaultKeyRow.restore(vault(checkError: Self.checkError), report: report(Self.finishReport)))
        XCTAssertEqual(restore.action.title, "Finish Restore")
        XCTAssertEqual(restore.action.command, "jit vault import --finish")
        XCTAssertNil(restore.action.argv)
        XCTAssertFalse(restore.action.destructive)
        XCTAssertNotEqual(restore.action.title, DoctorAdvice.importRecoveryFile.title)
    }

    /// The Doctor card says jit couldn't check, in jit's words, with no
    /// button (Check Again is the window's own). Control: the checked
    /// finding keeps its Restore from Recovery File.
    func testTheUncheckedCardOffersNothing() throws {
        let board = try DoctorBoard.make(report(Self.uncheckedReport))
        let card = try XCTUnwrap(board.cards.first)
        XCTAssertEqual(board.cards.count, 1)
        XCTAssertEqual(card.tier, .broken)
        XCTAssertEqual(card.title, "Can't tell whether secrets still need restoring")
        XCTAssertEqual(
            card.reason,
            "Couldn't check the vault for secrets sealed to a lost key: reading the lost key's record: permission denied"
        )
        XCTAssertNil(card.primary)
        XCTAssertTrue(card.menu.isEmpty)

        let checked = try XCTUnwrap(try DoctorBoard.make(report(DoctorVaultKeyTests.restoreReport)).cards.first)
        XCTAssertEqual(checked.primary?.title, "Restore from Recovery File…")
    }

    func testTheUncheckedCardOffersJitsFinish() throws {
        let card = try XCTUnwrap(try DoctorBoard.make(report(Self.finishReport)).cards.first)
        XCTAssertEqual(card.title, "Can't tell whether secrets still need restoring")
        let button = try XCTUnwrap(card.primary)
        XCTAssertEqual(button.title, "Finish Restore")
        XCTAssertEqual(button.steps.map(\.command), ["jit vault import --finish"])
        XCTAssertTrue(card.menu.isEmpty)
    }

    // MARK: - A change of the vault key this jit doesn't understand

    /// profilecheck.go's rekey_unknown, as doctorsections.go writes it: a
    /// detail and a step in words, and no command.
    static let unknownReport = #"""
    {"schema_version":2,"ok":false,"problems":[{"kind":"rekey_unknown","detail":"a move of the vault key this version \#
    of jit doesn't understand (to \"tpm\") is unfinished, so every command that changes the vault will refuse until it \#
    finishes.","action":"update jit, then finish it with the newer jit"}],"warnings":[]}
    """#

    static let unreadableReport = #"""
    {"schema_version":2,"ok":false,"problems":[{"kind":"rekey_unknown","detail":"jit can't read the file that marks an \#
    unfinished change of the vault key (permission denied), so every command that changes the vault will refuse until it \#
    can.","action":"make that file readable again, then check again"}],"warnings":[]}
    """#

    static let unknownWords = "A move of the vault key this version of jit doesn't understand (to \"tpm\") is unfinished, "
        + "so every command that changes the vault will refuse until it finishes. Update jit, then finish it with the newer jit."

    func testTheUnknownChangeCardIsTitledAndOffersNothing() throws {
        let card = try XCTUnwrap(try DoctorBoard.make(report(Self.unknownReport)).cards.first)
        XCTAssertEqual(card.tier, .broken)
        XCTAssertEqual(card.title, "An unfinished vault key change this JitPass doesn't understand")
        XCTAssertEqual(card.reason, Self.unknownWords)
        XCTAssertNil(card.primary)
        XCTAssertTrue(card.menu.isEmpty)

        let unreadable = try XCTUnwrap(try DoctorBoard.make(report(Self.unreadableReport)).cards.first)
        XCTAssertEqual(
            unreadable.reason,
            "jit can't read the file that marks an unfinished change of the vault key (permission denied), so every "
                + "command that changes the vault will refuse until it can. Make that file readable again, then check again."
        )
    }

    /// While doctor reports it, the row is blocked in jit's words, whatever
    /// status says, and Doctor offers no move. Controls: the same status
    /// with a clean report is the ordinary keychain row, and offered.
    func testTheRowIsBlockedWhileDoctorReportsIt() throws {
        let words = try XCTUnwrap(VaultKeyRow.changeUnknown(report(Self.unknownReport)))
        XCTAssertEqual(words, Self.unknownWords)
        let keychain = vault(restore: nil)
        XCTAssertEqual(
            VaultKeyRow.state(keychain, bundledHelper: true, keyLost: false, changeUnknown: words), .changeUnknown(words)
        )
        XCTAssertEqual(
            VaultKeyRow.state(vault("secure-enclave", restore: nil), bundledHelper: true, keyLost: false, changeUnknown: words),
            .changeUnknown(words)
        )
        XCTAssertFalse(VaultKeyRow.offersMove(keychain, bundledHelper: true, dismissed: false, changeUnknown: words))

        let clean = try report(#"{"schema_version":2,"ok":true,"problems":[],"warnings":[]}"#)
        XCTAssertNil(VaultKeyRow.changeUnknown(clean))
        XCTAssertEqual(VaultKeyRow.state(keychain, bundledHelper: true, keyLost: false), .keychain)
        XCTAssertTrue(VaultKeyRow.offersMove(keychain, bundledHelper: true, dismissed: false))
    }

    /// jit refuses every move while the change is unfinished, so the
    /// failure row never offers Try Again (it would be refused again): it
    /// offers Check Again. The three refusals are runVaultMove's own.
    /// Control: an ordinary refusal keeps Try Again.
    func testAMoveRefusedByTheUnknownChangeOffersNoTryAgain() {
        let refusals = [
            "jit vault rekey: a move of the vault key this version of jit doesn't understand (to \"tpm\") is unfinished, "
                + "so every command that changes the vault will refuse until it finishes. To fix: update jit, then finish "
                + "it with the newer jit.",
            "jit vault rekey: a change of the vault key this version of jit doesn't understand is unfinished, so every "
                + "command that changes the vault will refuse until it finishes. To fix: update jit, then finish it with "
                + "the newer jit.",
            "jit vault rekey: jit can't read the file that marks an unfinished change of the vault key (permission "
                + "denied), so every command that changes the vault will refuse until it can. To fix: make that file "
                + "readable again, then check again."
        ]
        for line in refusals {
            for now in [VaultKeyPlace.keychain, .secureEnclave] {
                let outcome = SettingsOutcome.vaultKeyFailed(to: .secureEnclave, now: now, line: line)
                XCTAssertFalse(outcome.offersRetry, line)
                XCTAssertTrue(outcome.offersCheck, line)
                XCTAssertEqual(outcome.verbatim, line)
                XCTAssertTrue(outcome.detail.hasPrefix("An unfinished vault key change this JitPass doesn't understand"))
            }
        }
        let ordinary = SettingsOutcome.vaultKeyFailed(
            to: .secureEnclave, now: .keychain, line: "jit vault rekey: sealing the key to the Secure Enclave: interrupted"
        )
        XCTAssertTrue(ordinary.offersRetry)
        XCTAssertFalse(ordinary.offersCheck)
    }
}
