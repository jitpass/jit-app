// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// A profile's line and a secret's verbs, split out of VaultView so the
/// window's layout reads on its own.
extension VaultView {
    /// The selected secret's verbs, in the bar under the table.
    @ViewBuilder func secretButtons(_ secret: VaultSecret) -> some View {
        Button("Reveal") { actions.reveal(secret.path) }
        Button("Copy") { actions.copy(secret.path) }
        Button("Replace…") { actions.openSheet(replaceSheet(secret)) }
        Button("History…") { actions.openSheet(.history(path: secret.path)) }
        if !secret.isLinked, model.vaultSettings != nil {
            Button("Move Out…") { actions.openSheet(.moveOut(paths: [secret.path])) }
                .help("Keep it as a plain setting beside the vault instead")
        }
        Button("Delete…") { actions.delete([secret.path]) }
    }

    @ViewBuilder func rowMenu(_ secret: VaultSecret) -> some View {
        Button("Reveal for \(StatusItemController.revealSeconds)s") { actions.reveal(secret.path) }
        Button("Copy to Clipboard") { actions.copy(secret.path) }
        Divider()
        Button("Replace…") { actions.openSheet(replaceSheet(secret)) }
        Button("History…") { actions.openSheet(.history(path: secret.path)) }
        if !secret.isLinked, model.vaultSettings != nil {
            Button("Move Out of Vault…") { actions.openSheet(.moveOut(paths: [secret.path])) }
        }
        Divider()
        Button("Delete…") { actions.delete([secret.path]) }
    }

    /// A linked secret is replaced with another link; a value with a value.
    func replaceSheet(_ secret: VaultSecret) -> VaultSheet {
        secret.isLinked ? .link(group: secret.group, replacing: secret.path) : .add(group: secret.group, replacing: secret.path)
    }

    /// "4 secrets · from ~/.clisso.yaml", with "(file gone)" when the
    /// origin no longer exists; "set by hand" when nothing was recorded.
    func profileLine(_ group: VaultGroup) -> String {
        var parts = [Format.profileCounts(secrets: group.secrets.count, settings: settings(group).count)]
        if let origin = group.origin {
            parts.append("from " + origin + (VaultOrigin.exists(origin) ? "" : " (file gone)"))
        } else if group.secrets.isEmpty {
            // All settings: nothing in the vault to have come from anywhere.
        } else if group.secrets.allSatisfy({ $0.origin == nil }) {
            parts.append("set by hand")
        } else {
            parts.append("from several files")
        }
        return parts.joined(separator: " · ")
    }

    /// The selected profile's plain settings, beside the vault.
    func settings(_ group: VaultGroup) -> [VaultSettingsListing.Setting] {
        model.vaultSettings?.settings(in: group.name) ?? []
    }
}
