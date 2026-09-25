// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The move into the Secure Enclave, frames B and C of the "Vault key in
/// the Secure Enclave" mockup. It leads with the cost, then the three
/// promises, then the recovery file, which comes first: after the move the
/// key cannot follow the vault to another Mac, so the file is the only way
/// back from a lost one. Move Key waits for it (`RecoveryFile.ready`) and
/// is never greyed for any other reason.
struct VaultKeySheet: View {
    @ObservedObject var model: MenuModel
    let actions: SettingsActions

    @State private var showsCommand = false

    private var file: RecoveryFile {
        model.recoveryFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s3) {
                Text(Format.moveSheetTitle).font(Win.cardTitle)
                (Text(Format.moveSheetCost).fontWeight(.semibold).foregroundColor(.primary)
                    + Text(Format.moveSheetCostRest).foregroundColor(.secondary))
                    .font(Win.rowName.weight(.regular))
                    .fixedSize(horizontal: false, vertical: true)
            }
            box {
                ForEach(Array(Format.moveSheetPromises.enumerated()), id: \.offset) { index, promise in
                    promiseRow(promise.name, promise.fact, last: index == Format.moveSheetPromises.count - 1)
                }
            }
            box { recoveryRow }
            if showsCommand {
                Text(Format.moveSheetCommand)
                    .font(Win.command).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .padding(.horizontal, Win.s5).padding(.vertical, Win.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WindowSurface.verbatim, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
            }
            footer
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        // app-sheet-material: the window's own material, not macOS's default sheet.
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }

    /// A card inside the sheet: the rows, with no rule above them.
    private func box(@ViewBuilder _ rows: () -> some View) -> some View {
        VStack(spacing: 0) { rows() }
            .padding(.horizontal, Win.s4)
            .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
    }

    private func promiseRow(_ name: String, _ fact: String, last: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Win.s5) {
                Text("✓").font(Win.rowFact.weight(.bold)).foregroundStyle(Color(StatusMark.green))
                    .frame(width: 16).padding(.top, 2)
                VStack(alignment: .leading, spacing: Win.s1) {
                    Text(name).font(Win.rowName).fixedSize(horizontal: false, vertical: true)
                    Text(fact).font(Win.rowFact).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Win.s4)
            if !last {
                Rectangle().fill(WindowSurface.rowLine).frame(height: 1)
            }
        }
    }

    /// No file yet (B), a file that counts (C), or one that does not: the
    /// row says when, and how many secrets against the vault's, so a file
    /// older than recent changes shows it. Saving is the export the Vault
    /// window already has, returning here.
    @ViewBuilder private var recoveryRow: some View {
        if model.recoveryFileSaving {
            AppNoteRow(mark: .busy, name: "Saving the recovery file…", fact: Format.vaultKeyWaiting, last: true) {
                EmptyView()
            }
        } else if let failure = model.recoveryFileFailure {
            AppNoteRow(
                mark: .failed, name: "The recovery file was not saved",
                fact: "jit did not save it. Its own words are below.", verbatim: failure, last: true
            ) {
                saveButton("Save Recovery File…", primary: true)
            }
        } else {
            AppNoteRow(
                mark: .dot(Color(file.ready ? StatusMark.green : StatusMark.amber)),
                name: Format.recoveryFileName(file),
                fact: Format.recoveryFileFact(file, vault: model.cli?.vault?.secretsStored ?? 0),
                last: true
            ) {
                file.ready ? saveButton("Save Another…", primary: false) : saveButton("Save Recovery File…", primary: true)
            }
        }
    }

    /// The next step takes Return: saving, until there is a file that counts.
    @ViewBuilder private func saveButton(_ title: String, primary: Bool) -> some View {
        if primary {
            Button(title, action: actions.saveRecoveryFile).buttonStyle(AppButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
        } else {
            Button(title, action: actions.saveRecoveryFile).buttonStyle(AppButton())
        }
    }

    private var footer: some View {
        let ready = file.ready && !model.recoveryFileSaving
        return HStack(spacing: Win.s4) {
            Button(showsCommand ? "Hide what jit runs ˅" : "Show what jit runs ›") { showsCommand.toggle() }
                .buttonStyle(AppButton(kind: .plain))
            Spacer(minLength: Win.s5)
            if ready {
                Text("Touch ID follows.").font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            }
            Button("Cancel", action: actions.cancelVaultKeyMove).buttonStyle(AppButton(kind: .secondary))
                .keyboardShortcut(.cancelAction)
            if ready {
                // Return moves: it destroys nothing, and the reverse exists.
                Button("Move Key", action: actions.confirmVaultKeyMove).buttonStyle(AppButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Move Key", action: actions.confirmVaultKeyMove).buttonStyle(AppButton(kind: .secondary))
                    .disabled(true)
                    .opacity(0.45)
            }
        }
    }
}
