// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Vault window's plain settings (design/secrets-only-vault.md in the
/// jit repo): the Settings card beside a profile's secrets, and the
/// banner for profiles protected before settings stayed plain.
extension VaultView {
    /// The profile's plain settings, on the same scroll as its secrets:
    /// plain text, no Touch ID to read, each one movable into the vault.
    func settingsCard(_ kept: [VaultSettingsListing.Setting], onlySettings: Bool) -> some View {
        AppCard(
            eyebrow: "Plain text", eyebrowTint: Color.secondary.opacity(0.5),
            title: Format.count(kept.count, "setting"),
            note: onlySettings ? Format.vaultOnlySettingsNote : Format.vaultSettingsNote
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(kept.enumerated()), id: \.element.path) { index, setting in
                    VaultRow(name: setting.name, fact: setting.value, factMono: true, last: index == kept.count - 1) {
                        Button("Move to Vault") { actions.moveIn(setting.path) }
                            .buttonStyle(AppButton(kind: .quiet))
                            .disabled(model.vaultBusy != nil)
                            .help("Reading it will then need Touch ID or a grant. Touch ID follows.")
                    }
                }
            }
        }
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
            .padding(.horizontal, Win.s6).padding(.vertical, Win.s4)
            .background(Color(StatusMark.amber).opacity(0.18))
        }
    }
}
