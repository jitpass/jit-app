// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// One agent's card: the eyebrow is its state, the title its name, the
/// note what changed since the last scan, and five rows — in its files,
/// can reach, this week, its key, and the one setting that is the agent's
/// own. The first row carries the verbs; the others link to the window
/// that holds the whole story.
extension AgentsView {
    func agentCard(_ row: AgentsBoard.Row, scanned: Bool) -> some View {
        let tier = AgentsBoard.Tier.of(row.card.state, scanned: scanned)
        let busy = model.toolsBusy != nil
        return AppCard(
            eyebrow: tier.word,
            eyebrowTint: Color(tier.tint),
            title: row.agent.tool + (row.agent.agentLabel.map { " · " + $0 } ?? ""),
            note: row.card.since
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                AppRow(name: "In its files", fact: row.card.inFiles) {
                    if row.card.offersClean {
                        Button("Clean Caches…", action: actions.cleanCaches).buttonStyle(AppButton()).disabled(busy)
                    }
                    if row.card.redactCount > 0 {
                        Button("Redact All \(row.card.redactCount)…") { actions.redact(row.agent) }
                            .buttonStyle(AppButton(kind: .secondary)).disabled(busy)
                    }
                    if row.card.state == .red {
                        Button("Findings…", action: actions.openScan).buttonStyle(AppButton(kind: .plain))
                    }
                }
                AppRow(name: "Can reach", fact: row.card.canReach) {
                    Button("Grants…", action: actions.openGrants).buttonStyle(AppButton(kind: .plain))
                }
                AppRow(name: "This week", fact: row.card.thisWeek) {
                    Button("Audit…") { actions.openAudit(row.agent) }.buttonStyle(AppButton(kind: .plain))
                }
                AppRow(name: "Its key", fact: row.card.key) {
                    if row.card.state != .green, row.agent.keyState(scan: model.macScan) != .none {
                        Button("Tools…", action: actions.openTools).buttonStyle(AppButton(kind: .plain))
                    }
                }
                AppRow(name: "Redact its caches after every scheduled scan", fact: row.card.redactFact, last: true) {
                    AppSwitch(isOn: Binding(
                        get: { model.redactAfterScan || model.redactAgents.contains(row.agent.tool) },
                        set: { actions.setRedactAfterScan(row.agent, $0) }
                    ))
                    .disabled(model.redactAfterScan)
                }
            }
        }
    }
}
