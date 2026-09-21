// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The digest's one card: one row per agent, its four facts in a fixed
/// order — key · copies · reads · grant — and, in the action group, one
/// button to the home of the fact that needs the reader. A row with
/// nothing wrong has no button; a row with a grant has a quiet link to it.
/// Nothing here acts: Protect is in Findings, Wrap in Tools, Clean Caches
/// in Findings, and this window says where.
extension AgentsView {
    static let digestNote = "Every fact lives in Tools, Findings, Decoys or Grants; this window only reads them. "
        + "A value an agent already sent upstream needs rotating; jit cannot take that back."

    func digestCard(_ board: AgentsBoard) -> some View {
        AppCard(
            eyebrow: board.tier.word,
            eyebrowTint: Color(board.tier.tint),
            title: "What each agent can reach, and what it has done",
            note: Self.digestNote
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(board.rows.enumerated()), id: \.element.id) { index, row in
                    AppNoteRow(
                        mark: .dot(Color(row.tint)),
                        name: row.agent.tool + (row.agent.agentLabel.map { " · " + $0 } ?? ""),
                        fact: row.digest.facts.joined(separator: " · "),
                        last: index == board.rows.count - 1
                    ) {
                        if let home = row.digest.link {
                            Button(home.title) { open(home) }
                                .buttonStyle(AppButton(kind: row.digest.state == .green ? .plain : .secondary))
                        }
                    }
                }
            }
        }
    }

    private func open(_ home: AgentDigest.Home) {
        switch home {
        case .tools: actions.openTools()
        case .findings: actions.openScan()
        case .decoys: actions.openAudit()
        case .grants: actions.openGrants()
        }
    }
}
