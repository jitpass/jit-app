// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Reset segment: everything that deletes or removes, least
/// destructive first, on a tab of its own so none of it sits beside a
/// daily switch. Each asks again before anything happens.
extension SettingsView {
    var resetCard: some View {
        AppPlainCard {
            AppRow(
                name: "Delete every secret, keep the vault",
                fact: "Every secret and every backup, gone for good. The vault stays usable.",
                wraps: true
            ) {
                Button("Clean in Terminal…", action: actions.vaultClean).buttonStyle(AppButton())
            }
            AppRow(
                name: "Destroy the vault and its key",
                fact: "The vault folder and its key. Nothing comes back.",
                wraps: true
            ) {
                Button("Delete in Terminal…", action: actions.vaultDelete)
                    .buttonStyle(AppButton(kind: .destructive))
            }
            AppRow(
                name: "Remove JitPass from this Mac",
                fact: "Every file goes back to what it held before JitPass. You see the full list first.",
                wraps: true,
                last: true
            ) {
                Button("Remove JitPass…", action: actions.removeJitPass).buttonStyle(AppButton(kind: .secondary))
            }
        }
    }
}
