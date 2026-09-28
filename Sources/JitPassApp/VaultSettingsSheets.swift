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
            SheetState(model: model, owner: VaultCommandLabel.move(paths))
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

    /// Each profile and the names in `paths`, by profile.
    private func byGroup(_ paths: Set<String>) -> [(String, [String])] {
        Dictionary(grouping: unchecked.filter { paths.contains($0.path) }, by: \.group)
            .map { ($0.key, $0.value.map(\.name).sorted()) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            if let check = model.settingsCheck {
                checked(check)
            } else {
                unread
            }
            SheetState(model: model, owner: VaultCommandLabel.settingsCheck)
            footer
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onExitCommand(perform: close)
        .onAppear { model.settingsCheck = nil }
    }

    /// Before the check: the entries named like settings, which jit reads
    /// to decide, apart from the ones named like secrets, which stay. An
    /// older engine says nothing about names: one list, as before.
    @ViewBuilder private var unread: some View {
        let known = unchecked.allSatisfy { $0.nameLooksSecret != nil }
        let secrets = Set(unchecked.filter { $0.nameLooksSecret == true }.map(\.path))
        let candidates = Set(unchecked.map(\.path)).subtracting(secrets)
        VStack(alignment: .leading, spacing: Win.s1) {
            Text(Format.checkSettingsTitle(candidates.count, known: known)).font(Win.cardTitle)
            Text(Format.checkSettingsNote(candidates.count, known: known))
                .font(Win.sub).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if known {
            if !candidates.isEmpty {
                Text(Format.settingsLookHeading(candidates.count)).font(Win.eyebrow).foregroundStyle(.secondary)
                list(byGroup(candidates))
            }
            if !secrets.isEmpty {
                Text(Format.settingsStaysHeading(secrets.count)).font(Win.eyebrow).foregroundStyle(.secondary)
                list(byGroup(secrets))
            }
        } else {
            list(byGroup(Set(unchecked.map(\.path))))
        }
    }

    /// After it: jit's own verdict, two lists, before anything moves.
    @ViewBuilder private func checked(_ check: MigrateSettingsResult) -> some View {
        let verdict = check.verdict(unchecked: unchecked.map(\.path))
        let moves = MigrateSettingsResult.byProfile(verdict.moves)
        let stays = MigrateSettingsResult.byProfile(verdict.stays)
        VStack(alignment: .leading, spacing: Win.s1) {
            Text(Format.settingsCheckTitle(moves: verdict.moves.count)).font(Win.cardTitle)
            Text(Format.settingsCheckNote).font(Win.sub).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !moves.isEmpty {
            Text(Format.settingsMovesHeading(verdict.moves.count)).font(Win.eyebrow).foregroundStyle(.secondary)
            list(moves)
        }
        if !stays.isEmpty {
            Text(Format.settingsStaysHeading(verdict.stays.count)).font(Win.eyebrow).foregroundStyle(.secondary)
            list(stays)
        }
    }

    /// Up to five profiles show in full (about 50pt a row): a list this
    /// short never hides its last row behind a scroll. More scroll.
    private func list(_ groups: [(String, [String])]) -> some View {
        AppPlainCard {
            CappedScroll(maxHeight: Design.Sheet.listMax) {
                ForEach(Array(groups.enumerated()), id: \.element.0) { index, item in
                    AppRow(name: item.0, fact: item.1.joined(separator: ", "), wraps: true, last: index == groups.count - 1) {}
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Win.s4) {
            Text(model.settingsCheck == nil ? Format.settingsCheckFirstFoot : Format.settingsCheckThenFoot)
                .font(Win.sub).foregroundStyle(.secondary)
            Spacer(minLength: Win.s5)
            Button("Cancel", action: close).buttonStyle(AppButton()).keyboardShortcut(.cancelAction)
            if let check = model.settingsCheck {
                Button(check.moved.isEmpty ? "Keep Them All" : "Move These \(check.moved.count)", action: actions.checkSettings)
                    .buttonStyle(AppButton(kind: .primary)).keyboardShortcut(.defaultAction)
            } else {
                Button("Check Which Move…", action: actions.previewSettings)
                    .buttonStyle(AppButton(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        }
        .disabled(model.vaultBusy != nil)
    }

    private func close() {
        model.settingsCheck = nil
        actions.closeSheet()
    }
}

/// What the sheet's own command is doing, above its buttons: the Touch ID
/// wait, then why it failed, or that the person said no. The sheet stays
/// up on a failure, and the row it was for is behind it, so the sheet has
/// to say it; saying nothing read as a button that does nothing.
struct SheetState: View {
    @ObservedObject var model: MenuModel
    /// The label the sheet's command runs under (VaultCommandLabel): what
    /// another command left behind, a reveal's cancel, is not this sheet's.
    let owner: String

    var body: some View {
        if VaultCommandLabel.belongs(busy: model.vaultBusy, endedFor: model.vaultFailedFor, to: owner) {
            if model.vaultBusy != nil {
                RowState.waiting(Format.vaultWaiting(model.vaultBusyVerb, path: model.vaultBusy ?? ""))
            } else if let message = model.vaultMessage {
                RowState.failure(message)
            } else if let verb = model.vaultCancelled {
                RowState.note(Format.vaultCancelled(verb))
            }
        }
    }
}
