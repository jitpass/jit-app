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

    /// The lost enclave key in the reader's words. The note does not guess
    /// the cause: jit can't tell a new Mac from a repaired one. The button
    /// is the vault_key finding's own restore (`DoctorAdvice`).
    static func vaultKeyLost(_ card: DoctorCard) -> DoctorCard {
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
}
