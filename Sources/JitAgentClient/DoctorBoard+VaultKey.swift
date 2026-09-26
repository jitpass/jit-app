// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Doctor's two vault key cards, frame H of the "Vault key in the Secure
/// Enclave" mockup: the offer to move the key, Recommended because nothing
/// is broken, and the lost key, Fix now because the vault cannot open.
extension DoctorBoard {
    static let vaultKeyOfferID = "vault-key-offer"

    /// Kinds whose card says jit's own sentence: an unfinished move, and a
    /// key left in the keychain of an enclave vault.
    static let ownSentenceKinds: Set = ["vault_move", "vault_key_copy"]

    /// Doctor's `vault_restore` when jit could not check it.
    static let restoreUncheckedTitle = "Can't tell whether secrets still need restoring"

    /// "Move…" opens the move sheet; ··· holds Don't Suggest Again, which
    /// has no undo: the Settings row is where the move stays on offer.
    static var vaultKeyOffer: DoctorCard {
        var card = DoctorCard(
            id: vaultKeyOfferID, tier: .recommended, title: "Keep the vault key in the Secure Enclave", items: []
        )
        card.reason = "In the keychain, a program running as you could read it. Touch ID moves it."
        card.primary = DoctorButton("Move…", .moveVaultKey)
        card.primaryProminent = false
        card.menu = [.button(DoctorButton("Don't Suggest Again", .dismissVaultKeyOffer))]
        return card
    }

    /// The lost enclave key in the reader's words, and an unfinished move
    /// in jit's. The note does not guess
    /// the cause: jit can't tell a new Mac from a repaired one. The button
    /// is the vault_key finding's own restore (`DoctorAdvice`).
    static func vaultKeyLost(_ card: DoctorCard) -> DoctorCard {
        if card.items.count == 1, let item = card.items.first, ownSentenceKinds.contains(item.kind), let detail = item.detail {
            // jit's own sentence, begun as a sentence: it starts lower case
            // in jit's report. For a move it says which way it was going;
            // for a key left in the keychain, who can read it there.
            var card = card
            card.reason = detail.prefix(1).uppercased() + detail.dropFirst()
            card.subject = "The vault key"
            return card
        }
        if card.items.count == 1, let item = card.items.first, item.kind == "rekey_unknown" {
            // jit's sentence and its step, which names no command.
            var card = card
            card.reason = VaultKeyRow.changeUnknownText(item)
            card.subject = "The vault key"
            return card
        }
        if card.items.count == 1, let item = card.items.first, VaultKeyRow.isUncheckedRestore(item), let detail = item.detail {
            // jit could not check which secrets are sealed to the lost key:
            // no count, no import, and nothing claimed. jit's own words.
            var card = card
            card.title = restoreUncheckedTitle
            card.reason = detail.prefix(1).uppercased() + detail.dropFirst()
            card.subject = "The vault key"
            return card
        }
        guard card.items.contains(where: VaultKeyRow.isLostFinding) else {
            return card
        }
        var card = card
        card.title = "This Mac's Secure Enclave doesn't have the vault key"
        card.subject = "The vault key"
        card.reason = "The vault can't open here. A recovery file brings every secret back."
        card.detail = nil
        return card
    }
}

public extension DoctorAdvice {
    /// The lost key's restore: the import the Doctor window already runs
    /// for a missing key, after the `jit vault init` jit's fix names.
    static let restoreRecoveryFile = DoctorAction(
        "Restore from Recovery File", "jit vault init && jit vault import <file>",
        needs: .existingPath(placeholder: "<file>"),
        argv: [["vault", "init"], ["vault", "import", "<file>", "--stdin", "--yes"]],
        input: .passphrase(prompt: "The recovery file's passphrase")
    )

    /// The restore after a lost key that has a new one already (doctor's
    /// `vault_restore`, status's `restore_pending`): the import alone.
    static let importRecoveryFile = DoctorAction(
        "Restore from Recovery File", "jit vault import <file>",
        needs: .existingPath(placeholder: "<file>"),
        argv: [["vault", "import", "<file>", "--stdin", "--yes"]],
        input: .passphrase(prompt: "The recovery file's passphrase")
    )

    /// Doctor's `vault_restore`: the import alone (the key exists already,
    /// jit made it when the old one was lost), but only when jit's finding
    /// names the import. When jit could not check which secrets are sealed
    /// to the lost key it names no import, and the app adds none: only what
    /// jit's fixes name (its Finish Restore, or a generic button), or
    /// nothing.
    static func restoreActions(_ item: DoctorItem) -> [DoctorAction] {
        guard VaultKeyRow.isUncheckedRestore(item) else {
            return [importRecoveryFile]
        }
        return (item.fixes ?? []).filter { !DoctorItem.needsReference($0.command) }.map { fix in
            fix.argv == ["vault", "import", "--finish"] ? finishRestore : generic(fix)
        }
    }

    /// `jit vault import --finish`: stops tracking a restore jit can't
    /// check, once every recovery file is in. In the terminal, without
    /// --yes: jit lists the secrets that may still not open before its own
    /// y/N, and the app has no way to show that list itself.
    static let finishRestore = DoctorAction("Finish Restore", "jit vault import --finish")

    /// Doctor's `vault_key_copy`: jit's own fix, run as the generic button
    /// runs it (in the terminal, where jit asks its own y/N and explains
    /// --force when the key isn't the vault's), titled by what it does.
    /// Any other fix jit names keeps the generic button.
    static func removeKeychainCopy(_ item: DoctorItem) -> [DoctorAction] {
        (item.fixes ?? []).filter { !DoctorItem.needsReference($0.command) }.map { fix in
            var action = generic(fix)
            if fix.argv == ["vault", "rekey", "--wrapper", VaultKeyPlace.secureEnclave.rawValue] {
                action.title = "Remove from Keychain"
            }
            return action
        }
    }

    /// Doctor's `vault_move` card: the unfinished move run again as it is,
    /// the command the Settings row's Finish Move runs.
    static func finishMove(_ target: VaultKeyPlace) -> DoctorAction {
        DoctorAction(
            "Finish Move", "jit vault rekey --wrapper \(target.rawValue)", argv: [target.moveArguments], presence: true
        )
    }
}
