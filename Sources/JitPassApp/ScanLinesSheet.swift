// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// One file's flagged lines. A row carries one fact, never six, so the
/// list a file with several findings used to print under its row lives
/// here: the sheet belongs to the window it dropped from, and it carries
/// content, which is what makes it a sheet rather than an alert.
struct ScanLinesSheet: View {
    let group: ScanFileGroup
    let actions: ScanActions
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            HStack(alignment: .top, spacing: Win.s5) {
                StateDot(tint: Severity.color(group.severity)).padding(.top, 5)
                VStack(alignment: .leading, spacing: Win.s1) {
                    Text(Format.linesTitle(group)).font(Win.cardTitle)
                    Text(Format.home(group.filePath)).font(Win.command).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(group.findings.enumerated()), id: \.element.id) { index, finding in
                        // The name is the token's (or the scanner's sentence),
                        // the detail the line, the fact where it sits: "in Claude
                        // Code's transcripts" for a cache file, the finding's
                        // kind otherwise.
                        AppRow(
                            name: finding.shortEvidence,
                            detail: finding.line.map { "line \($0)" },
                            fact: finding.foundIn.map { "in " + $0 } ?? (finding.vendorName == nil ? nil : finding.typeLabel),
                            last: index == group.findings.count - 1
                        ) {
                            Button("Open") { actions.open(group.filePath, finding.line) }
                                .buttonStyle(AppButton(kind: .plain))
                        }
                    }
                }
                .padding(.horizontal, Win.s5)
                .padding(.vertical, Win.s2)
            }
            .frame(maxHeight: 280)
            .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
            HStack(spacing: Win.s4) {
                Spacer()
                Button("Reveal in Finder") { actions.reveal(group.filePath) }.buttonStyle(AppButton())
                Button("Done", action: close).buttonStyle(AppButton(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
    }
}
