// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// New Grant: the sentence the disclosed Touch ID will ask, filled in one
/// blank at a time (GrantDraft). One sheet, not a wizard: the whole
/// decision is read before a Touch ID is spent. No folder is ever chosen;
/// every profile on the Mac is listed, filterable, with its folder under
/// its name only so two similar ones can be told apart. The service does
/// the deciding: this sheet collects the request, exactly as `jit grant`
/// does, and the footer says what is still missing while the button is off.
struct GrantSheetView: View {
    @ObservedObject var model: MenuModel
    let actions: GrantActions

    @State private var draft = GrantDraft()

    /// A selected row: the brand green at the tint `accent-dim` samples.
    static let selection = Color(StatusMark.green).opacity(0.13)

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s3) {
                Text(Format.grantSheetTitle).font(Win.cardTitle)
                sentence
            }
            VStack(alignment: .leading, spacing: Win.s5) {
                coverRow
                if draft.cover == .oneProcess {
                    row("Process") { GrantProcessList(model: model, draft: $draft) }
                } else {
                    programRow
                }
                row("Profiles") { GrantProfileList(model: model, draft: $draft, actions: actions) }
                forRow
            }
            .opacity(model.grantBusy ? 0.55 : 1)
            .disabled(model.grantBusy)
            if let error = model.grantError {
                AppNoteRow(mark: .failed, name: Format.grantFailure, verbatim: error, last: true) { EmptyView() }
            } else {
                notes
            }
            footer
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        .onAppear {
            draft = model.grantPrefill ?? GrantDraft()
        }
        .onChange(of: draft.cover) { _, cover in
            // Until revoked belongs to every copy; one process keeps a
            // deadline. The default follows the cover.
            if cover == .oneProcess, draft.term == .untilRevoked {
                draft.term = .hours(8)
            } else if cover == .everyCopy, model.grantPrefill == nil {
                draft.term = .untilRevoked
            }
        }
        .onChange(of: draft.anchorPID) { _, pid in
            draft.anchorName = model.grantSessionRoots.first { $0.pid == pid }?.name
        }
    }

    // MARK: - The sentence

    private var sentence: some View {
        var text = Text("")
        for part in draft.sentence {
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

    private var coverRow: some View {
        row("Cover") {
            AppSegmented(
                items: [
                    AppSegmentItem(value: GrantDraft.Cover.oneProcess, title: "One process"),
                    AppSegmentItem(value: GrantDraft.Cover.everyCopy, title: "Every copy")
                ],
                selection: $draft.cover, fill: true
            )
            hint(Format.grantCoverHint(draft.cover))
        }
    }

    // MARK: Every copy

    private var programRow: some View {
        row("Program") {
            HStack(spacing: Win.s4) {
                AppTextField(placeholder: "name it", text: $draft.program)
                Text("under").font(Win.sub).foregroundStyle(.secondary)
                AppPopup(options: anchorOptions, selection: $draft.anchorPID)
            }
            if let text = Format.grantProgramHint(program: draft.programName, anchor: draft.anchorName ?? "", running: runningCopies) {
                hint(text)
            }
        }
    }

    private var anchorOptions: [AppSegmentItem<Int32?>] {
        [AppSegmentItem(value: Int32?.none, title: "choose an app")] +
            model.grantSessionRoots.map { AppSegmentItem(value: Int32?.some($0.pid), title: $0.name) }
    }

    /// How many copies of the named program run under the chosen app now.
    private var runningCopies: Int {
        guard let anchor = draft.anchorName, !draft.programName.isEmpty else {
            return 0
        }
        return model.grantAllProcesses.filter { $0.name == draft.programName && $0.under == anchor }.count
    }

    // MARK: For

    private var forRow: some View {
        row("For") {
            AppSegmented(
                items: draft.terms.map { AppSegmentItem(value: $0, title: GrantDraft.termLabel($0)) },
                selection: $draft.term
            )
            if let ends = Format.grantEnds(draft.term) {
                hint(ends)
            }
            if draft.cover == .oneProcess {
                hint(Format.grantOneProcessDeadline)
            }
        }
    }

    // MARK: - Notes and footer

    private var notes: some View {
        VStack(alignment: .leading, spacing: Win.s2) {
            Rectangle().fill(WindowSurface.separator).frame(height: 1).padding(.bottom, Win.s4)
            ForEach(Format.grantNotes(draft), id: \.self) { line in
                Text("• " + line).font(Win.rowFact).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        let ready = draft.isComplete && !model.grantBusy
        return HStack(spacing: Win.s4) {
            if model.grantBusy {
                ProgressView().controlSize(.small)
                Text(Format.grantFooterWaiting).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(draft.missing ?? Format.grantFooterReady).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Win.s5)
            Button("Cancel", action: actions.cancel).buttonStyle(AppButton(kind: .secondary))
                .keyboardShortcut(.cancelAction)
            Button("Grant with Touch ID") { actions.grant(draft) }.buttonStyle(AppButton(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!ready)
                .opacity(ready ? 1 : 0.45)
        }
    }
}

struct GrantActions {
    var reload: () -> Void = {}
    var chooseFolder: () -> Void = {}
    var openFindings: () -> Void = {}
    var grant: (GrantDraft) -> Void = { _ in }
    var cancel: () -> Void = {}
}
