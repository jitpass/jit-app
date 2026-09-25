// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Every sentence the AI Agents window says, so one change reaches the
/// header, the footer and the empty state together. The cards' own facts
/// are AgentCard's, in JitAgentClient, under test.
extension Format {
    /// The headline: how many agents, and the AI apps with a card of their
    /// own (Claude Desktop, Cursor), so it counts every card the window
    /// shows. The lines under it say what they ask.
    static func agentsHeadline(_ board: AgentsBoard, apps: Int = 0) -> String {
        guard board.hasAgents else {
            return apps == 0 ? "No AI agent CLI on this Mac" : count(apps, "AI app") + " on this Mac"
        }
        return agentsAndApps(board.rows.count, apps: apps) + " on this Mac"
    }

    /// "1 agent" / "1 agent and 2 AI apps".
    static func agentsAndApps(_ agents: Int, apps: Int) -> String {
        count(agents, "agent") + (apps == 0 ? "" : " and " + count(apps, "AI app"))
    }

    /// The sentence under it: where the facts come from, and the one
    /// thing jit cannot do about an agent.
    static func agentsSubline(_ board: AgentsBoard, now: Date = Date()) -> String {
        guard board.hasAgents else {
            return "jit wraps " + ToolRecord.agentTools.sorted().prefix(4).joined(separator: ", ")
                + " and others. Install one and it shows up here."
        }
        guard let at = board.scanAt else {
            return "Its files are not searched yet; a whole-Mac scan fills them in. Reads and runs come from the audit, live."
        }
        let scan = (board.scanDeep ? "the deep scan " : "the scan ") + ScanWording.when(at, now: now)
        return "From " + scan + " and the audit, live. A value an agent already sent upstream needs rotating."
    }

    /// The footer states: agents, copies in their files, runs this week.
    static func agentsFooter(_ board: AgentsBoard, activity: [String: AgentActivity], apps: Int = 0) -> String {
        var parts = [agentsAndApps(board.rows.count, apps: apps)]
        if board.scanned {
            let exposed = board.rows.filter { $0.card.redactCount > 0 || $0.card.offersClean }.count
            parts.append(exposed == 0 ? "nothing in their files" : "copies in " + count(exposed, "agent's files", plural: "agents' files"))
        }
        let runs = activity.values.reduce(0) { $0 + $1.runs }
        if !activity.isEmpty {
            parts.append(count(runs, "run") + " through jit this week")
        }
        return parts.joined(separator: " · ")
    }

    /// "9 copies in 4 files, from ~/proj/.env and ~/.aws/credentials".
    /// The Findings window's agent-cache card says this; it lives here so
    /// one change reaches every window that names a cache group.
    static func agentCacheDetail(_ group: ScanAgentGroup) -> String {
        var text = count(group.findings.count, "copy", plural: "copies")
            + " in " + count(group.files.count, "file")
        let origins = group.origins.map(home)
        if !origins.isEmpty {
            text += ", from " + origins.prefix(2).joined(separator: ", ") + (origins.count > 2 ? ", …" : "")
        }
        return text
    }

    /// "1 file" / "3 files", so no sentence has to carry its own plural.
    static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? singular : plural ?? singular + "s")
    }

    /// "claude", "claude and codex", "claude, codex and gemini".
    static func names(_ list: [String]) -> String {
        switch list.count {
        case 0: "nothing"
        case 1: list[0]
        default: list.dropLast().joined(separator: ", ") + " and " + (list.last ?? "")
        }
    }
}
