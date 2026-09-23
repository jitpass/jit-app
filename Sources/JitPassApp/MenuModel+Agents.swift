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
                grantEnds: grant.map(AgentCard.grantEnds),
                consent: consentEnabled, activity: agentActivity[agent.tool],
                redactsAfterScan: redactAfterScan || redactAgents.contains(agent.tool), home: home
            ))
            return (agent, card)
        }
    }
}
