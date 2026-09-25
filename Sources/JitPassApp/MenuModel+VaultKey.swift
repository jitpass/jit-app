// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The vault key's place and the recovery file, as the Settings row, the
/// move sheet and Doctor's offer read them.
extension MenuModel {
    /// The Protection card's Vault key row, or nil where it is not drawn.
    var vaultKeyRow: VaultKeyRow? {
        VaultKeyRow.state(cli?.vault, bundledHelper: JitCLI.isBundledHelper, keyLost: VaultKeyRow.keyLost(doctor))
    }

    /// The move sheet's gate.
    var recoveryFile: RecoveryFile {
        RecoveryFile.check(cli?.vault, recorded: recoveryFileRecorded)
    }

    /// Doctor's Recommended card.
    var offersVaultKeyMove: Bool {
        VaultKeyRow.offersMove(cli?.vault, bundledHelper: JitCLI.isBundledHelper, dismissed: vaultKeyOfferDismissed)
    }
}
