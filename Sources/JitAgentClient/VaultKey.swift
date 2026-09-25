// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Where the vault key is kept, and moving it (the Secure Enclave plan,
/// step A4; the mockup is "Vault key in the Secure Enclave"). The move is
/// jit's own `jit vault rekey --wrapper …`: the app decides only whether
/// to show the row, and its Move Key follows jit's own recovery file rule.
public enum VaultKeyPlace: String, Sendable, Equatable {
    case keychain
    case secureEnclave = "secure-enclave"

    /// `jit vault rekey --wrapper <place> --yes`. The flag is hidden in jit
    /// until this row ships; --yes because the app's own sheet or alert
    /// has asked jit's y/N already.
    public var moveArguments: [String] {
        ["vault", "rekey", "--wrapper", rawValue, "--yes"]
    }
}

/// What the Protection card's Vault key row shows.
public enum VaultKeyRow: Equatable, Sendable {
    /// In the login keychain: Move to Secure Enclave…
    case keychain
    /// In the Secure Enclave, and this Mac's enclave has it: a green dot,
    /// and Move Back in ···.
    case secureEnclave
    /// The vault says the Secure Enclave, and doctor has not answered yet
    /// whether this Mac's enclave has the key: no colour until it does.
    case checking
    /// The vault says the Secure Enclave, and the doctor check that would
    /// say whether this Mac's enclave has the key could not run: no colour,
    /// a Check Again, and Move Back still in ···.
    case unchecked
    /// The vault says the Secure Enclave, and this Mac's enclave has no
    /// such key: nothing opens until a recovery file is restored.
    case lost
    /// jit's `move_unfinished`: a move toward the place named stopped
    /// partway, and every vault write is refused until it finishes.
    case unfinished(VaultKeyPlace)
    /// jit's `restore_pending`: the key was lost and replaced, and secrets
    /// sealed to the old one stay unopenable until a recovery file is
    /// imported. The restore stays on offer until jit stops saying so.
    case restorePending
    /// `restore_pending` with jit's `restore_check_error`: jit could not
    /// check which secrets the lost key left sealed, and says why. jit
    /// names no restore for it, so the row offers none of its own: only
    /// Check Again, and whatever doctor's `vault_restore` finding names.
    case restoreUnchecked(String)
    /// Doctor's `rekey_unknown`: an unfinished change of the vault key
    /// this jit can't read or doesn't understand, in jit's own words.
    /// Every vault change is refused, a move too, so the row offers no
    /// move at all.
    case changeUnknown(String)

    /// The row, or nil where it has nothing true to offer: a jit that is
    /// not the app's own helper cannot reach the enclave, a jit too old to
    /// report where the key is cannot move it, and a Mac with no vault has
    /// no key to move. `keyLost` is doctor's word for the enclave's half,
    /// nil before doctor has answered; `doctorFailed` says the last check
    /// could not run (and none is running), so nil will not change by
    /// waiting. An unfinished move and a pending restore are jit's own
    /// status fields, never a guess of the app's; `changeUnknown` is
    /// doctor's `rekey_unknown` sentence (`changeUnknown(_:)`), which jit's
    /// status does not carry.
    public static func state(
        _ vault: CLIVaultStatus?, bundledHelper: Bool, keyLost: Bool?, doctorFailed: Bool = false,
        changeUnknown: String? = nil
    ) -> VaultKeyRow? {
        guard bundledHelper, let vault, vault.initialized == "yes", let place = VaultKeyPlace.of(vault) else {
            return nil
        }
        if place == .secureEnclave, keyLost == true {
            return .lost
        }
        if let changeUnknown {
            return .changeUnknown(changeUnknown)
        }
        if let unfinished = vault.moveUnfinished.flatMap(VaultKeyPlace.init(rawValue:)) {
            return .unfinished(unfinished)
        }
        if vault.restorePending == true {
            if let error = vault.restoreCheckError, !error.isEmpty {
                return .restoreUnchecked(error)
            }
            return .restorePending
        }
        switch place {
        case .keychain: return .keychain
        case .secureEnclave:
            if let keyLost {
                return keyLost ? .lost : .secureEnclave
            }
            return doctorFailed ? .unchecked : .checking
        }
    }

    /// Doctor's lost-key finding: `vault_key` with `jit vault init` among
    /// its fixes, which jit adds only when the key is not in this Mac's
    /// Secure Enclave (a keychain key that is gone needs no init). An
    /// ignored finding still counts: ignoring it opens nothing. nil when
    /// doctor has not run.
    public static func keyLost(_ report: DoctorReport?) -> Bool? {
        guard let report else {
            return nil
        }
        return (report.problems + report.ignored).contains(where: isLostFinding)
    }

