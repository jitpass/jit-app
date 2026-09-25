// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The vault key's place and the recovery file, as the Settings row, the
/// move sheet and Doctor's offer read them.
extension MenuModel {
    /// The Protection card's Vault key row, or nil where it is not drawn.
    var vaultKeyRow: VaultKeyRow? {
        VaultKeyRow.state(
            cli?.vault, bundledHelper: JitCLI.isBundledHelper, keyLost: VaultKeyRow.keyLost(doctor),
            doctorFailed: doctorFailed && !doctorRunning
        )
    }

    /// Where jit says the key is now.
    var vaultKeyPlace: VaultKeyPlace? {
        VaultKeyPlace.of(cli?.vault)
    }

    /// jit's own word on an unfinished move: where it was going.
    var vaultKeyUnfinished: VaultKeyPlace? {
        cli?.vault?.moveUnfinished.flatMap(VaultKeyPlace.init(rawValue:))
    }

    /// The move sheet's gate: jit's own.
    var recoveryFile: RecoveryFile {
        RecoveryFile.check(cli?.vault)
    }

    /// Whether the move in can be offered at all (not on an empty vault).
    var canMoveVaultKeyIn: Bool {
        VaultKeyRow.canMoveIn(cli?.vault)
    }

    /// The failure row's Try Again: which way, and whether it finishes.
    var vaultKeyRetry: VaultKeyRetry? {
        VaultKeyMove.retry(unfinished: vaultKeyUnfinished, attempted: vaultKeyAttempted, now: vaultKeyPlace)
    }

    /// Doctor's Recommended card.
    var offersVaultKeyMove: Bool {
        VaultKeyRow.offersMove(cli?.vault, bundledHelper: JitCLI.isBundledHelper, dismissed: vaultKeyOfferDismissed)
    }
}
