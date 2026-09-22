// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// The panel's AI Agents row and the cards the window draws, worked out
/// from the same facts so the row's dot and the window's mark agree.
extension MenuModel {
    /// One card per installed agent, in the listing's order.
    var agentCards: [(tool: ToolRecord, card: AgentCard)] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let scan = macScan
        let known = macScanNew
        return (toolListing?.agents ?? []).map { agent in
            let label = agent.agentLabel ?? agent.tool
            let exposure = scan?.agentExposure(label)
            let fresh = known.map { ids in (scan?.findings(in: label) ?? []).filter { ids.contains($0.id) }.count } ?? 0
            let grant = grants.first { $0.name == agent.tool || $0.anchor?.contains(agent.tool) == true }
            let card = AgentCard.make(AgentCard.Input(
                tool: agent.tool, label: label, key: agent.keyState(scan: scan),
                wrapped: agent.wrapped, healthy: agent.isHealthy, stateLabel: agent.stateLabel,
                exposure: exposure, newCopies: fresh,
                protectedFiles: cli?.mounts?.registered ?? 0,
                mcpKeysInTheOpen: scan?.mcpByFile.reduce(0) { $0 + $1.findings.count } ?? 0,
                grantUntil: grant.map { Date(timeIntervalSince1970: TimeInterval($0.expiresUnix)) },
                consent: consentEnabled, activity: agentActivity[agent.tool],
                redactsAfterScan: redactAfterScan || redactAgents.contains(agent.tool), home: home
            ))
            return (agent, card)
        }
    }

    /// The row's value: the worst fact, in the reader's words, so "1 of 1"
    /// never sits green over copies in an agent's files.
    var agentsValue: String? {
        let cards = agentCards
        guard !cards.isEmpty else {
            return nil
        }
        let red = cards.filter { $0.card.state == .red }
        if red.count == 1, let label = red.first?.tool.agentLabel {
            return "copies in " + label
        }
        if red.count > 1 {
            return "copies in \(red.count) agents' files"
        }
        let amber = cards.filter { $0.card.state == .amber }.count
        if amber > 0 {
            return "\(amber) need" + (amber == 1 ? "s" : "") + " you"
        }
        return macScan == nil ? "not searched yet" : "all set"
    }

    var agentsState: AgentsState? {
        let cards = agentCards
        guard !cards.isEmpty else {
            return nil
        }
        if cards.contains(where: { $0.card.state == .red }) {
            return .red
        }
        return cards.contains(where: { $0.card.state == .amber }) || macScan == nil ? .amber : .green
    }
}
