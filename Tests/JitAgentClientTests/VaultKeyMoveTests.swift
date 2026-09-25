// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// Moving the vault key: which sheet button takes Return, where Try Again
/// goes after a move that failed or stopped halfway, and what the row and
/// the banner say afterwards.
final class VaultKeyMoveTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - The sheet's Return key

    private var older: RecoveryFile {
        .older(at: now)
    }

    /// Exactly one button takes Return, and it is never Move Key while a
    /// failed save's row is showing, even when an earlier file counts.
    func testOneDefaultAndNeverMoveKeyAfterAFailedSave() {
        let current = RecoveryFile.current(at: now)
        XCTAssertEqual(VaultKeySheetDefault.pick(current, saving: false, saveFailed: true), .saveRecoveryFile)
        XCTAssertEqual(VaultKeySheetDefault.pick(current, saving: false, saveFailed: false), .moveKey)
        XCTAssertEqual(VaultKeySheetDefault.pick(.none, saving: false, saveFailed: false), .saveRecoveryFile)
        XCTAssertEqual(VaultKeySheetDefault.pick(older, saving: false, saveFailed: false), .saveRecoveryFile)
        XCTAssertEqual(VaultKeySheetDefault.pick(current, saving: true, saveFailed: false), .none)
        XCTAssertTrue(VaultKeySheetDefault.moveEnabled(current, saving: false))
        XCTAssertFalse(VaultKeySheetDefault.moveEnabled(current, saving: true))
        XCTAssertFalse(VaultKeySheetDefault.moveEnabled(older, saving: false))
    }

    // MARK: - An unfinished move

    /// Finish Move and Try Again: jit's `move_unfinished` names the move to
    /// finish, whichever way the app last tried, and it runs as it is. With
    /// no move unfinished, the move that failed is asked again, never the
    /// opposite one; the other place only with no record of the attempt.
    func testTryAgainFinishesWhatJitSaysIsUnfinished() {
        // Crashed after the key reached the enclave: jit names the target.
        XCTAssertEqual(
            VaultKeyMove.retry(unfinished: .secureEnclave, attempted: .secureEnclave, now: .secureEnclave),
            VaultKeyRetry(target: .secureEnclave, finishes: true)
        )
        // Crashed before the key moved, after a relaunch (nothing attempted
        // in this run of the app): still jit's target.
        XCTAssertEqual(
            VaultKeyMove.retry(unfinished: .secureEnclave, attempted: nil, now: .keychain),
            VaultKeyRetry(target: .secureEnclave, finishes: true)
        )
        // A move started in a terminal, the other way from the app's last.
        XCTAssertEqual(
            VaultKeyMove.retry(unfinished: .keychain, attempted: .secureEnclave, now: .secureEnclave),
            VaultKeyRetry(target: .keychain, finishes: true)
        )
        // Refused before anything changed: ask again.
        XCTAssertEqual(
            VaultKeyMove.retry(unfinished: nil, attempted: .secureEnclave, now: .keychain),
            VaultKeyRetry(target: .secureEnclave, finishes: false)
        )
        // Failed, but the key is at the target and jit has no marker.
        XCTAssertEqual(
            VaultKeyMove.retry(unfinished: nil, attempted: .keychain, now: .keychain),
            VaultKeyRetry(target: .keychain, finishes: true)
        )
        XCTAssertEqual(
            VaultKeyMove.retry(unfinished: nil, attempted: nil, now: .secureEnclave),
            VaultKeyRetry(target: .keychain, finishes: false)
        )
        XCTAssertNil(VaultKeyMove.retry(unfinished: nil, attempted: nil, now: nil))
    }

    // MARK: - Outcomes

    func testTheBannerSaysWhatMoved() {
        let into = SettingsOutcome.vaultKeyMoved(to: .secureEnclave)
        XCTAssertTrue(into.ok)
        XCTAssertEqual(into.row, .vaultKey)
        XCTAssertEqual(into.title, "Moved the vault key into the Secure Enclave · every secret opens as before")
        XCTAssertEqual(SettingsOutcome.vaultKeyMoved(to: .keychain).title, "Moved the vault key back to your keychain")
    }

    /// The banner follows where jit says the key is after the run, not the
    /// exit code: jit exits 0 for "already in the Secure Enclave. Nothing
    /// to do." too.
    func testNoBannerWhenNothingMoved() {
        XCTAssertNil(SettingsOutcome.vaultKeyMoveEnded(
            to: .secureEnclave, before: .secureEnclave, now: .secureEnclave, finishing: false, failure: nil
        ))
        XCTAssertEqual(
            SettingsOutcome.vaultKeyMoveEnded(to: .secureEnclave, before: .keychain, now: .secureEnclave, finishing: false, failure: nil),
            .vaultKeyMoved(to: .secureEnclave)
        )
        // Finishing a half-done move: the key was already there by status,
        // and the move still ended now.
        XCTAssertEqual(
            SettingsOutcome.vaultKeyMoveEnded(
                to: .secureEnclave,
                before: .secureEnclave,
                now: .secureEnclave,
                finishing: true,
                failure: nil
            ),
            .vaultKeyMoved(to: .secureEnclave)
        )
        // No status afterwards: nothing claimed.
        XCTAssertNil(SettingsOutcome.vaultKeyMoveEnded(to: .keychain, before: .secureEnclave, now: nil, finishing: false, failure: nil))
        // A zero exit with the key somewhere else is not a move.
        let elsewhere = SettingsOutcome.vaultKeyMoveEnded(
            to: .keychain, before: .secureEnclave, now: .secureEnclave, finishing: false, failure: nil
        )
        XCTAssertEqual(elsewhere?.ok, false)
        XCTAssertEqual(elsewhere?.title, "Still in the Secure Enclave")
    }

    /// Frame F: where the key still is, what stopped it in the reader's
    /// words, jit's own line under it, and Try Again.
    func testACancelledTouchIDSaysNothingChanged() {
        let line = "jit vault rekey: local authentication failed: Canceled by user."
        let outcome = SettingsOutcome.vaultKeyFailed(to: .secureEnclave, now: .keychain, line: line)
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.row, .vaultKey)
        XCTAssertEqual(outcome.title, "Still in your login keychain")
        XCTAssertEqual(outcome.detail, "Touch ID was cancelled, so nothing changed.")
        XCTAssertEqual(outcome.verbatim, line)
        XCTAssertTrue(outcome.offersRetry)
        XCTAssertFalse(outcome.offersStart)
        XCTAssertEqual(
            SettingsOutcome.vaultKeyMoveEnded(to: .secureEnclave, before: .keychain, now: .keychain, finishing: false, failure: line),
            outcome
        )
    }

    func testTheOtherRefusalsInTheirOwnSentence() {
        let outside = SettingsOutcome.vaultKeyFailed(
            to: .secureEnclave, now: .keychain,
            line: "jit vault rekey: sealing the key to the Secure Enclave: this copy of jit can't use the Secure Enclave; "
                + "use the jit inside JitPass.app (nothing changed)"
        )
        XCTAssertEqual(outside.detail, "This copy of jit can't reach the Secure Enclave, so nothing changed.")
        let stale = "jit vault rekey: your recovery file is older than your newest secret; save a new one with `jit vault export` first"
        XCTAssertEqual(
            SettingsOutcome.vaultKeyFailed(to: .secureEnclave, now: .keychain, line: stale).detail,
            "Secrets were added or changed after the recovery file was saved, so nothing changed."
        )
        let back = SettingsOutcome.vaultKeyFailed(to: .keychain, now: .secureEnclave, line: "jit vault rekey: the Mac is locked")
        XCTAssertEqual(back.title, "Still in the Secure Enclave")
        XCTAssertEqual(back.detail, "jit did not move it. Its own words are below.")
        // A line that happens to say "not running" is still the move's
        // failure: its button is Try Again, never Start Service.
        let down = SettingsOutcome.vaultKeyFailed(to: .keychain, now: .secureEnclave, line: "jit: the service is not running")
        XCTAssertFalse(down.offersStart)
        XCTAssertTrue(down.offersRetry)
    }

    /// A failure after which jit could not be asked where the key is:
    /// nothing is claimed ("Try again to finish it" was a guess), and the
    /// row's button asks again rather than moving.
    func testAnUnknownResultOffersCheckAgain() {
        let line = "jit vault rekey: the Mac is locked"
        let outcome = SettingsOutcome.vaultKeyFailed(to: .secureEnclave, now: nil, line: line)
        XCTAssertFalse(outcome.ok)
        XCTAssertEqual(outcome.title, "The move's result is unknown")
        XCTAssertEqual(outcome.detail, "jit could not say where the key is now. Check again to find out. jit's own words are below.")
        XCTAssertFalse(outcome.detail.lowercased().contains("try again"))
        XCTAssertEqual(outcome.verbatim, line)
        XCTAssertTrue(outcome.offersCheck)
        XCTAssertFalse(outcome.offersRetry)
        XCTAssertEqual(
            SettingsOutcome.vaultKeyMoveEnded(to: .secureEnclave, before: .keychain, now: nil, finishing: false, failure: line),
            outcome
        )
        XCTAssertEqual(
            SettingsOutcome.vaultKeyFailed(to: .keychain, now: nil, line: "").detail,
            "jit could not say where the key is now. Check again to find out."
        )
        // A known place keeps Try Again.
        XCTAssertFalse(SettingsOutcome.vaultKeyFailed(to: .secureEnclave, now: .keychain, line: line).offersCheck)
    }

    /// A failure after the key reached its new place ("re-run to finish")
    /// must not claim nothing changed.
    func testAHalfFinishedMoveSaysSo() {
        let line = "jit vault rekey: the key is in the Secure Enclave, but its old keychain copy could not be deleted: "
            + "denied (re-run to finish)"
        let outcome = SettingsOutcome.vaultKeyFailed(to: .secureEnclave, now: .secureEnclave, line: line)
        XCTAssertEqual(outcome.title, "The move did not finish")
        XCTAssertFalse(outcome.detail.contains("nothing changed"))
        XCTAssertTrue(outcome.offersRetry)
    }
}
