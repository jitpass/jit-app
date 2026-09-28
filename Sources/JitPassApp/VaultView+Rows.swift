// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The profile's secrets card and each secret's row, split out of
/// VaultView so the window's layout reads on its own.
extension VaultView {
    func secretsCard(_ group: VaultGroup) -> some View {
        AppCard(
            eyebrow: "In the vault", eyebrowTint: Color(StatusMark.green),
            title: Format.count(group.secrets.count, "secret"),
            note: "Reading one takes Touch ID or a grant."
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(group.secrets.enumerated()), id: \.element.path) { index, secret in
                    VaultRow(
                        name: secret.name, fact: Format.vaultSecretFact(secret),
                        factTint: secret.expires.map { $0 > Date() } == false ? Color(StatusMark.amber) : nil,
                        last: index == group.secrets.count - 1
                    ) {
                        if let reveal = model.vaultReveal, reveal.path == secret.path {
                            revealLine(reveal)
                        }
                    } actions: {
                        secretButtons(secret)
                    }
                    .contextMenu { rowMenu(secret) }
                }
            }
        }
    }

    /// The value, its countdown. Never selectable: the reveal is for
    /// reading, the clipboard path is Copy.
    private func revealLine(_ reveal: VaultReveal) -> some View {
        HStack(alignment: .top, spacing: Win.s4) {
            Text(reveal.text)
                .font(Win.command)
                .lineLimit(6)
                .textSelection(.disabled)
                .padding(.horizontal, Win.s3).padding(.vertical, Win.s1)
                .background(Color(StatusMark.amber).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.box, style: .continuous))
            Text("\(reveal.secondsLeft)s").font(Win.rowFact).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.top, Win.s2)
    }

    /// A row's everyday verbs, then the rest behind its ⋯. Reveal is Hide
    /// on the row whose value is showing.
    @ViewBuilder func secretButtons(_ secret: VaultSecret) -> some View {
        Group {
            if model.vaultReveal?.path == secret.path {
                Button("Hide", action: actions.hideReveal)
            } else {
                Button("Reveal") { actions.reveal(secret.path) }
            }
            Button("Copy") { actions.copy(secret.path) }
        }
        .buttonStyle(AppButton(kind: .quiet))
        .disabled(model.vaultBusy != nil)
        Menu {
            secretMenu(secret)
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton(kind: .quiet))
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.vaultBusy != nil)
    }

    /// What the row's ⋯ holds: nothing used every day, Delete last and apart.
    @ViewBuilder func secretMenu(_ secret: VaultSecret) -> some View {
        Button("Replace…") { actions.openSheet(replaceSheet(secret)) }
        Button("History…") { actions.openSheet(.history(path: secret.path)) }
        if !secret.isLinked, model.vaultSettings != nil {
            Button("Move Out of Vault…") { actions.openSheet(.moveOut(paths: [secret.path])) }
        }
        Divider()
        Button("Delete…") { actions.delete([secret.path]) }
    }

    /// Right-click: the row's two buttons, then its ⋯.
    @ViewBuilder func rowMenu(_ secret: VaultSecret) -> some View {
        Button("Reveal for \(StatusItemController.revealSeconds)s") { actions.reveal(secret.path) }
        Button("Copy to Clipboard") { actions.copy(secret.path) }
        Divider()
        secretMenu(secret)
    }

    /// The header's ⋯: the profile's verbs that are not Add.
    func profileMenu(_ group: VaultGroup) -> some View {
        Menu {
            Button("Link 1Password…") { actions.openSheet(.link(group: group.name, replacing: nil)) }
            Divider()
            Button("Delete Profile…") { actions.delete(group.secrets.map(\.path)) }
                .disabled(group.secrets.isEmpty)
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton())
        .menuIndicator(.hidden)
        .fixedSize()
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

/// A vault row: the name in mono, one fact under it (mono for a
/// setting's value), whatever the row shows below that (a revealed
/// value), and its verbs pushed right. AppRow's shape, with room for
/// the line under the fact that AppRow does not have.
struct VaultRow<Below: View, Actions: View>: View {
    let name: String
    var fact: String?
    var factMono = false
    var factTint: Color?
    var last = false
    @ViewBuilder var below: () -> Below
    @ViewBuilder var actions: () -> Actions

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Win.s5) {
                VStack(alignment: .leading, spacing: Win.s1) {
                    Text(name).font(Design.Text.command.weight(.medium))
                        .lineLimit(1).truncationMode(.middle).help(name)
                    if let fact, !fact.isEmpty {
                        Text(fact).font(factMono ? Win.command : Win.rowFact)
                            .foregroundStyle(factTint ?? .secondary)
                            .lineLimit(1).truncationMode(.tail).help(fact)
                    }
                    below()
                }
                Spacer(minLength: Win.s5)
                HStack(spacing: Win.s3) { actions() }
            }
            .padding(.vertical, Win.s4)
            .padding(.horizontal, Win.s3)
            .background(hovering ? WindowSurface.hover : .clear)
            .clipShape(RoundedRectangle(cornerRadius: Win.segment, style: .continuous))
            .onHover { hovering = $0 }
            if !last {
                Rectangle().fill(WindowSurface.rowLine).frame(height: 1)
            }
        }
    }
}

extension VaultRow where Below == EmptyView {
    init(
        name: String, fact: String?, factMono: Bool = false, last: Bool = false,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.init(name: name, fact: fact, factMono: factMono, factTint: nil, last: last, below: { EmptyView() }, actions: actions)
    }
}
