// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The Vault key row's and the move sheet's words, in one place. The
/// drawing they follow is the "Vault key in the Secure Enclave" mockup,
/// with its Vault card folded into one row of the Protection card.
extension Format {
    // MARK: - The row

    static let vaultKeyName = "Vault key"

    /// The mono detail beside the name, as the PATH row names its path.
    static func vaultKeyDetail(_ row: VaultKeyRow) -> String {
        switch row {
        case .keychain: "in your login keychain"
        case .secureEnclave, .lost: "in the Secure Enclave"
        }
    }

    static func vaultKeyFact(_ row: VaultKeyRow) -> String {
        switch row {
        case .keychain: "JitPass asks for Touch ID. A program running as you could read it."
        case .secureEnclave: "Only JitPass can use it, after Touch ID or your password."
        // Doctor's Fix now card, in its own words: it carries the restore.
        case .lost: "This Mac's Secure Enclave doesn't have the vault key. The vault can't open here."
        }
    }

    static let vaultKeyMoving = "Moving the key…"
    static let vaultKeyWaiting = "Waiting for Touch ID"

    // MARK: - The sheet

    static let moveSheetTitle = "Move the vault key into the Secure Enclave?"
    static let moveSheetCost = "After this, the key can't leave this Mac."
    static let moveSheetCostRest = " If this Mac is lost, replaced or erased, your secrets come back only from a recovery file."

    /// The three promises, each a name and the fact under it.
    static let moveSheetPromises: [(name: String, fact: String)] = [
        ("Your secrets, grants and AI Jobs stay as they are", "Nothing is re-encrypted. Tools keep working."),
        ("Only JitPass can use the key", "And only after Touch ID or your password. Other programs can't read it."),
        ("You can move it back", "Settings › Protection, any time. Touch ID once.")
    ]

    /// The recovery file row's name: none yet, or when it was saved.
    static func recoveryFileName(_ file: RecoveryFile, now: Date = Date()) -> String {
        guard let at = file.savedAt else {
            return "No recovery file yet"
        }
        return "Recovery file saved " + day(at, now: now)
    }

    /// "11:42 · 67 secrets · the vault holds 67": when, what it holds, and
    /// what the vault holds now, so a file older than recent changes
    /// shows it. Without a count, the part that decides instead.
    static func recoveryFileFact(_ file: RecoveryFile, vault: Int, now: Date = Date()) -> String {
        let holds = "the vault holds \(vault)"
        switch file {
        case .none:
            return "Every secret, encrypted with a passphrase you choose."
        case let .current(at, secrets):
            return ([when(at, now: now)] + (secrets.map { [secretsWord($0)] } ?? []) + [holds]).joined(separator: " · ")
        case let .behind(at, secrets, _):
            return [when(at, now: now), secretsWord(secrets), holds].joined(separator: " · ")
        case let .older(at):
            return [when(at, now: now), "older than your newest secret"].joined(separator: " · ")
        case let .expired(at):
            return [when(at, now: now), "more than 30 days old"].joined(separator: " · ")
        }
    }

    static let moveSheetCommand = "jit " + VaultKeyPlace.secureEnclave.moveArguments.joined(separator: " ")

    // MARK: - Moving back (the alert)

    static let moveBackTitle = "Move the vault key back to your keychain?"
    static let moveBackMessage = "A program running as you could read it from the keychain again, as before. "
        + "Your secrets, grants and AI Jobs stay as they are. Touch ID follows."

    // MARK: - Helpers

    private static func secretsWord(_ count: Int) -> String {
        count == 1 ? "1 secret" : "\(count) secrets"
    }

    /// "today", "yesterday", "3 days ago".
    private static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }

    /// The time for today's file, the day and time for an older one.
    private static func when(_ date: Date, now: Date) -> String {
        stamp(date, withDay: !Calendar.current.isDate(date, inSameDayAs: now))
    }
}
