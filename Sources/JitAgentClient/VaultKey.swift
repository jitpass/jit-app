// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Where the vault key is kept, and moving it (the Secure Enclave plan,
/// step A4; the mockup is "Vault key in the Secure Enclave"). The move is
/// jit's own `jit vault rekey --wrapper …`: the app decides only whether
/// to show the row and whether the recovery file is good enough to offer
/// Move Key.
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
    /// The vault says the Secure Enclave, and this Mac's enclave has no
    /// such key: nothing opens until a recovery file is restored.
    case lost

    /// The row, or nil where it has nothing true to offer: a jit that is
    /// not the app's own helper cannot reach the enclave, a jit too old to
    /// report where the key is cannot move it, and a Mac with no vault has
    /// no key to move. `keyLost` is doctor's word for the enclave's half.
    public static func state(_ vault: CLIVaultStatus?, bundledHelper: Bool, keyLost: Bool) -> VaultKeyRow? {
        guard bundledHelper, let vault, vault.initialized == "yes",
              let place = vault.keyStore.flatMap(VaultKeyPlace.init(rawValue:))
        else {
            return nil
        }
        switch place {
        case .keychain: return .keychain
        case .secureEnclave: return keyLost ? .lost : .secureEnclave
        }
    }

    /// Whether the jit the app runs is the helper inside this app, the one
    /// binary a provisioning profile lets use the Secure Enclave: its path,
    /// or `Contents/MacOS/jit`, the compat symlink to it. A Homebrew or
    /// development jit is not, even when it is the same version.
    public static func isBundledHelper(_ executable: String?, bundleURL: URL) -> Bool {
        guard let executable else {
            return false
        }
        let helper = bundleURL.appendingPathComponent(CommandLineTool.bundledRelativePath)
        return resolved(URL(fileURLWithPath: executable)) == resolved(helper)
    }

    private static func resolved(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Doctor's lost-key finding: `vault_key` with `jit vault init` among
    /// its fixes, which jit adds only when the key is not in this Mac's
    /// Secure Enclave (a keychain key that is gone needs no init).
    public static func keyLost(_ report: DoctorReport?) -> Bool {
        (report?.problems ?? []).contains(where: isLostFinding)
    }

    public static func isLostFinding(_ item: DoctorItem) -> Bool {
        item.kind == "vault_key" && (item.fixes ?? []).contains { $0.argv.starts(with: ["vault", "init"]) }
    }

    /// Doctor's Recommended offer: a keychain vault with secrets in it, on
    /// a Mac whose jit can move it, that the reader has not dismissed.
    public static func offersMove(_ vault: CLIVaultStatus?, bundledHelper: Bool, dismissed: Bool) -> Bool {
        !dismissed && (vault?.secretsStored ?? 0) > 0
            && state(vault, bundledHelper: bundledHelper, keyLost: false) == .keychain
    }
}

/// A recovery file the app saw jit write: when jit recorded it, and how
/// many secrets jit said it put in it. jit records only the time, so the
/// count is known only for a file saved from the app.
public struct RecordedExport: Codable, Equatable, Sendable {
    public var unixTime: Int64
    public var secrets: Int

    public init(unixTime: Int64, secrets: Int) {
        self.unixTime = unixTime
        self.secrets = secrets
    }

    /// The count in jit's own closing line, "Exported 67 secrets to …"
    /// (or "1 secret"); nil when the line is not there.
    public static func count(in output: String) -> Int? {
        for line in output.split(separator: "\n") {
            let words = line.split(separator: " ")
            if words.count > 2, words[0] == "Exported", words[2].hasPrefix("secret"), let count = Int(words[1]) {
                return count
            }
        }
        return nil
    }
}

/// The move sheet's gate. A recovery file counts when it holds the vault's
/// current secret count; where the count is not known (a file saved in a
/// terminal), when it is at most 30 days old. Either way a file jit calls
/// stale (a secret written since) does not count, because jit refuses the
/// move for it.
public enum RecoveryFile: Equatable, Sendable {
    case none
    /// `secrets` is nil when the count is not known.
    case current(at: Date, secrets: Int?)
    /// The file holds a different number of secrets than the vault.
    case behind(at: Date, secrets: Int, vault: Int)
    /// A secret was written after the file: jit's own `export_stale`.
    case older(at: Date)
    /// No count to compare, and older than `fallbackAge`.
    case expired(at: Date)

    public static let fallbackAge: TimeInterval = 30 * 24 * 60 * 60

    public var ready: Bool {
        if case .current = self {
            return true
        }
        return false
    }

    public var savedAt: Date? {
        switch self {
        case .none: nil
        case let .current(at, _), let .behind(at, _, _), let .older(at), let .expired(at): at
        }
    }

    /// `recorded` counts only when it is the export jit has on record now:
    /// a file saved later in a terminal replaces jit's record, not the app's.
    public static func check(_ vault: CLIVaultStatus?, recorded: RecordedExport?, now: Date = Date()) -> RecoveryFile {
        guard let vault, vault.exportRecorded == true, let unix = vault.exportUnixTime else {
            return .none
        }
        let at = Date(timeIntervalSince1970: TimeInterval(unix))
        if vault.exportStale == true {
            return .older(at: at)
        }
        if let recorded, recorded.unixTime == unix {
            return recorded.secrets == vault.secretsStored
                ? .current(at: at, secrets: recorded.secrets)
                : .behind(at: at, secrets: recorded.secrets, vault: vault.secretsStored)
        }
        return now.timeIntervalSince(at) > fallbackAge ? .expired(at: at) : .current(at: at, secrets: nil)
    }

    /// How many more secrets the vault holds than the file, when both
    /// counts are known: the number a stale-file refusal names.
    public static func newSecrets(_ vault: CLIVaultStatus?, recorded: RecordedExport?) -> Int? {
        guard let vault, let recorded, recorded.unixTime == vault.exportUnixTime, vault.secretsStored > recorded.secrets else {
            return nil
        }
        return vault.secretsStored - recorded.secrets
    }
}
