// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// New AI Job (the Jobs mockup, frames C, D and E): one sheet, read top to
/// bottom before a Touch ID is spent. The command is shown as typed, in mono,
/// because it is the one thing to read and the thing the fingerprint
/// protects. What the service resolved (the program, the secrets, the file
/// count, a refusal) comes from `job_preview`, the same checks approval runs,
/// so this sheet can never promise what approval would then refuse. An
/// agent's proposal opens the same sheet pre-filled, with its words shown as
/// theirs and unchecked, and Dismiss where Cancel was.
struct JobSheetView: View {
    @ObservedObject var model: MenuModel
    let actions: JobSheetActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let proposal = model.jobDraft.proposal {
                WindowBanner(tint: Color(StatusMark.amber), text: Format.proposalBanner(proposal))
            }
            VStack(alignment: .leading, spacing: Win.s5) {
                VStack(alignment: .leading, spacing: Win.s3) {
                    Text(Format.jobSheetTitle).font(Win.cardTitle)
                    Text(Format.jobSentence(model.jobDraft, preview: model.jobPreview))
                        .font(Design.Text.row).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                rows
                    .opacity(model.jobBusy ? 0.55 : 1)
                    .disabled(model.jobBusy)
                if let refusal = model.jobPreview?.refusal {
                    AppNoteRow(mark: .failed, name: Format.jobRefusedName, verbatim: refusal, last: true) { EmptyView() }
                } else if let error = model.jobError {
                    AppNoteRow(mark: .failed, name: Format.jobFailure, verbatim: error, last: true) { EmptyView() }
                } else if model.jobPreview != nil {
                    notes
                }
                footer
            }
            .padding(Win.s6)
        }
        .frame(width: Win.sheetWide)
        .onChange(of: model.jobDraft.folder) { _, _ in actions.preview() }
        .onChange(of: model.jobDraft.command) { _, _ in actions.preview() }
        .onChange(of: model.jobDraft.profile) { _, _ in actions.preview() }
        .onChange(of: model.jobDraft.ask) { _, _ in actions.preview() }
        .onChange(of: model.jobDraft.output) { _, _ in actions.preview() }
        .onAppear(perform: actions.preview)
    }

    // MARK: - Rows

    private var rows: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            if let why = model.jobDraft.proposal?.why, !why.isEmpty {
                row("Why") {
                    Text("“\(why)”").font(Win.sub).fixedSize(horizontal: false, vertical: true)
                    hint(Format.proposalWhyHint(model.jobDraft.proposal))
                }
            }
            row("Name") {
                AppTextField(placeholder: "notion-guests", text: $model.jobDraft.name, width: 200)
            }
            row("Folder") {
                HStack(spacing: Win.s4) {
                    Text(model.jobDraft.folder.isEmpty ? "No folder chosen" : Format.home(model.jobDraft.folder))
                        .font(Win.command).foregroundStyle(model.jobDraft.folder.isEmpty ? .tertiary : .primary)
                        .lineLimit(1).truncationMode(.head)
                    Spacer(minLength: Win.s4)
                    Button("Choose…", action: actions.chooseFolder).buttonStyle(AppButton(kind: .secondary))
                }
            }
            row("Runs") {
                TextField(".venv/bin/python list_guest_users.py", text: $model.jobDraft.command)
                    .textFieldStyle(.plain).font(Win.command).appField()
                hint(Format.jobRunsHint(model.jobDraft, preview: model.jobPreview))
            }
            row("Secrets") { secrets }
            row("Asks") {
                AppSegmented(
                    items: [
                        AppSegmentItem(value: JobAsk.eachTime, title: "Each time"),
                        AppSegmentItem(value: JobAsk.never, title: "Never, until you remove it")
                    ],
                    selection: $model.jobDraft.ask
                )
                hint(Format.jobAskHint(model.jobDraft.ask))
            }
            row("Output") {
                HStack(spacing: Win.s4) {
                    Text(model.jobDraft.output.isEmpty ? "None" : Format.home(model.jobDraft.output))
                        .font(Win.command).foregroundStyle(model.jobDraft.output.isEmpty ? .tertiary : .primary)
                        .lineLimit(1).truncationMode(.head)
                    Spacer(minLength: Win.s4)
                    if !model.jobDraft.output.isEmpty {
                        Button("Clear") { model.jobDraft.output = "" }.buttonStyle(AppButton(kind: .plain))
                    }
                    Button("Choose…", action: actions.chooseOutput).buttonStyle(AppButton(kind: .secondary))
                }
                hint(Format.jobOutputHint)
            }
        }
    }

    /// The profile's secrets as the service resolved them, each with its
    /// Hidden/Shown switch. Hidden is the default; Shown is for values that
    /// appear in what the script prints and are not keys.
    @ViewBuilder private var secrets: some View {
        if model.jobProfiles.count > 1 {
            AppPopup(
                options: model.jobProfiles.map { AppSegmentItem(value: String?.some($0), title: $0) },
                selection: $model.jobDraft.profile
            )
        }
        if let resolved = model.jobPreview?.secrets, !resolved.isEmpty {
            AppCardRows {
                ForEach(Array(resolved.enumerated()), id: \.element.name) { index, secret in
                    AppRow(name: secret.name, last: index == resolved.count - 1) {
                        AppSegmented(
                            items: [AppSegmentItem(value: false, title: "Hidden"), AppSegmentItem(value: true, title: "Shown")],
                            selection: shownBinding(secret.name)
                        )
                    }
                }
            }
            .padding(.horizontal, Win.s4)
            .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
        }
        hint(Format.jobSecretsHint(model.jobDraft, preview: model.jobPreview, profiles: model.jobProfiles))
    }

    private func shownBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { model.jobDraft.shown.contains(name) },
            set: { shown in
                if shown {
                    model.jobDraft.shown.insert(name)
                } else {
                    model.jobDraft.shown.remove(name)
                }
            }
        )
    }

    private func row(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: Win.s5) {
            Text(label).font(Win.sub).foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing).padding(.top, 4)
            VStack(alignment: .leading, spacing: Win.s3) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(Win.rowFact).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Notes and footer

    private var notes: some View {
        VStack(alignment: .leading, spacing: Win.s2) {
            Rectangle().fill(WindowSurface.separator).frame(height: 1).padding(.bottom, Win.s4)
            ForEach(Format.jobNotes(model.jobDraft, preview: model.jobPreview), id: \.self) { line in
                Text("• " + line).font(Win.rowFact).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        let refused = model.jobPreview?.refusal != nil
        let ready = model.jobDraft.isComplete && model.jobPreview != nil && !refused && !model.jobBusy
        return HStack(spacing: Win.s4) {
            if model.jobBusy {
                ProgressView().controlSize(.small)
                Text(Format.jobFooterWaiting).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(Format.jobFooter(model.jobDraft, preview: model.jobPreview, checking: model.jobPreviewBusy))
                    .font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Win.s5)
            if model.jobDraft.proposal != nil {
                Button("Dismiss", action: actions.dismiss).buttonStyle(AppButton(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Cancel", action: actions.cancel).buttonStyle(AppButton(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
            }
            Button("Approve with Touch ID", action: actions.approve).buttonStyle(AppButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
                .opacity(ready ? 1 : 0.45)
        }
    }
}

struct JobSheetActions {
    var preview: () -> Void = {}
    var chooseFolder: () -> Void = {}
    var chooseOutput: () -> Void = {}
    var approve: () -> Void = {}
    var cancel: () -> Void = {}
    var dismiss: () -> Void = {}
}
