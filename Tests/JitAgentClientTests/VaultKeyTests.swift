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

    /// Never green before doctor has said this Mac's enclave has the key:
    /// "checking" until the report lands. A keychain vault needs no answer.
    func testAnEnclaveKeyIsCheckingUntilDoctorAnswers() {
        XCTAssertEqual(VaultKeyRow.state(vault("secure-enclave"), bundledHelper: true, keyLost: nil), .checking)
        XCTAssertEqual(VaultKeyRow.state(vault("keychain"), bundledHelper: true, keyLost: nil), .keychain)
    }

    /// A move the app started, while jit's marker is there, is its own
    /// state; a lost key still comes first, since nothing opens.
    func testAnUnfinishedMoveIsItsOwnState() {
        XCTAssertEqual(
            VaultKeyRow.state(vault("keychain"), bundledHelper: true, keyLost: false, unfinished: .keychain),
            .unfinished(.keychain)
        )
        XCTAssertEqual(
            VaultKeyRow.state(vault("secure-enclave"), bundledHelper: true, keyLost: true, unfinished: .keychain), .lost
        )
    }

    /// jit reports the recovery file only for a vault with something in
    /// it, so an empty one is never offered the move; backups count, as
    /// they do in status.go.
    func testAnEmptyVaultIsNotOfferedTheMove() {
        XCTAssertFalse(VaultKeyRow.canMoveIn(CLIVaultStatus(secretsStored: 0, keyStore: "keychain", backupsStored: 0)))
        XCTAssertFalse(VaultKeyRow.canMoveIn(CLIVaultStatus(secretsStored: 0, keyStore: "keychain")))
        XCTAssertTrue(VaultKeyRow.canMoveIn(CLIVaultStatus(secretsStored: 0, keyStore: "keychain", backupsStored: 2)))
        XCTAssertTrue(VaultKeyRow.canMoveIn(CLIVaultStatus(secretsStored: 1, keyStore: "keychain")))
        XCTAssertFalse(VaultKeyRow.canMoveIn(nil))
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

    /// A FileManager that says which paths are executable, so the
    /// Homebrew fallback is tested without touching /opt/homebrew.
    private final class FakeFiles: FileManager, @unchecked Sendable {
        var executables: Set<String> = []
        override func isExecutableFile(atPath path: String) -> Bool {
            executables.contains(path)
        }
    }

    /// The path the app runs, and the bundled check read from the same
    /// place: the helper when it is there, else Homebrew's jit, which is
    /// never the helper.
    func testTheAppRunsItsHelperFirstAndFallsBackToHomebrew() {
        let app = URL(fileURLWithPath: "/Applications/JitPass.app")
        let helper = app.appendingPathComponent(CommandLineTool.bundledRelativePath).path
        let files = FakeFiles()
        files.executables = [helper, "/opt/homebrew/bin/jit", "/usr/local/bin/jit"]
        XCTAssertEqual(CommandLineTool.runnableJit(in: app, fileManager: files), helper)
        XCTAssertTrue(CommandLineTool.runsBundledJit(in: app, fileManager: files))

        files.executables = ["/opt/homebrew/bin/jit", "/usr/local/bin/jit"]
        XCTAssertEqual(CommandLineTool.runnableJit(in: app, fileManager: files), "/opt/homebrew/bin/jit")
        XCTAssertFalse(CommandLineTool.runsBundledJit(in: app, fileManager: files))

        files.executables = ["/usr/local/bin/jit"]
        XCTAssertEqual(CommandLineTool.runnableJit(in: app, fileManager: files), "/usr/local/bin/jit")
        files.executables = []
        XCTAssertNil(CommandLineTool.runnableJit(in: app, fileManager: files))
        XCTAssertFalse(CommandLineTool.runsBundledJit(in: app, fileManager: files))
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
        XCTAssertEqual(VaultKeyRow.keyLost(lost), true)
        XCTAssertEqual(VaultKeyRow.keyLost(gone), false)
        XCTAssertNil(VaultKeyRow.keyLost(nil))
    }

    /// Ignoring the finding opens nothing: the row stays lost, never green.
    func testAnIgnoredLostKeyIsStillLost() throws {
        var report = try JSONDecoder().decode(DoctorReport.self, from: Data(Self.lostReport.utf8))
        report.ignored = report.problems
        report.problems = []
        XCTAssertEqual(VaultKeyRow.keyLost(report), true)
        XCTAssertEqual(
            VaultKeyRow.state(vault("secure-enclave"), bundledHelper: true, keyLost: VaultKeyRow.keyLost(report)), .lost
        )
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
        XCTAssertEqual(RecoveryFile.check(none), .none)
        XCTAssertEqual(RecoveryFile.check(nil), .none)
        XCTAssertFalse(RecoveryFile.check(none).ready)
    }

    /// The gate is jit's rule and nothing else (recoveryFileCurrent): a
    /// recorded file no secret is newer than counts, whatever its age and
    /// however many entries jit's export line counted (it counts backups,
    /// which status does not, so the numbers were never comparable).
    func testAFileNoSecretIsNewerThanCountsWhateverItsAge() {
        let vault = exported(daysAgo: 90)
        let file = RecoveryFile.check(vault)
        XCTAssertEqual(file, .current(at: Date(timeIntervalSince1970: TimeInterval(vault.exportUnixTime ?? 0))))
        XCTAssertTrue(file.ready)
    }

    /// jit refuses the move for a file older than the newest secret.
    func testAStaleFileNeverCounts() {
        let vault = exported(daysAgo: 1, stale: true)
        XCTAssertEqual(RecoveryFile.check(vault), .older(at: Date(timeIntervalSince1970: TimeInterval(vault.exportUnixTime ?? 0))))
        XCTAssertFalse(RecoveryFile.check(vault).ready)
    }
}
