// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The scan window's agent-cache card: the copies grouped the way a
/// reader can act on them, one row per agent and cache area, where nine
/// hash-named file rows are not something anyone can act on.
extension ScanReportView {
    static let agentNote = "Verbatim copies of credentials the scan confirmed elsewhere, kept by an AI agent. "
        + "Clean Caches redacts them in place after its own Touch ID; every file is backed up first."

    func agentCard(_ groups: [ScanAgentGroup]) -> some View {
        AppCard(
            eyebrow: Format.tierLabel(.agentCaches),
            eyebrowTint: Color(Self.tierTint(.agentCaches)),
            title: Format.tierTitle(.agentCaches, files: groups.count),
            note: Self.agentNote
        ) {
            Button("Clean Caches…", action: actions.cleanCaches).buttonStyle(AppButton(kind: .secondary))
        } rows: {
            AppCardRows {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    AppRow(
                        name: group.agent,
                        detail: group.area,
                        fact: agentDetail(group),
                        last: index == groups.count - 1
                    ) {
                        if let first = group.files.first {
                            Button("Open") { actions.open(first, nil) }.buttonStyle(AppButton())
                            Button("Reveal") { actions.reveal(first) }.buttonStyle(AppButton(kind: .plain))
                        }
                    }
                }
            }
        }
    }

    /// "9 copies in 4 files, from ~/proj/.env and ~/.aws/credentials".
    func agentDetail(_ g: ScanAgentGroup) -> String {
        let copies = g.findings.count
        let files = g.files.count
        var text = "\(copies) cop\(copies == 1 ? "y" : "ies") in \(files) file\(files == 1 ? "" : "s")"
        let origins = g.origins.map(Format.home)
        if !origins.isEmpty {
            text += ", from " + origins.prefix(2).joined(separator: ", ") + (origins.count > 2 ? ", …" : "")
        }
        return text
    }
}
