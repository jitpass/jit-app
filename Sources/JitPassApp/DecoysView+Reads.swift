// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Decoys window's reads, as bursts, and its expected readers.
extension DecoysView {
    /// One row per burst: who read which file, how many times, when, and
    /// why they got a decoy. Expected ones come last, muted.
    func readsCard(_ bursts: [DecoyBurst]) -> some View {
        let programs = DecoyBurst.unexpectedPrograms(bursts)
        let untraced = DecoyBurst.untraced(bursts)
        let shown = Array(bursts.prefix(12))
        return AppCard(
            eyebrow: "Reads", eyebrowTint: Color(programs > 0 || untraced ? StatusMark.amber : StatusMark.green),
            title: Format.decoysProgramsTitle(programs, untraced: untraced),
            note: model.decoyExpected == nil ? Format.decoysReadsNote : Format.decoysReadsExpectNote
        ) {
            Button("Audit…", action: actions.openAudit).buttonStyle(AppButton(kind: .plain))
        } rows: {
            AppCardRows {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, burst in
                    AppRow(
                        name: burst.reader ?? "Reader not recorded",
                        detail: Format.decoyFileName(burst.file),
                        badge: burst.expected ? "expected" : nil,
                        fact: Format.decoyBurstFact(
                            burst,
                            cannotExpect: !burst.expected && !(burst.by.map(ExpectedReaders.canBeExpected) ?? true)
                        ),
                        last: index == shown.count - 1
                    ) {
                        if model.decoyExpected != nil, !burst.expected, let by = burst.by {
                            // A shell or an interpreter runs any script, so it
                            // is never offered: the fact line says why.
                            if ExpectedReaders.canBeExpected(program: by) {
                                Button("Expected…") { actions.askExpected(burst) }.buttonStyle(AppButton(kind: .quiet))
                            }
                        }
                    }
                    .opacity(burst.expected ? Design.Opacity.muted : 1)
                }
            }
        }
    }

    /// Where a mark is taken back later.
    func expectedCard(_ readers: [ExpectedReader]) -> some View {
        AppCard(
            eyebrow: "Expected readers",
            eyebrowTint: Color.secondary,
            title: Format.count(readers.count, "expected reader"),
            note: nil
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(readers.enumerated()), id: \.element.id) { index, reader in
                    AppRow(
                        name: Format.expectedReaderName(reader),
                        fact: Format.expectedReaderFact(reader),
                        last: index == readers.count - 1
                    ) {
                        Button("Not Expected") { actions.setExpected(reader, true) }.buttonStyle(AppButton(kind: .quiet))
                    }
                }
            }
        }
    }
}