    public static func isLostFinding(_ item: DoctorItem) -> Bool {
        item.kind == "vault_key" && (item.fixes ?? []).contains { $0.argv.starts(with: ["vault", "init"]) }
    }

    /// Doctor's `vault_restore`: secrets sealed to a lost key that no
    /// import has brought back yet. jit leaves it out while `vault_key`
    /// fires, so it never sits beside the lost-key finding.
    public static func isRestoreFinding(_ item: DoctorItem) -> Bool {
        item.kind == "vault_restore"
    }

    /// Doctor's `rekey_unknown` in jit's own words, its detail and then its
    /// step, each begun as a sentence: "A change of the vault key this
    /// version of jit doesn't understand is unfinished, … Update jit, then
    /// finish it with the newer jit." An ignored finding still counts:
    /// ignoring it refuses nothing less. nil when doctor has not run or
    /// reports none.
    public static func changeUnknown(_ report: DoctorReport?) -> String? {
        guard let report,
              let item = (report.problems + report.warnings + report.ignored).first(where: { $0.kind == "rekey_unknown" })
        else {
            return nil
        }
        return changeUnknownText(item)
    }

    static func changeUnknownText(_ item: DoctorItem) -> String {
        [item.detail, item.action].compactMap { part in
            guard let part = part?.trimmingCharacters(in: .whitespaces), !part.isEmpty else {
                return nil
            }
            // "jit" stays lower case: it is the tool's name.
            let sentence = part.hasPrefix("jit ") ? part : part.prefix(1).uppercased() + part.dropFirst()
            return sentence.hasSuffix(".") ? sentence : sentence + "."
        }.joined(separator: " ")
    }

    /// The restore the vault needs, and the finding it answers, or nil:
    /// the lost key's own (a new key, then the import); else what doctor's
    /// `vault_restore` finding names (the import alone, or nothing when jit
    /// could not check); else, before doctor has answered, the import for a
    /// restore jit's status reports pending and did check. Never an import
    /// while jit says it could not check (`restore_check_error`): the app
    /// adds no fix jit did not name.
    public static func restore(
        _ vault: CLIVaultStatus?, report: DoctorReport?
    ) -> (action: DoctorAction, finding: (DoctorItem) -> Bool)? {
        if keyLost(report) == true {
            return (DoctorAdvice.restoreRecoveryFile, isLostFinding)
        }
        let unchecked = !(vault?.restoreCheckError ?? "").isEmpty
        if let report, let item = (report.problems + report.ignored).first(where: isRestoreFinding) {
            let offered = DoctorAdvice.actions(for: item).first { !(unchecked && imports($0)) }
            return offered.map { ($0, isRestoreFinding) }
        }
        guard vault?.restorePending == true, !unchecked else {
            return nil
        }
        return (DoctorAdvice.importRecoveryFile, isRestoreFinding)
    }

    private static func imports(_ action: DoctorAction) -> Bool {
        DoctorAdvice.steps(of: action).contains(where: importsAFile)
    }

    /// Doctor's `vault_restore` when jit could not check it: no import of
    /// a recovery file among its fixes (jit gives the checked finding one,
    /// always). `jit vault import --finish`, the way out jit names for an
    /// unchecked restore, imports nothing.
    public static func isUncheckedRestore(_ item: DoctorItem) -> Bool {
        isRestoreFinding(item) && !(item.fixes ?? []).map(\.argv).contains(where: importsAFile)
    }

    /// `jit vault import <file>`, and not `jit vault import --finish`.
    static func importsAFile(_ argv: [String]) -> Bool {
        argv.starts(with: ["vault", "import"]) && !argv.contains("--finish")
    }

    /// Whether the move in can be offered: jit reports the recovery file,
    /// its gate, only for a vault with something in it (status.go returns
    /// before the export fields when secrets and backups are both zero),
    /// so an empty vault could never pass the sheet.
    public static func canMoveIn(_ vault: CLIVaultStatus?) -> Bool {
        guard let vault else {
            return false
        }
        return vault.secretsStored + (vault.backupsStored ?? 0) > 0
    }

    /// Doctor's Recommended offer: a keychain vault with secrets in it, on
    /// a Mac whose jit can move it, that the reader has not dismissed.
    /// Not while doctor reports a change jit doesn't understand
    /// (`changeUnknown`): jit refuses every move until it ends.
    public static func offersMove(
        _ vault: CLIVaultStatus?, bundledHelper: Bool, dismissed: Bool, changeUnknown: String? = nil
    ) -> Bool {
        !dismissed && (vault?.secretsStored ?? 0) > 0
            && state(vault, bundledHelper: bundledHelper, keyLost: false, changeUnknown: changeUnknown) == .keychain
    }
}

