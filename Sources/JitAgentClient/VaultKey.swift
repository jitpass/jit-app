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
    /// The vault says the Secure Enclave, and this Mac's enclave has no
    /// such key: nothing opens until a recovery file is restored.
    case lost
    /// A move this app started toward the place named, whose marker jit
    /// still has: every vault write is refused until it finishes.
    case unfinished(VaultKeyPlace)

    /// The row, or nil where it has nothing true to offer: a jit that is
    /// not the app's own helper cannot reach the enclave, a jit too old to
    /// report where the key is cannot move it, and a Mac with no vault has
    /// no key to move. `keyLost` is doctor's word for the enclave's half,
    /// nil before doctor has answered; `unfinished` is `VaultKeyMove`'s.
    public static func state(
        _ vault: CLIVaultStatus?, bundledHelper: Bool, keyLost: Bool?, unfinished: VaultKeyPlace? = nil
    ) -> VaultKeyRow? {
        guard bundledHelper, let vault, vault.initialized == "yes", let place = VaultKeyPlace.of(vault) else {
            return nil
        }
        if place == .secureEnclave, keyLost == true {
            return .lost
        }
        if let unfinished {
            return .unfinished(unfinished)
        }
        switch place {
        case .keychain: return .keychain
        case .secureEnclave: return keyLost == false ? .secureEnclave : .checking
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
    public static func offersMove(_ vault: CLIVaultStatus?, bundledHelper: Bool, dismissed: Bool) -> Bool {
        !dismissed && (vault?.secretsStored ?? 0) > 0
            && state(vault, bundledHelper: bundledHelper, keyLost: false) == .keychain
    }
}

public extension VaultKeyPlace {
    /// Where `jit status` says the key is, or nil for a jit that does not
    /// say or a word this app does not know.
    static func of(_ vault: CLIVaultStatus?) -> VaultKeyPlace? {
        vault?.keyStore.flatMap(VaultKeyPlace.init(rawValue:))
    }
}

/// A move the app started, and what jit's marker says about it. jit
/// reports the marker only as doctor's `rekey` finding, which does not
/// tell a move from a rotation or name the move's target, so the target
/// is the one the app itself asked for (kept until jit's marker is gone).
public enum VaultKeyMove {
    /// Whether jit's rekey marker is there: doctor's `rekey` finding,
    /// ignored or not. nil when doctor has not run.
    public static func markerPresent(_ report: DoctorReport?) -> Bool? {
        guard let report else {
            return nil
        }
        return (report.problems + report.warnings + report.ignored).contains { $0.kind == "rekey" }
    }

    /// The move to finish: the app's own target, while the marker is there.
    public static func unfinished(pending: VaultKeyPlace?, report: DoctorReport?) -> VaultKeyPlace? {
        markerPresent(report) == true ? pending : nil
    }

    /// Whether the app's record of its move can go: doctor answered and
    /// jit has no marker, so nothing is left to finish.
    public static func settled(_ report: DoctorReport?) -> Bool {
        markerPresent(report) == false
    }

    /// Where Try Again goes: the move that failed, because a half-done
    /// move is finished by running the same one again and jit refuses the
    /// other direction; the other place only when the app has no record.
    /// `finishes` when that move is half done (the key already reached the
    /// target, or jit's marker is there): it runs again as it is, with no
    /// sheet, because the question was answered when it started and jit
    /// skips its recovery file rule for a move it is finishing.
    public static func retry(pending: VaultKeyPlace?, now: VaultKeyPlace?, report: DoctorReport?) -> VaultKeyRetry? {
        let target: VaultKeyPlace
        if let pending {
            target = pending
        } else if let now {
            target = now == .keychain ? .secureEnclave : .keychain
        } else {
            return nil
        }
        let finishes = pending == target && (now == target || markerPresent(report) == true)
        return VaultKeyRetry(target: target, finishes: finishes)
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
