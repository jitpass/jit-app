// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Vault window's plain settings (design/secrets-only-vault.md in the
/// jit repo): the Settings section under a profile's secrets, and the
/// banner for profiles protected before settings stayed plain.
extension VaultView {
    /// The profile's plain settings, under its secrets: plain text, no
    /// Touch ID to read, each one movable into the vault (mockup section 3).
    func settingsSection(_ kept: [VaultSettingsListing.Setting]) -> some View {
        VStack(alignment: .leading, spacing: Win.s2) {
            HStack(spacing: Win.s3) {
                Text("Settings").font(Win.cardTitle)
                Text("plain text, not in the vault").font(Win.sub).foregroundStyle(.secondary)
            }
            CappedScroll(maxHeight: 180) {
                ForEach(Array(kept.enumerated()), id: \.element.path) { index, setting in
                    AppRow(name: setting.name, detail: setting.value, last: index == kept.count - 1) {
                        Button("Move to Vault") { actions.moveIn(setting.path) }
                            .buttonStyle(AppButton(kind: .quiet))
                            .disabled(model.vaultBusy != nil)
                            .help("Reading it will then need Touch ID or a grant. Touch ID follows.")
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    /// Profiles protected before settings stayed plain: said once, above
    /// the profile. It counts entries nobody has checked, not settings:
    /// knowing which are settings means reading them (CheckSettingsSheet).
    @ViewBuilder var cleanupBanner: some View {
        // Only on an engine that keeps settings (it answered `vault
        // settings`): on an older one every .env entry is unchecked and
        // `jit migrate settings` does not exist.
        let unchecked = model.vaultSettings == nil ? [] : (model.vaultListing?.uncheckedFromEnv ?? [])
        if !unchecked.isEmpty {
            let profiles = Set(unchecked.map(\.group)).count
            HStack(spacing: Win.s3) {
                StateDot(tint: Color(StatusMark.amber))
                Text("\(profiles) profile\(profiles == 1 ? "" : "s") protected before settings stayed plain may hold settings")
                    .font(Win.sub)
                Spacer()
                Button("Move Them Out…") { actions.openSheet(.checkSettings) }
                    .buttonStyle(AppButton(kind: .plain))
                    .disabled(model.vaultBusy != nil)
            }
            .padding(.horizontal, 16).padding(.vertical, Win.s4)
            .background(Color(StatusMark.amber).opacity(0.18))
        }
    }
}
