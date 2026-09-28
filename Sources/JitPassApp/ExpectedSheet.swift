// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Expected…: one question, leading with what changes, and a scope that
/// defaults to the one file (mockup: Decoy Bursts, section 3). A sheet, not
/// an alert, because of the scope choice.
struct ExpectedSheet: View {
    let burst: DecoyBurst
    let close: () -> Void
    let mark: (ExpectedReader) -> Void

    @State private var everyFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s2) {
                Text(Format.expectQuestion(burst)).font(Win.cardTitle)
                Text(Format.expectMessage).font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("", selection: $everyFile) {
                Text(Format.expectOneFile(burst)).tag(false)
                Text(Format.expectEveryFile).tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text(everyFile ? Format.expectEveryFileHint : Format.expectOneFileHint)
                .font(Win.sub).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Win.s4) {
                Spacer()
                Button("Cancel", action: close).buttonStyle(AppButton()).keyboardShortcut(.cancelAction)
                Button("Mark Expected") {
                    if let program = ExpectedReaders.program(of: burst.by) {
                        mark(ExpectedReader(program: program, file: everyFile ? nil : burst.file))
                    }
                }
                .buttonStyle(AppButton(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }
}
