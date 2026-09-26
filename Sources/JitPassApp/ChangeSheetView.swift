// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// "What Changed…": what a Redact or a Protect did, as rows
/// (docs/design/mockups/WhatChanged-sheet.html). The result in one line,
/// what was not touched, one row per file, the promises kept, what was
/// left. jit's words are on screen only under a failure; its full report
/// is one disclosure away, never the first thing read.
struct ChangeSheetView: View {
    let sheet: ChangeSheet
    let reveal: (String) -> Void
    let copyPath: (String) -> Void
    let undo: () -> Void
    let close: () -> Void

    @State private var allFiles = false
    @State private var showReport = false

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(sheet.title).font(Win.cardTitle).fixedSize(horizontal: false, vertical: true)
                Text(sheet.sentence).font(Win.sub).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let failure = sheet.notes.first(where: { $0.mark == .failed }) {
                AppPlainCard { note(failure, last: true) }
            }
            if !sheet.files.isEmpty {
                AppPlainCard { files }
            }
            let rest = sheet.notes.filter { $0.mark != .failed }
            if !rest.isEmpty {
                AppPlainCard {
                    ForEach(Array(rest.enumerated()), id: \.offset) { index, item in
                        note(item, last: index == rest.count - 1)
                    }
                }
            }
            if showReport, !sheet.report.isEmpty {
                ScrollView {
                    Text(sheet.report).font(Win.command).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .padding(.horizontal, Win.s5).padding(.vertical, Win.s4)
                .background(WindowSurface.verbatim, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
            }
            HStack(spacing: Win.s4) {
                if !sheet.report.isEmpty {
                    Button(showReport ? "Hide jit's report" : "Show jit's report ›") { showReport.toggle() }
                        .buttonStyle(AppButton(kind: .plain))
                }
                Spacer(minLength: Win.s5)
                if !sheet.undo.isEmpty {
                    Button("Undo", action: undo).buttonStyle(AppButton())
                }
                Button("Done", action: close).buttonStyle(AppButton(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        // app-sheet-material: the window's own material, not macOS's default sheet.
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onExitCommand(perform: close)
    }

    /// The first files, then the rest folded into one row until asked for:
    /// a Redact can touch dozens of transcripts.
    @ViewBuilder private var files: some View {
        let folds = !allFiles && sheet.files.count > ChangeSheet.shown + 1
        let shown = folds ? Array(sheet.files.prefix(ChangeSheet.shown)) : sheet.files
        ForEach(Array(shown.enumerated()), id: \.offset) { index, file in
            AppRow(
                name: Format.fileName(file.path),
                detail: Format.parentFolder(file.path),
                fact: file.fact,
                last: !folds && index == shown.count - 1
            ) {
                Menu {
                    Button("Reveal in Finder") { reveal(file.path) }
                    Button("Copy Path") { copyPath(file.path) }
                } label: {
                    Text("···")
                }
                .menuStyle(.button)
                .buttonStyle(AppButton())
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        if folds {
            let more = sheet.files.count - shown.count
            AppRow(name: "and \(more) more file" + (more == 1 ? "" : "s"), last: true) {
                Button("Show All") { allFiles = true }.buttonStyle(AppButton(kind: .plain))
            }
        }
    }

    private func note(_ item: ChangeSheet.Note, last: Bool) -> some View {
        AppNoteRow(mark: mark(item.mark), name: item.name, fact: item.fact, verbatim: item.verbatim, last: last) {
            EmptyView()
        }
    }

    private func mark(_ mark: ChangeMark) -> AppNoteRow<EmptyView>.Mark {
        switch mark {
        case .done: .done
        case .left: .dot(Color(StatusMark.amber))
        case .failed: .failed
        }
    }
}
