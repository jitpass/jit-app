// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// New AI Job (JobSheet-redesign.html, frames C1 to C3; frames D and E of
/// the Jobs mockup for a proposal and a refusal): one sheet, read top to
/// bottom before a Touch ID is spent. It starts from a profile, as New
/// Grant does, and the profile's folder is where the job runs, so a folder
/// is chosen only for a global profile. Runs offers the scripts in that
/// folder. What the service resolved (the program, the secrets, the file
/// count, a refusal) comes from `job_preview`, the checks approval runs, so
/// this sheet can never promise what approval would then refuse. An agent's
/// proposal opens the same sheet filled in, its words shown as theirs.
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
                    Text(Format.jobSheetTitle(model.jobDraft)).font(Win.cardTitle)
                    sentence
                }
                rows
                    .opacity(model.jobBusy ? 0.55 : 1)
                    .disabled(model.jobBusy)
                if let refusal = model.jobPreview?.refusal {
                    AppNoteRow(mark: .failed, name: Format.jobRefusedName, verbatim: refusal, last: true) { EmptyView() }
                } else if let error = model.jobError {
                    AppNoteRow(mark: .failed, name: Format.jobFailure, verbatim: error, last: true) { EmptyView() }
                } else if model.jobPreview != nil, model.jobDraft.isComplete {
                    notes
                }
                footer
            }
            .padding(Win.s6)
        }
        .frame(width: Win.sheetWide)
        // app-sheet-material is the window's own material; left unset, macOS
        // paints its default sheet, warmer than every window it drops from.
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onChange(of: model.jobDraft.folder) { _, _ in actions.preview() }
        .onChange(of: model.jobDraft.command) { _, _ in actions.preview() }
        .onChange(of: model.jobDraft.profile) { _, _ in actions.preview() }
        .onChange(of: model.jobDraft.ask) { _, _ in actions.preview() }
        .onAppear(perform: actions.preview)
    }

    // MARK: - The sentence

    private var sentence: some View {
        let parts = model.jobDraft.sentence(program: model.jobPreview?.program, secrets: model.jobPreview?.secrets?.count)
        var text = Text("")
        for part in parts {
            text = text + piece(part) // swiftlint:disable:this shorthand_operator
        }
        return text.font(Design.Text.row).fixedSize(horizontal: false, vertical: true)
    }

    private func piece(_ part: GrantDraft.Part) -> Text {
        switch part {
        case let .text(s): Text(s).foregroundStyle(.secondary)
        case let .value(s): Text(s).fontWeight(.semibold).foregroundStyle(.primary)
        case let .blank(s): Text(s).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Rows

    /// Only what is true yet: the profile first, then what runs, then what
    /// the service resolved. Nothing claims a folder or its secrets before
    /// there is one.
    private var rows: some View {
        let draft = model.jobDraft
        return VStack(alignment: .leading, spacing: Win.s5) {
            if let why = draft.proposal?.why, !why.isEmpty {
                row("Why") {
                    Text("“\(why)”").font(Win.sub).fixedSize(horizontal: false, vertical: true)
                    hint(Format.proposalWhyHint(draft.proposal))
                }
            }
            if draft.profile == nil, draft.folder.isEmpty {
                row("Profile") { JobProfileList(model: model, actions: actions) }
            } else {
                profileRow
                folderRow
                if !draft.folder.isEmpty {
                    row("Runs") { JobRunsPicker(model: model) }
                }
                if draft.isComplete || !draft.argv.isEmpty {
                    if let secrets = model.jobPreview?.secrets, !secrets.isEmpty {
                        row("Secrets") { secretRows(secrets) }
                    }
                    askRow
                    if draft.editing == nil {
                        nameRow
                    }
                }
            }
        }
    }

    /// The chosen profile.
    private var profileRow: some View {
        let draft = model.jobDraft
        return row("Profile") {
            HStack(spacing: Win.s4) {
                Text(draft.profile ?? "No profile").font(Win.rowName)
                Spacer(minLength: Win.s4)
                if draft.proposal == nil {
                    Button("Change…", action: actions.changeProfile).buttonStyle(AppButton(kind: .quiet))
                }
            }
        }
    }

    /// Where the script is: the profile's folder until a folder inside it
    /// is chosen. The job runs there and fingerprints only that folder. A
    /// global profile names none, so one is chosen before anything else.
    private var folderRow: some View {
        let draft = model.jobDraft
        return row("Folder") {
            HStack(spacing: Win.s4) {
                if draft.folder.isEmpty {
                    Text("None yet").font(Win.sub).foregroundStyle(.secondary)
                } else {
                    Text(Format.home(draft.folder)).font(Design.Text.command).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: Win.s4)
                if draft.proposal == nil {
                    Button("Choose…", action: actions.chooseFolder).buttonStyle(AppButton(kind: .quiet))
                }
            }
            hint(Format.jobFolderHint(draft))
        }
    }

    /// The name AI tools call it by, made from the script until typed over.
    private var nameRow: some View {
        row("Name") {
            AppTextField(placeholder: "", text: nameBinding, width: 240)
            hint(Format.jobNameHint)
        }
    }

    /// Typing a name stops it following the script.
    private var nameBinding: Binding<String> {
        Binding(
            get: { model.jobDraft.name },
            set: { name in
                model.jobDraft.name = name
                model.jobDraft.nameSuggested = false
            }
        )
    }

    /// The profile's secrets as the service resolved them, each with its
    /// Hidden/Shown switch. Hidden is the default; Shown is for values that
    /// appear in what the script prints and are not keys.
    private func secretRows(_ secrets: [JobSecretStatus]) -> some View {
        VStack(alignment: .leading, spacing: Win.s3) {
            VStack(spacing: 0) {
                ForEach(Array(secrets.enumerated()), id: \.element.name) { index, secret in
                    HStack(spacing: Win.s5) {
                        // A key name is mono, as the system reserves it for.
                        Text(secret.name).font(Design.Text.command).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: Win.s5)
                        AppSegmented(
                            items: [AppSegmentItem(value: false, title: "Hidden"), AppSegmentItem(value: true, title: "Shown")],
                            selection: shownBinding(secret.name)
                        )
                    }
                    .padding(.vertical, Win.s4)
                    if index < secrets.count - 1 {
                        Rectangle().fill(WindowSurface.rowLine).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, Win.s5)
            .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
            hint(Format.jobShownHint)
        }
    }

    private var askRow: some View {
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

    private func row(_ label: String, @ViewBuilder _ content: @escaping () -> some View) -> some View {
        JobSheetRow(label: label, content: content)
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
                Text(model.jobCancelled ? Format.jobTouchIDCancelled
                    : Format.jobFooter(model.jobDraft, preview: model.jobPreview, checking: model.jobPreviewBusy))
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
            Button(model.jobDraft.editing == nil ? "Approve with Touch ID" : "Approve Changes with Touch ID", action: actions.approve)
                .buttonStyle(AppButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
                .opacity(ready ? 1 : 0.45)
        }
    }
}

/// A sheet row: the label in its column, the content beside it. New
/// Grant's shape, so the two sheets line up.
struct JobSheetRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: Win.s5) {
            Text(label).font(Win.sub).foregroundStyle(.secondary)
                .frame(width: 62, alignment: .trailing).padding(.top, 4)
            VStack(alignment: .leading, spacing: Win.s3) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct JobSheetActions {
    var preview: () -> Void = {}
    var chooseProfile: (DiscoveredProfile) -> Void = { _ in }
    var changeProfile: () -> Void = {}
    var chooseFolder: () -> Void = {}
    var addFolder: () -> Void = {}
    var approve: () -> Void = {}
    var cancel: () -> Void = {}
    var dismiss: () -> Void = {}
}
