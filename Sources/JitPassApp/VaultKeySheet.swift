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

    /// The one button Return presses (`VaultKeySheetDefault`).
    private var returnKey: VaultKeySheetDefault {
        .pick(file, saving: model.recoveryFileSaving, saveFailed: model.recoveryFileFailure != nil)
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
                    .frame(width: Design.Size.glyph).padding(.top, Design.Space.one)
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

    /// No file yet (B), a file that counts (C), or one jit would refuse:
    /// the row says when, and jit's verdict on it. Saving is the export
    /// the Vault window already has, returning here.
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
                saveButton("Save Recovery File…")
            }
        } else {
            AppNoteRow(
                mark: .dot(Color(file.ready ? StatusMark.green : StatusMark.amber)),
                name: Format.recoveryFileName(file),
                fact: Format.recoveryFileFact(file),
                last: true
            ) {
                saveButton(file.ready ? "Save Another…" : "Save Recovery File…")
            }
        }
    }

    /// Saving takes Return when it is the next step (`returnKey`), and is
    /// the quiet kind otherwise.
    @ViewBuilder private func saveButton(_ title: String) -> some View {
        if returnKey == .saveRecoveryFile {
            Button(title, action: actions.saveRecoveryFile).buttonStyle(AppButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
        } else {
            Button(title, action: actions.saveRecoveryFile).buttonStyle(AppButton())
        }
    }

    private var footer: some View {
        let enabled = VaultKeySheetDefault.moveEnabled(file, saving: model.recoveryFileSaving)
        return HStack(spacing: Win.s4) {
            Button(showsCommand ? "Hide what jit runs ˅" : "Show what jit runs ›") { showsCommand.toggle() }
                .buttonStyle(AppButton(kind: .plain))
            Spacer(minLength: Win.s5)
            if enabled {
                Text("Touch ID follows.").font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            }
            Button("Cancel", action: actions.cancelVaultKeyMove).buttonStyle(AppButton(kind: .secondary))
                .keyboardShortcut(.cancelAction)
            if returnKey == .moveKey {
                // Return moves: it destroys nothing, and the reverse exists.
                Button("Move Key", action: actions.confirmVaultKeyMove).buttonStyle(AppButton(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            } else {
                // Pressable after a failed save when an earlier file still
                // counts, but Return belongs to the save row then.
                Button("Move Key", action: actions.confirmVaultKeyMove).buttonStyle(AppButton(kind: .secondary))
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : Design.Opacity.disabled)
            }
        }
    }
}