public extension VaultKeyPlace {
    /// Where `jit status` says the key is, or nil for a jit that does not
    /// say or a word this app does not know.
    static func of(_ vault: CLIVaultStatus?) -> VaultKeyPlace? {
        vault?.keyStore.flatMap(VaultKeyPlace.init(rawValue:))
    }

    /// Where doctor's `vault_move` finding says the unfinished move was
    /// going: its fix's `jit vault rekey --wrapper <target>`.
    static func moveTarget(_ item: DoctorItem) -> VaultKeyPlace? {
        guard item.kind == "vault_move" else {
            return nil
        }
        let argv = (item.fixes ?? []).map(\.argv).first { $0.starts(with: ["vault", "rekey", "--wrapper"]) && $0.count > 3 }
        return argv.flatMap { VaultKeyPlace(rawValue: $0[3]) }
    }
}

/// Where Try Again goes after a move failed.
public enum VaultKeyMove {
    /// The move to finish, when jit says one is unfinished
    /// (`move_unfinished`); `attempted` is the move whose failure the row
    /// is showing, kept only in memory for that row. A half-done move is
    /// finished by running the same one again, with no sheet: the question
    /// was answered when it started, and jit skips its recovery file rule
    /// for a move it is finishing. So is a failure that left the key at the
    /// target anyway. Otherwise the move that failed is asked again (sheet
    /// in, alert back), never the opposite one; the other place only when
    /// the app has no record of what it tried.
    public static func retry(unfinished: VaultKeyPlace?, attempted: VaultKeyPlace?, now: VaultKeyPlace?) -> VaultKeyRetry? {
        if let unfinished {
            return VaultKeyRetry(target: unfinished, finishes: true)
        }
        let target: VaultKeyPlace
        if let attempted {
            target = attempted
        } else if let now {
            target = now == .keychain ? .secureEnclave : .keychain
        } else {
            return nil
        }
        return VaultKeyRetry(target: target, finishes: attempted == target && now == target)
    }
}

/// What the failure row's button does: the move toward `target`, asked
/// again (sheet or alert), or run again to finish it.
public struct VaultKeyRetry: Equatable, Sendable {
    public var target: VaultKeyPlace
    public var finishes: Bool

    public init(target: VaultKeyPlace, finishes: Bool) {
        self.target = target
        self.finishes = finishes
    }
}

/// The move sheet's gate, which is jit's own (vaultmove.go's
/// recoveryFileCurrent, decision D3): a recovery file counts when jit has
/// one on record and no secret is newer than it (`export_stale` false).
/// jit records only the time, so the sheet claims nothing about a count.
public enum RecoveryFile: Equatable, Sendable {
    case none
    /// Newer than every secret: the move can go ahead.
    case current(at: Date)
    /// A secret was written after the file: jit's own `export_stale`, and
    /// jit refuses the move for it.
    case older(at: Date)

    public var ready: Bool {
        if case .current = self {
            return true
        }
        return false
    }

    public var savedAt: Date? {
        switch self {
        case .none: nil
        case let .current(at), let .older(at): at
        }
    }

    public static func check(_ vault: CLIVaultStatus?) -> RecoveryFile {
        guard let vault, vault.exportRecorded == true, let unix = vault.exportUnixTime else {
            return .none
        }
        let at = Date(timeIntervalSince1970: TimeInterval(unix))
        return vault.exportStale == true ? .older(at: at) : .current(at: at)
    }
}

/// Which of the move sheet's buttons takes Return. Never more than one,
/// and never Move Key while a save has failed: the row asking to save
/// again is the next step, even when an earlier file still counts.
public enum VaultKeySheetDefault: Equatable, Sendable {
    case saveRecoveryFile
    case moveKey
    /// While jit writes the file: nothing to press.
    case none

    public static func pick(_ file: RecoveryFile, saving: Bool, saveFailed: Bool) -> VaultKeySheetDefault {
        if saving {
            return .none
        }
        if saveFailed {
            return .saveRecoveryFile
        }
        return file.ready ? .moveKey : .saveRecoveryFile
    }

    /// Move Key can be pressed: the file counts and nothing is being saved.
    public static func moveEnabled(_ file: RecoveryFile, saving: Bool) -> Bool {
        file.ready && !saving
    }
}
