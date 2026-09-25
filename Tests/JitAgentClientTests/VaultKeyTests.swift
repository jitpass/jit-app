// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

@testable import JitAgentClient
import XCTest

/// The Vault key row (Settings › Protection) and the move sheet's gate:
/// where `jit status` says the key is, whether this app's jit can move it,
/// and whether the recovery file is good enough to offer Move Key.
final class VaultKeyTests: XCTestCase {
    // MARK: - Status

    /// `jit status --format json`'s vault section on a real Mac (jit
    /// 2.2.8-dev, 2026-09-25): a keychain vault with no recovery file.
    func testDecodesWhereTheKeyIsFromARealStatus() throws {
        let json = #"""
        {"vault":{"initialized":"yes","key_store":"keychain","secrets_stored":26,"backups_stored":523,
         "stale_backups":7,"export_recorded":false}}
        """#
        let vault = try XCTUnwrap(JSONDecoder().decode(CLIStatus.self, from: Data(json.utf8)).vault)
        XCTAssertEqual(vault.keyStore, "keychain")
        XCTAssertEqual(vault.secretsStored, 26)
        XCTAssertEqual(vault.exportRecorded, false)
        XCTAssertNil(vault.exportUnixTime)
        XCTAssertNil(vault.exportStale)
    }

    /// The recorded export, as status.go writes it: time, and stale only
    /// when a secret was written since.
    func testDecodesTheRecoveryFileFields() throws {
        let json = #"""
        {"vault":{"initialized":"yes","key_store":"secure-enclave","secrets_stored":67,"backups_stored":0,
         "export_recorded":true,"export_unix_time":1790000000,"export_stale":true}}
        """#
        let vault = try XCTUnwrap(JSONDecoder().decode(CLIStatus.self, from: Data(json.utf8)).vault)
        XCTAssertEqual(vault.keyStore, "secure-enclave")
        XCTAssertEqual(vault.exportRecorded, true)
        XCTAssertEqual(vault.exportUnixTime, 1_790_000_000)
        XCTAssertEqual(vault.exportStale, true)
    }

    /// A jit before the move says nothing about where the key is.
    func testAnOlderJitLeavesTheNewFieldsNil() throws {
        let json = #"{"vault":{"initialized":"yes","secrets_stored":3}}"#
        let vault = try XCTUnwrap(JSONDecoder().decode(CLIStatus.self, from: Data(json.utf8)).vault)
        XCTAssertNil(vault.keyStore)
        XCTAssertNil(vault.exportRecorded)
    }

    // MARK: - The row

    private func vault(_ store: String?, initialized: String = "yes", secrets: Int = 5) -> CLIVaultStatus {
        CLIVaultStatus(secretsStored: secrets, initialized: initialized, keyStore: store)
    }

    func testTheRowSaysWhereTheKeyIs() {
        XCTAssertEqual(VaultKeyRow.state(vault("keychain"), bundledHelper: true, keyLost: false), .keychain)
        XCTAssertEqual(VaultKeyRow.state(vault("secure-enclave"), bundledHelper: true, keyLost: false), .secureEnclave)
    }

    /// Doctor's lost key turns the enclave row into the bad state; it says
    /// nothing about a keychain vault, whose missing key is another finding.
    func testALostEnclaveKeyIsItsOwnState() {
        XCTAssertEqual(VaultKeyRow.state(vault("secure-enclave"), bundledHelper: true, keyLost: true), .lost)
        XCTAssertEqual(VaultKeyRow.state(vault("keychain"), bundledHelper: true, keyLost: true), .keychain)
    }

    /// Only the app's own helper can reach the enclave: a Homebrew or dev
    /// jit gets no row at all, whichever place the key is in.
    func testNoRowForAJitOutsideTheApp() {
        XCTAssertNil(VaultKeyRow.state(vault("keychain"), bundledHelper: false, keyLost: false))
        XCTAssertNil(VaultKeyRow.state(vault("secure-enclave"), bundledHelper: false, keyLost: false))
    }

    /// No row where there is nothing true to offer: no status yet, a jit
    /// too old to say (or to move), a word this app doesn't know, no vault.
    func testNoRowWithoutAKnownPlaceOrAVault() {
        XCTAssertNil(VaultKeyRow.state(nil, bundledHelper: true, keyLost: false))
        XCTAssertNil(VaultKeyRow.state(vault(nil), bundledHelper: true, keyLost: false))
        XCTAssertNil(VaultKeyRow.state(vault("tpm"), bundledHelper: true, keyLost: false))
        XCTAssertNil(VaultKeyRow.state(vault("keychain", initialized: "no"), bundledHelper: true, keyLost: false))
        XCTAssertNil(VaultKeyRow.state(vault("keychain", initialized: "unknown"), bundledHelper: true, keyLost: false))
    }

    func testTheMoveCommandsAreJitsOwn() {
        XCTAssertEqual(VaultKeyPlace.secureEnclave.moveArguments, ["vault", "rekey", "--wrapper", "secure-enclave", "--yes"])
        XCTAssertEqual(VaultKeyPlace.keychain.moveArguments, ["vault", "rekey", "--wrapper", "keychain", "--yes"])
    }

    // MARK: - Which jit

    /// The helper's own path and the compat symlink to it count; a copy
    /// elsewhere, even a symlink to another jit, does not.
    func testOnlyTheBundledHelperCounts() throws {
        let fm = FileManager.default
        let app = fm.temporaryDirectory.appendingPathComponent("VaultKeyTests-\(UUID().uuidString)/JitPass.app")
        defer { try? fm.removeItem(at: app.deletingLastPathComponent()) }
        let helper = app.appendingPathComponent(CommandLineTool.bundledRelativePath)
        try fm.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: helper)
        let compat = app.appendingPathComponent("Contents/MacOS/jit")
        try fm.createDirectory(at: compat.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: compat.path, withDestinationPath: "../Helpers/JitPassAgent.app/Contents/MacOS/jit")
        let brew = app.deletingLastPathComponent().appendingPathComponent("bin/jit")
        try fm.createDirectory(at: brew.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: brew)

        XCTAssertTrue(VaultKeyRow.isBundledHelper(helper.path, bundleURL: app))
        XCTAssertTrue(VaultKeyRow.isBundledHelper(compat.path, bundleURL: app))
        XCTAssertFalse(VaultKeyRow.isBundledHelper(brew.path, bundleURL: app))
        XCTAssertFalse(VaultKeyRow.isBundledHelper("/opt/homebrew/bin/jit", bundleURL: app))
        XCTAssertFalse(VaultKeyRow.isBundledHelper(nil, bundleURL: app))
    }

    // MARK: - Doctor's lost key

    /// jit's `vault_key` finding for a lost enclave key carries `jit vault
    /// init` before the import (doctorsections.go); a keychain key that is
    /// gone carries the import alone.
    static let lostReport = #"""
    {"schema_version":2,"ok":false,"problems":[{"kind":"vault_key","detail":"the vault holds 67 secrets but this Mac's \#
    master key is not in this Mac's Secure Enclave, so none of them can be decrypted. Every envelope is structurally \#
    intact; only the key is gone.","action":"`jit vault init`, then `jit vault import <file>` from a `jit vault export` \#
    backup","fixes":[{"command":"jit vault init","argv":["vault","init"],"destructive":true,"presence":false},{"command":\#
    "jit vault import <file>","argv":["vault","import","<file>"],"destructive":true,"presence":true,"needs":"<file>"}]}],\#
    "warnings":[]}
    """#

    static let goneFromKeychainReport = #"""
    {"schema_version":2,"ok":false,"problems":[{"kind":"vault_key","detail":"the vault holds 67 secrets but this Mac's \#
    master key is missing from the keychain, so none of them can be decrypted.","action":"`jit vault import <file>` from \#
    a `jit vault export` backup","fixes":[{"command":"jit vault import <file>","argv":["vault","import","<file>"],\#
    "destructive":true,"presence":true,"needs":"<file>"}]}],"warnings":[]}
    """#

    func testDoctorSaysWhenTheEnclaveKeyIsLost() throws {
        let lost = try JSONDecoder().decode(DoctorReport.self, from: Data(Self.lostReport.utf8))
        let gone = try JSONDecoder().decode(DoctorReport.self, from: Data(Self.goneFromKeychainReport.utf8))
        XCTAssertTrue(VaultKeyRow.keyLost(lost))
        XCTAssertFalse(VaultKeyRow.keyLost(gone))
        XCTAssertFalse(VaultKeyRow.keyLost(nil))
    }

    /// Doctor's offer: a keychain vault with secrets, a jit that can move
    /// it, not dismissed.
    func testTheOfferIsForAMovableKeychainVaultOnly() {
        XCTAssertTrue(VaultKeyRow.offersMove(vault("keychain"), bundledHelper: true, dismissed: false))
        XCTAssertFalse(VaultKeyRow.offersMove(vault("keychain"), bundledHelper: true, dismissed: true))
        XCTAssertFalse(VaultKeyRow.offersMove(vault("keychain"), bundledHelper: false, dismissed: false))
        XCTAssertFalse(VaultKeyRow.offersMove(vault("secure-enclave"), bundledHelper: true, dismissed: false))
        XCTAssertFalse(VaultKeyRow.offersMove(vault("keychain", secrets: 0), bundledHelper: true, dismissed: false))
    }

    // MARK: - The recovery file

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func exported(daysAgo: Double, secrets: Int = 67, stale: Bool = false) -> CLIVaultStatus {
        CLIVaultStatus(
            secretsStored: secrets, initialized: "yes", keyStore: "keychain", exportRecorded: true,
            exportUnixTime: Int64(now.timeIntervalSince1970 - daysAgo * 86400), exportStale: stale
        )
    }

    func testNoRecoveryFile() {
        let none = CLIVaultStatus(secretsStored: 67, initialized: "yes", keyStore: "keychain", exportRecorded: false)
        XCTAssertEqual(RecoveryFile.check(none, recorded: nil, now: now), .none)
        XCTAssertEqual(RecoveryFile.check(nil, recorded: nil, now: now), .none)
        XCTAssertFalse(RecoveryFile.check(none, recorded: nil, now: now).ready)
    }

    /// The decision: a file counts when it holds the vault's current count.
    func testAFileHoldingTheVaultsCountIsCurrentWhateverItsAge() {
        let vault = exported(daysAgo: 90)
        let recorded = RecordedExport(unixTime: vault.exportUnixTime ?? 0, secrets: 67)
        let file = RecoveryFile.check(vault, recorded: recorded, now: now)
        XCTAssertEqual(file, .current(at: Date(timeIntervalSince1970: TimeInterval(recorded.unixTime)), secrets: 67))
        XCTAssertTrue(file.ready)
    }

    func testAFileWithAnotherCountIsBehind() {
        let vault = exported(daysAgo: 1, secrets: 70)
        let recorded = RecordedExport(unixTime: vault.exportUnixTime ?? 0, secrets: 67)
        let file = RecoveryFile.check(vault, recorded: recorded, now: now)
        XCTAssertEqual(file, .behind(at: Date(timeIntervalSince1970: TimeInterval(recorded.unixTime)), secrets: 67, vault: 70))
        XCTAssertFalse(file.ready)
        XCTAssertEqual(RecoveryFile.newSecrets(vault, recorded: recorded), 3)
    }

    /// Without a count (a file saved in a terminal, or the app's record is
    /// of an older export), 30 days is the fallback.
    func testWithoutACountThirtyDaysDecides() {
        XCTAssertTrue(RecoveryFile.check(exported(daysAgo: 29), recorded: nil, now: now).ready)
        let old = exported(daysAgo: 31)
        XCTAssertEqual(
            RecoveryFile.check(old, recorded: nil, now: now),
            .expired(at: Date(timeIntervalSince1970: TimeInterval(old.exportUnixTime ?? 0)))
        )
        let earlier = RecordedExport(unixTime: (old.exportUnixTime ?? 0) - 60, secrets: 60)
        XCTAssertFalse(RecoveryFile.check(old, recorded: earlier, now: now).ready)
        XCTAssertNil(RecoveryFile.newSecrets(old, recorded: earlier))
    }

    /// jit refuses the move for a file older than the newest secret, so the
    /// sheet never offers it, even when the counts match.
    func testAStaleFileNeverCounts() {
        let vault = exported(daysAgo: 1, stale: true)
        let recorded = RecordedExport(unixTime: vault.exportUnixTime ?? 0, secrets: 67)
        XCTAssertEqual(
            RecoveryFile.check(vault, recorded: recorded, now: now),
            .older(at: Date(timeIntervalSince1970: TimeInterval(recorded.unixTime)))
        )
        XCTAssertFalse(RecoveryFile.check(vault, recorded: nil, now: now).ready)
    }

    /// jit's closing line, from `jit vault export` (countWord in vault.go).
    func testReadsTheCountFromJitsExportLine() {
        XCTAssertEqual(RecordedExport.count(in: "Exported 67 secrets to /Users/me/r.export."), 67)
        XCTAssertEqual(RecordedExport.count(in: "Touch ID…\nExported 1 secret to /tmp/x.export."), 1)
        XCTAssertNil(RecordedExport.count(in: "jit vault export: canceled"))
        XCTAssertNil(RecordedExport.count(in: ""))
    }

    // MARK: - Outcomes

    func testTheBannerSaysWhatMoved() {
        let into = SettingsOutcome.vaultKeyMoved(to: .secureEnclave)
        XCTAssertTrue(into.ok)
        XCTAssertEqual(into.row, .vaultKey)
        XCTAssertEqual(into.title, "Moved the vault key into the Secure Enclave · every secret opens as before")
        XCTAssertEqual(SettingsOutcome.vaultKeyMoved(to: .keychain).title, "Moved the vault key back to your keychain")
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
            SettingsOutcome.vaultKeyFailed(to: .secureEnclave, now: .keychain, line: stale, newSecrets: 3).detail,
            "The recovery file is from before 3 new secrets, so nothing changed."
        )
        XCTAssertEqual(
            SettingsOutcome.vaultKeyFailed(to: .secureEnclave, now: .keychain, line: stale).detail,
            "The recovery file is older than your newest secret, so nothing changed."
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
