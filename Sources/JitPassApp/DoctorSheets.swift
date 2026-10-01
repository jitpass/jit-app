// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// What the Doctor window has open over it: the one question before a
/// destructive fix, the profiles review, or the service log's rows. All
/// three are sheets on the window that raised them, never windows of their
/// own.
enum DoctorSheet: Identifiable, Equatable {
    case review
    case confirm(DoctorConfirmRequest)
    case log(ServiceLog)

    var id: String {
        switch self {
        case .review: "review"
        case let .confirm(request): "confirm:" + request.id.uuidString
        case .log: "log"
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

/// Doctor › Show Log: what the service did, as rows (`jit service log
/// --format json`), newest first under a day label. Each row is a time, a
/// dot for its level (red failed, amber a reader worth a look), the
/// message, and the protected files it was about, name first. Copy keeps
/// the lines' words for a bug report.
struct ServiceLogSheet: View {
    let log: ServiceLog
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.five) {
            VStack(alignment: .leading, spacing: Design.Space.one) {
                Text("Service log").font(Win.cardTitle)
                Text(log.entries.isEmpty ? "The service hasn't written anything yet." : "What the service did, newest first.")
                    .font(Win.sub).foregroundStyle(.secondary)
            }
            if !log.entries.isEmpty {
                AppPlainCard {
                    CappedScroll(maxHeight: Design.Sheet.listMax) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                                Text(day.label).font(Win.rowFact).fontWeight(.semibold).foregroundStyle(.secondary)
                                    .padding(.top, Design.Space.three).padding(.bottom, Design.Space.two)
                                ForEach(Array(day.entries.enumerated()), id: \.offset) { _, entry in
                                    row(entry)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: Design.Space.four) {
                if !log.entries.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(log.plainText, forType: .string)
                    }
                    .buttonStyle(AppButton())
                }
                Spacer()
                Button("Done", action: done).buttonStyle(AppButton(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Design.Space.six)
        .frame(width: Design.Sheet.wide)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onExitCommand(perform: done)
    }

    /// Labelled in jit's own Gregorian calendar (`ServiceLog.day`).
    private var days: [ServiceLog.Day] {
        log.days(now: Date())
    }

    @ViewBuilder
    private func row(_ entry: ServiceLog.Entry) -> some View {
        if let raw = entry.raw {
            // A line jit didn't recognise (a panic, a stack frame): it is
            // evidence, so it stays exactly as written.
            Text(raw).font(Win.command).foregroundStyle(.secondary).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, Design.Space.two)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Design.Space.four) {
                Text(entry.time ?? "").font(Win.rowFact).monospacedDigit().foregroundStyle(.secondary)
                Circle().fill(dot(entry.level)).frame(width: Design.Size.dot, height: Design.Size.dot)
                VStack(alignment: .leading, spacing: Design.Space.one) {
                    Text(entry.message ?? "").font(Win.sub).fixedSize(horizontal: false, vertical: true)
                    if let about = subjects(entry) {
                        Text(about).font(Win.rowFact).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Design.Space.three)
        }
    }

    private func dot(_ level: String?) -> Color {
        switch level {
        case "risk": Color(StatusMark.red)
        case "warn": Color(StatusMark.amber)
        default: Color(nsColor: .secondaryLabelColor)
        }
    }

    /// The files a row is about: one by name and folder, several by count
    /// and their folders' names (they are usually all `.env`).
    private func subjects(_ entry: ServiceLog.Entry) -> String? {
        let paths = entry.subjects ?? []
        guard let first = paths.first else {
            return nil
        }
        if paths.count == 1 {
            return Format.fileName(first) + " · " + Format.parentFolder(first)
        }
        return "\(paths.count) protected files · " + NameList.capped(paths.map { Format.fileName(Format.parentFolder($0)) })
    }
}
