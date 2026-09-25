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

    private func doctor(_ kinds: [String], ignored: [String] = []) throws -> DoctorReport {
        let item = { (kind: String) in #"{"kind":"\#(kind)","detail":"x"}"# }
        let json = #"{"schema_version":2,"ok":false,"problems":[\#(kinds.map(item).joined(separator: ","))],"#
            + #""warnings":[],"ignored":[\#(ignored.map(item).joined(separator: ","))]}"#
        return try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
    }

    /// Try Again goes the way the failed move went, never the opposite way
    /// jit would refuse ("a move to secure-enclave is unfinished").
    func testTryAgainRetriesTheFailedMovesTarget() throws {
        let marker = try doctor(["rekey"])
        // Stopped halfway: the key reached the enclave, the keychain copy
        // was not deleted. The row reads "in the Secure Enclave".
        XCTAssertEqual(
            VaultKeyMove.retry(pending: .secureEnclave, now: .secureEnclave, report: marker),
            VaultKeyRetry(target: .secureEnclave, finishes: true)
        )
        // Stopped halfway on the way back.
        XCTAssertEqual(
            VaultKeyMove.retry(pending: .keychain, now: .keychain, report: nil),
            VaultKeyRetry(target: .keychain, finishes: true)
        )
        // Crashed before the key moved: the marker is there, the key is not.
        XCTAssertEqual(
            VaultKeyMove.retry(pending: .secureEnclave, now: .keychain, report: marker),
            VaultKeyRetry(target: .secureEnclave, finishes: true)
        )
        // Refused before anything changed (jit removed its marker): ask again.
        XCTAssertEqual(
            try VaultKeyMove.retry(pending: .secureEnclave, now: .keychain, report: doctor([])),
            VaultKeyRetry(target: .secureEnclave, finishes: false)
        )
        // No record of the app's own move: the other place, asked again.
        XCTAssertEqual(
            VaultKeyMove.retry(pending: nil, now: .secureEnclave, report: marker),
            VaultKeyRetry(target: .keychain, finishes: false)
        )
        XCTAssertNil(VaultKeyMove.retry(pending: nil, now: nil, report: nil))
    }

    /// jit reports its marker only as doctor's `rekey` finding: the row
    /// offers to finish the app's own move while it is there, and the
    /// app's record goes once doctor answers without it.
    func testTheMarkerFromDoctorDecidesTheUnfinishedRow() throws {
        XCTAssertEqual(try VaultKeyMove.unfinished(pending: .secureEnclave, report: doctor(["rekey"])), .secureEnclave)
        XCTAssertEqual(try VaultKeyMove.unfinished(pending: .keychain, report: doctor([], ignored: ["rekey"])), .keychain)
        XCTAssertNil(try VaultKeyMove.unfinished(pending: nil, report: doctor(["rekey"])))
        XCTAssertNil(try VaultKeyMove.unfinished(pending: .keychain, report: doctor([])))
        XCTAssertNil(VaultKeyMove.unfinished(pending: .keychain, report: nil))
        XCTAssertTrue(try VaultKeyMove.settled(doctor([])))
        XCTAssertFalse(try VaultKeyMove.settled(doctor(["rekey"])))
        XCTAssertFalse(VaultKeyMove.settled(nil))
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
