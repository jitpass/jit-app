// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The scan window's "AI agent caches" section: one row per agent and
/// cache area, the copies grouped the way a reader can act on them.
extension ScanReportView {
    static let agentNote = "Verbatim copies of credentials the scan confirmed elsewhere, kept by an AI agent. "
        + "Clean Caches redacts them in place after its own Touch ID; every file is backed up first."

    /// One row per agent and cache area: what a reader can act on, where
    /// nine hash-named file rows are not. Open and Reveal go to the first
    /// file in the group.
    func agentSection(_ groups: [ScanAgentGroup]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                heading("AI agent caches", groups.reduce(0) { $0 + $1.findings.count })
                Spacer()
                Button("Clean Caches…", action: actions.cleanCaches).controlSize(.small)
            }
            ForEach(groups) { g in
                HStack(alignment: .top, spacing: 8) {
                    dot(g.severity)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(g.agent + " · " + g.area).font(.system(size: 12, weight: .medium))
                        Text(agentDetail(g)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if let first = g.files.first {
                        fileButtons(first, line: nil)
                    }
                }
            }
            Text(Self.agentNote).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// "9 copies in 4 files, from ~/proj/.env and ~/.aws/credentials".
    func agentDetail(_ g: ScanAgentGroup) -> String {
        let copies = g.findings.count
        let files = g.files.count
        var text = "\(copies) cop\(copies == 1 ? "y" : "ies") in \(files) file\(files == 1 ? "" : "s")"
        let origins = g.origins.map(Format.home)
        if !origins.isEmpty {
            text += ", from " + origins.prefix(3).joined(separator: ", ") + (origins.count > 3 ? ", …" : "")
        }
        return text
    }
}
