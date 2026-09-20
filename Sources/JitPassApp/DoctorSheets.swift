// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// What the Doctor window has open over it: the one question before a
/// destructive fix, the profiles review, or the output of an action whose
/// output was the whole request. All three are sheets on the window that
/// raised them, never windows of their own.
enum DoctorSheet: Identifiable, Equatable {
    case review
    case confirm(DoctorConfirmRequest)
    case output(DoctorOutput)

    var id: String {
        switch self {
        case .review: "review"
        case let .confirm(request): "confirm:" + request.id.uuidString
        case let .output(output): "output:" + output.id.uuidString
        }
    }
}

/// A destructive action waiting for its one answer, with the files it is
/// about named the way the row named them.
struct DoctorConfirmRequest: Identifiable, Equatable {
    var id = UUID()
    var confirmation: DoctorConfirmation
    /// What the row said about the file, carried through so the sheet and
    /// the row agree on why this is being deleted.
    var fact: String?
}

struct DoctorOutput: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var text: String
}

/// The one question before a destructive fix.
///
/// It leads with what changes, in the reader's words. It used to lead
/// with the command line: "This runs: jit migrate forget ~/…", in the one
/// dialog that exists to explain, in a 260-point alert where the path
/// wrapped mid-word. The command is still here, one click away, because a
/// tool that can be audited is the point; it is just no longer the first
/// thing read.
struct DoctorConfirmSheet: View {
    let request: DoctorConfirmRequest
    let answer: (Bool) -> Void
    @State private var showingCommand = false

    private var confirmation: DoctorConfirmation {
        request.confirmation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.five) {
            Text(confirmation.question).font(Design.Text.windowHead).foregroundStyle(Design.Label.primary)
            if !confirmation.files.isEmpty {
                VStack(alignment: .leading, spacing: Design.Space.three) {
                    ForEach(confirmation.files.prefix(4), id: \.self) { file in
                        DoctorFileChip(path: file, fact: confirmation.files.count == 1 ? request.fact : nil)
                    }
                    if confirmation.files.count > 4 {
                        Text("and \(confirmation.files.count - 4) more")
                            .font(Design.Text.rowFact).foregroundStyle(Design.Label.secondary)
                    }
                }
            }
            Text(confirmation.lead).font(Design.Text.row).foregroundStyle(Design.Label.primary)
                .fixedSize(horizontal: false, vertical: true)
            // What jit refuses to do is what makes this safe to press, so
            // the checks read as promises rather than warnings.
            if !confirmation.checks.isEmpty {
                VStack(alignment: .leading, spacing: Design.Space.three) {
                    ForEach(confirmation.checks, id: \.self) { check in
                        HStack(alignment: .top, spacing: Design.Space.four) {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(StatusMark.green))
                            Text(check).font(Design.Text.cardNote).foregroundStyle(Design.Label.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if showingCommand {
                Text(confirmation.command)
                    .font(Design.Text.commandSmall)
                    .foregroundStyle(Design.Label.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Design.Space.four)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous).fill(Design.Surface.verbatim)
                    )
            }
            HStack(spacing: Design.Space.four) {
                // One click from the exact line, never the first thing
                // read. "Nothing asks again" is not here: it is true of
                // every one of these, so it distinguishes nothing.
                Button(showingCommand ? "Hide what jit runs" : "Show what jit runs") { showingCommand.toggle() }
                    .buttonStyle(.link).font(Design.Text.button)
                Spacer(minLength: Design.Space.four)
                if confirmation.presence {
                    Text("Touch ID follows.").font(Design.Text.rowFact).foregroundStyle(Design.Label.secondary)
                }
                Button("Cancel") { answer(false) }.keyboardShortcut(.cancelAction).font(Design.Text.button)
                // Destructive, and never the default: Return must not
                // delete, so nothing here takes .defaultAction.
                Button(confirmation.button) { answer(true) }
                    .buttonStyle(.borderedProminent).tint(Color(StatusMark.red)).font(Design.Text.button)
            }
        }
        .padding(Design.Space.six)
        .frame(width: Design.Sheet.wide)
    }
}

/// A file as the row showed it: its name, the folder it sits in, and what
/// was true of it.
struct DoctorFileChip: View {
    let path: String
    var fact: String?

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.five) {
            Image(systemName: "doc").font(.system(size: Design.Size.glyph * 0.8))
                .foregroundStyle(Design.Label.primary).opacity(0.5).frame(width: Design.Size.glyph)
            VStack(alignment: .leading, spacing: Design.Space.one) {
                Text((path as NSString).lastPathComponent)
                    .font(Design.Text.rowName).foregroundStyle(Design.Label.primary)
                Text((path as NSString).deletingLastPathComponent)
                    .font(Design.Text.commandSmall).foregroundStyle(Design.Label.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if let fact {
                    Text(fact).font(Design.Text.rowFact).foregroundStyle(Design.Label.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, Design.Space.one)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Design.Space.four)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous).fill(Design.Surface.card))
    }
}

/// The output of an action whose output was the whole request (a
/// comparison, a service log). In the window's own type on the window's
/// own material: it replaces a black monospaced pane that opened as a
/// separate modal window over the app.
struct DoctorOutputSheet: View {
    let output: DoctorOutput
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.five) {
            Text(output.title).font(Design.Text.windowHead).foregroundStyle(Design.Label.primary)
            ScrollView {
                Text(output.text.isEmpty ? "jit printed nothing." : output.text)
                    .font(Design.Text.command)
                    .foregroundStyle(Design.Label.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 320)
            HStack(spacing: Design.Space.four) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output.text, forType: .string)
                }
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction).font(Design.Text.button)
            }
        }
        .padding(Design.Space.six)
        .frame(width: Design.Sheet.wide)
    }
}
