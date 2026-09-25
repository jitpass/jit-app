// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Doctor's two vault key cards, frame H of the "Vault key in the Secure
/// Enclave" mockup: the offer to move the key, Recommended because nothing
/// is broken, and the lost key, Fix now because the vault cannot open.
extension DoctorBoard {
    static let vaultKeyOfferID = "vault-key-offer"

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
        if card.items.count == 1, let item = card.items.first, item.kind == "vault_move", let detail = item.detail {
            // jit's own sentence, which says which way the move was going,
            // begun as a sentence: it starts lower case in jit's report.
            var card = card
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

    /// Doctor's `vault_move` card: the unfinished move run again as it is,
    /// the command the Settings row's Finish Move runs.
    static func finishMove(_ target: VaultKeyPlace) -> DoctorAction {
        DoctorAction(
            "Finish Move", "jit vault rekey --wrapper \(target.rawValue)", argv: [target.moveArguments], presence: true
        )
    }
}
