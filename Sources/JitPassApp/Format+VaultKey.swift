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
    /// A lost key's is one word, so "Vault key missing" is never cut by
    /// the Restore button beside it, and so is a pending restore's: the
    /// lost key was replaced, and the fact says what that left behind. An
    /// unfinished move says where jit says the key is now.
    static func vaultKeyDetail(_ row: VaultKeyRow, now: VaultKeyPlace?) -> String {
        switch row {
        case .keychain: "in your login keychain"
        case .secureEnclave, .copyInKeychain, .checking, .unchecked: "in the Secure Enclave"
        case .lost: "missing"
        case .restorePending, .restoreUnchecked: "replaced"
        case .unfinished, .changeUnknown: now == .secureEnclave ? "in the Secure Enclave" : "in your login keychain"
        }
    }

    /// `movable`: false for an empty vault, which jit reports no recovery
    /// file for, so the row says why it offers no move.
    static func vaultKeyFact(_ row: VaultKeyRow, movable: Bool = true) -> String {
        switch row {
        case .keychain:
            movable ? "JitPass asks for Touch ID. A program running as you could read it."
                : "A program running as you could read it. It can move once the vault holds a secret."
        case .secureEnclave: "Only JitPass can use it, after Touch ID or your password."
        // jit's `keychain_copy_left`, worded as jit words it: an item has
        // the vault key's name, and only a read could say it is the same
        // key, so "a key", never "a copy". Doctor's card carries the fix.
        case .copyInKeychain: "A key is still in your keychain under its name; Doctor can remove it."
        case .checking: "Checking that this Mac's Secure Enclave has it…"
        case .unchecked: "The check that this Mac's Secure Enclave has it couldn't run."
        // Doctor's Fix now card, in its own words: it carries the restore.
        case .lost: "This Mac's Secure Enclave doesn't have the vault key. The vault can't open here."
        case let .unfinished(target): target == .secureEnclave
            ? "Moving it into the Secure Enclave did not finish. Vault changes are refused until it does."
            : "Moving it back to your keychain did not finish. Vault changes are refused until it does."
        // jit's own status line; status gives no count, doctor's card does.
        case .restorePending: "Some secrets are sealed to a key this Mac no longer has. A recovery file brings them back."
        // jit's own status line, error and all: it could not check, so
        // nothing here claims secrets are sealed, or that a restore helps.
        case let .restoreUnchecked(error): "jit couldn't check the vault for secrets sealed to a lost key: " + error
        // jit's own sentence and step (doctor's rekey_unknown).
        case let .changeUnknown(words): words
        }
    }

    /// The failure row's button: the question again, or the half-done
    /// move run again as it is.
    static func vaultKeyRetryTitle(finishes: Bool) -> String {
        finishes ? "Finish Move" : "Try Again…"
    }

    /// Asks jit again: after a move whose result is unknown, on an enclave
    /// row whose doctor check could not run, and where jit could not check
    /// a restore or does not understand an unfinished change.
    static let vaultKeyCheckAgain = "Check Again"

    // MARK: - Restore, in the Doctor window

    static let restoreQueued = "Restore from Recovery File… starts when this check finishes."
    static let restoreBusy = "Another action is still running. Restore from Recovery File… when it finishes."
    static let restoreNotNeeded = "This Mac has the vault key now, so there is nothing to restore."

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

    /// When, and jit's own verdict on it: newer than every secret (the
    /// move can go), or secrets added or changed since (jit refuses it).
    /// jit records only the time, so nothing here claims a count.
    static func recoveryFileFact(_ file: RecoveryFile, now: Date = Date()) -> String {
        switch file {
        case .none:
            "Every secret, encrypted with a passphrase you choose."
        case let .current(at):
            [when(at, now: now), "newer than every secret in the vault"].joined(separator: " · ")
        case let .older(at):
            [when(at, now: now), "secrets were added or changed after it was saved"].joined(separator: " · ")
        }
    }

    static let moveSheetCommand = "jit " + VaultKeyPlace.secureEnclave.moveArguments.joined(separator: " ")

    // MARK: - Moving back (the alert)

    static let moveBackTitle = "Move the vault key back to your keychain?"
    static let moveBackMessage = "A program running as you could read it from the keychain again, as before. "
        + "Your secrets, grants and AI Jobs stay as they are. Touch ID follows."

    // MARK: - Helpers

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
