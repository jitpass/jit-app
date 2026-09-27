// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Move Out of Vault's question (the "Secrets-Only Vault" mockup, 3b). It
/// leads with the cost: any program on this Mac can read the value. A value
/// the scan counts as a secret, or one nobody has checked, carries the
/// warning on its own row, and then Return cancels: the move is still the
/// user's call (D6), it is just not the default.
struct MoveOutSheet: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions
    let paths: [String]

    private var secrets: [VaultSecret] {
        paths.compactMap { path in model.vaultListing?.secrets.first { $0.path == path } }
    }

    private var risky: Bool {
        secrets.contains(where: \.moveOutIsRisky)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(title).font(Win.cardTitle)
                Text(sentence).font(Win.sub).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            AppPlainCard {
                ForEach(Array(secrets.enumerated()), id: \.element.path) { index, secret in
                    AppRow(
                        dot: secret.moveOutIsRisky ? Color(StatusMark.amber) : Color(StatusMark.green),
                        name: secret.name,
                        fact: fact(secret),
                        wraps: true,
                        last: index == secrets.count - 1
                    ) {}
                }
            }
            HStack(spacing: Win.s4) {
                Text("Touch ID follows. Move to Vault puts \(paths.count == 1 ? "it" : "them") back.")
                    .font(Win.sub).foregroundStyle(.secondary)
                Spacer(minLength: Win.s5)
                if risky {
                    Button("Cancel", action: actions.closeSheet).buttonStyle(AppButton(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                    Button("Move Out") { actions.moveOut(paths) }.buttonStyle(AppButton())
                } else {
                    Button("Cancel", action: actions.closeSheet).buttonStyle(AppButton()).keyboardShortcut(.cancelAction)
                    Button("Move Out") { actions.moveOut(paths) }.buttonStyle(AppButton(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .disabled(model.vaultBusy != nil)
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onExitCommand(perform: actions.closeSheet)
    }

    private var title: String {
        paths.count == 1
            ? "Move \(secrets.first?.name ?? paths[0]) out of the vault?"
            : "Move \(paths.count) values out of the vault?"
    }

    private var sentence: String {
        let profile = secrets.first?.group ?? ""
        let what = paths.count == 1 ? "It becomes a plain setting" : "They become plain settings"
        let who = paths.count == 1 ? "it" : "them"
        return "\(what) of \(profile), and the file keeps working. Any program on this Mac can read \(who), with no Touch ID and no grant."
    }

    private func fact(_ secret: VaultSecret) -> String {
        switch secret.scan {
        case "secret": "The scan counts this as a secret. It will show in Findings again as a plain-text secret."
        case "check": "Scan can't tell whether this is a secret. The name looks like one, the value doesn't."
        case "setting": "The scan doesn't count this as a secret."
        default: "Nobody has checked this value: it was protected before jit kept settings out of the vault."
        }
    }
}

/// The cleanup for profiles protected before settings stayed plain. It can
/// count the entries, not the settings among them: judging a value means
/// reading it, which is the Touch ID this sheet asks for.
struct CheckSettingsSheet: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions

    private var unchecked: [VaultSecret] {
        model.vaultListing?.uncheckedFromEnv ?? []
    }

    private var byGroup: [(String, Int)] {
        Dictionary(grouping: unchecked, by: \.group).map { ($0.key, $0.value.count) }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text("Move the settings out of these profiles?").font(Win.cardTitle)
                Text("jit reads the \(unchecked.count) entries below and moves the ones that aren't secrets out of the vault, "
                    + "into plain settings. The secrets, and names that look like one, stay. Files keep working.")
                    .font(Win.sub).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            AppPlainCard {
                CappedScroll(maxHeight: 240) {
                    ForEach(Array(byGroup.enumerated()), id: \.element.0) { index, item in
                        AppRow(
                            name: item.0,
                            fact: "\(item.1) \(item.1 == 1 ? "entry" : "entries") protected from a .env",
                            last: index == byGroup.count - 1
                        ) {}
                    }
                }
            }
            HStack(spacing: Win.s4) {
                Text("Touch ID follows, once.").font(Win.sub).foregroundStyle(.secondary)
                Spacer(minLength: Win.s5)
                Button("Cancel", action: actions.closeSheet).buttonStyle(AppButton()).keyboardShortcut(.cancelAction)
                Button("Move Out", action: actions.checkSettings).buttonStyle(AppButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .disabled(model.vaultBusy != nil)
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onExitCommand(perform: actions.closeSheet)
    }
}
