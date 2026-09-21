// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The scan window's agent-cache card: the copies grouped the way a
/// reader can act on them, one row per agent and cache area, where nine
/// hash-named file rows are not something anyone can act on.
extension ScanReportView {
    static let agentNote = "Copies of your vaulted secrets, and tokens found by their format, kept by an AI agent. "
        + "Protecting a file removes its copies; Clean Caches removes every vaulted copy after its own Touch ID; "
        + "Redact replaces a token with a marker, one-way, no Touch ID."

    /// Two kinds of row: a cache area holding copies of vaulted secrets
    /// (Clean Caches), and a file holding tokens found by format (Redact).
    func agentCard(_ groups: [ScanAgentGroup], shapes: [ScanFileGroup]) -> some View {
        let shapeCount = shapes.reduce(0) { $0 + $1.findings.count }
        return AppCard(
            eyebrow: Format.tierLabel(.agentCaches),
            eyebrowTint: Color(Self.tierTint(.agentCaches)),
            title: Format.tierTitle(.agentCaches, files: groups.count + shapes.count),
            note: Self.agentNote
        ) {
            if !groups.isEmpty {
                Button("Clean Caches…", action: actions.cleanCaches).buttonStyle(AppButton(kind: .secondary))
                    .disabled(model.toolsBusy != nil)
            }
            if !shapes.isEmpty {
                Button("Redact All \(shapeCount)…") {
                    actions.redact(
                        [],
                        [],
                        "\(shapeCount) token" + (shapeCount == 1 ? "" : "s") + " in \(shapes.count) file" + (shapes.count == 1 ? "" : "s"),
                        nil
                    )
                }
                .buttonStyle(AppButton(kind: .secondary)).disabled(model.toolsBusy != nil)
            }
        } rows: {
            AppCardRows {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    AppRow(
                        name: group.agent,
                        detail: group.area,
                        badge: isNew(group.findings) ? "new" : nil,
                        fact: agentDetail(group),
                        last: shapes.isEmpty && index == groups.count - 1
                    ) {
                        if let first = group.files.first {
                            Button("Open") { actions.open(first, nil) }.buttonStyle(AppButton())
                            Button("Reveal") { actions.reveal(first) }.buttonStyle(AppButton(kind: .plain))
                        }
                    }
                }
                ForEach(Array(shapes.enumerated()), id: \.element.id) { index, group in
                    shapeRow(group, last: index == shapes.count - 1)
                }
            }
        }
    }

    /// One cache file holding tokens found by format: the file, the lines,
    /// Redact… for the whole file (the lines sheet redacts one at a time).
    private func shapeRow(_ group: ScanFileGroup, last: Bool) -> some View {
        AppRow(
            name: Format.fileName(group.filePath),
            detail: Format.parentFolder(group.filePath),
            badge: isNew(group.findings) ? "new" : nil,
            fact: group.fact,
            last: last
        ) {
            if group.findings.count > 1 {
                Button("\(group.findings.count) Lines…") { actions.showLines(group) }.buttonStyle(AppButton(kind: .plain))
            }
            Button("Open") { actions.open(group.filePath, group.firstLine) }.buttonStyle(AppButton())
            Button("Redact…") {
                let n = group.findings.count
                actions.redact(
                    [group.filePath],
                    n == 1 ? group.findings[0].line.map { [$0] } ?? [] : [],
                    n == 1 ? "the " + group.findings[0].shortEvidence + " on line \(group.firstLine ?? 0)" : "\(n) tokens in this file",
                    group.findings.first?.foundIn
                )
            }
            .buttonStyle(AppButton(kind: .secondary)).disabled(model.toolsBusy != nil)
        }
    }

    /// "9 copies in 4 files, from ~/proj/.env and ~/.aws/credentials".
    /// The AI Agents window says the same thing about the same group, so
    /// the sentence lives in `Format` where one change reaches both.
    func agentDetail(_ g: ScanAgentGroup) -> String {
        Format.agentCacheDetail(g)
    }
}
