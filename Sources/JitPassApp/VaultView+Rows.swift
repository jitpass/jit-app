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
            note: Format.vaultSecretsNote
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
                        rowState(secret.path)
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

    /// What a row is waiting on, or why its last action failed: under the
    /// row, where the eye already is.
    @ViewBuilder func rowState(_ path: String) -> some View {
        if model.vaultBusy == path {
            RowState.waiting(Format.vaultWaiting(model.vaultBusyVerb, path: path)).padding(.top, Win.s2)
        } else if let message = model.vaultMessage, model.vaultFailedFor == path {
            RowState.failure(message).padding(.top, Win.s2)
        } else if let verb = model.vaultCancelled, model.vaultFailedFor == path {
            RowState.note(Format.vaultCancelled(verb)).padding(.top, Win.s2)
        }
    }

    /// A row's everyday verbs, then the rest behind its ⋯. Reveal is Hide
    /// on the row whose value is showing, at the same width so the row's
    /// buttons do not jog.
    @ViewBuilder func secretButtons(_ secret: VaultSecret) -> some View {
        // A sealed login is a tool's whole login: nothing to read or copy.
        if !secret.isSealedLogin {
            valueButtons(secret)
        }
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

    /// Reveal and Copy.
    private func valueButtons(_ secret: VaultSecret) -> some View {
        Group {
            let shown = model.vaultReveal?.path == secret.path
            Button {
                shown ? actions.hideReveal() : actions.reveal(secret.path)
            } label: {
                ZStack {
                    Text("Reveal").hidden()
                    Text(shown ? "Hide" : "Reveal")
                }
            }
            Button("Copy") { actions.copy(secret.path) }
        }
        .buttonStyle(AppButton(kind: .quiet))
        .disabled(model.vaultBusy != nil)
    }

    /// What the row's ⋯ holds: nothing used every day, Delete last and apart.
    /// A sealed login keeps Delete alone: jit refuses a set, keeps it no
    /// history, and it comes out by its unwrap or sign-out.
    @ViewBuilder func secretMenu(_ secret: VaultSecret) -> some View {
        if !secret.isSealedLogin {
            Button("Replace…") { actions.openSheet(replaceSheet(secret)) }
            Button("History…") { actions.openSheet(.history(path: secret.path)) }
            if !secret.isLinked, model.vaultSettings != nil {
                Button("Move Out of Vault…") { actions.openSheet(.moveOut(paths: [secret.path])) }
            }
            Divider()
        }
        Button("Delete…") { actions.delete([secret.path]) }
    }

    /// Right-click: the row's two buttons, then its ⋯.
    @ViewBuilder func rowMenu(_ secret: VaultSecret) -> some View {
        if !secret.isSealedLogin {
            if model.vaultReveal?.path == secret.path {
                Button("Hide", action: actions.hideReveal)
            } else {
                Button("Reveal for \(StatusItemController.revealSeconds)s") { actions.reveal(secret.path) }
            }
            Button("Copy to Clipboard") { actions.copy(secret.path) }
            Divider()
        }
        secretMenu(secret)
    }

    /// The header's ⋯: the profile's verbs that are not Add.
    func profileMenu(_ group: VaultGroup) -> some View {
        Menu {
            Button("Link 1Password…") { actions.openSheet(.link(group: group.name, replacing: nil)) }
            Divider()
            if group.secrets.isEmpty {
                // Settings only: `vault rm` has nothing to delete, so the
                // profile itself goes, through jit's own plan for it.
                Button("Delete Profile…") { actions.deleteProfile(group.name) }
            } else {
                Button("Delete Profile…") { actions.delete(group.secrets.map(\.path)) }
            }
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
            // All settings: they keep no origin, only who names them.
            // Other profiles only: a profile naming its own settings says nothing.
            let users = Set(settings(group).flatMap(\.usedBy)).subtracting([group.name]).sorted()
            if !users.isEmpty {
                parts.append("used by " + users.joined(separator: ", "))
            }
        } else if let used = Format.vaultUsedBy(profileUsers(group)) {
            // No file on record, but a profile names them: that is where
            // they are used, which is what "set by hand" failed to say.
            parts.append(used)
        } else if group.secrets.allSatisfy({ $0.origin == nil }) {
            parts.append("set by hand")
        } else {
            parts.append("from several files")
        }
        return parts.joined(separator: " · ")
    }

    /// The profiles, in any project folder, that name this profile's secrets.
    func profileUsers(_ group: VaultGroup) -> [VaultSecretUser] {
        model.vaultUsers?.profiles(for: group.secrets.map(\.path)) ?? []
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
                        // A value stays one line; a secret's facts may take
                        // two, so "used by" is never cut at the window's size.
                        Text(fact).font(factMono ? Win.command : Win.rowFact)
                            .foregroundStyle(factTint ?? .secondary)
                            .lineLimit(factMono ? 1 : 2).truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true).help(fact)
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

/// A row's (or the header's) one line of state: a spinner for a Touch ID
/// being waited on, a red dot beside a failure in the label colour, a
/// green dot beside a success.
enum RowState {
    static func waiting(_ text: String) -> some View {
        HStack(spacing: Win.s3) {
            ProgressView().controlSize(.mini)
            Text(text).font(Win.rowFact).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// jit's words, or the plain sentence for a refusal only the installed
    /// JitPass can get past (VaultFailure); jit's own words in the tooltip.
    static func failure(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Win.s3) {
            StateDot(tint: Color(StatusMark.red))
            Text(VaultFailure.plain(text)).font(Win.rowFact).foregroundStyle(.primary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true).help(text)
        }
    }

    /// A plain word under the row, with a grey dot that ties it to the
    /// row: nothing went wrong.
    static func note(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Win.s3) {
            StateDot(tint: Color.secondary)
            Text(text).font(Win.rowFact).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    static func done(_ text: String) -> some View {
        HStack(spacing: Win.s3) {
            StateDot(tint: Color(StatusMark.green))
            Text(text).font(Win.rowFact).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
