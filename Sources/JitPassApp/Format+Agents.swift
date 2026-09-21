// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Every sentence the AI Agents window says, so one change reaches the
/// header, the footer and the empty state together. The rows' own facts
/// are AgentDigest's, in JitAgentClient, under test.
extension Format {
    /// The headline: how many agents, and how many need the reader.
    static func agentsHeadline(_ board: AgentsBoard) -> String {
        guard board.hasAgents else {
            return "No AI agent CLI on this Mac"
        }
        let agents = count(board.rows.count, "agent") + " on this Mac"
        if !board.scanned {
            return agents + " · not searched yet"
        }
        return agents + (board.needingYou == 0 ? " · all set" : " · \(board.needingYou) need" + (board.needingYou == 1 ? "s" : "") + " you")
    }

    /// The sentence under it: what the rows are, and where each fact lives.
    static func agentsSubline(_ board: AgentsBoard) -> String {
        guard board.hasAgents else {
            return "jit wraps " + ToolRecord.agentTools.sorted().prefix(4).joined(separator: ", ")
                + " and others. Install one and it shows up here."
        }
        guard board.scanned else {
            return "What each agent can reach and what it has done. A scan fills in the caches; "
                + "the key, the reads and the grant are read now."
        }
        return "What each agent can reach and what it has done. Every fact lives in Tools, Findings, "
            + "Decoys or Grants; this window only reads them."
    }

    /// The footer's runtime fact: whether an agent's tool has to ask.
    static func askingFact(_ board: AgentsBoard) -> String {
        switch board.consent {
        case true: "Asking is on · an agent's tool gets a machine credential only after you say so"
        case false: "Asking is off · an agent's tool gets machine credentials without asking you"
        default: "The service is not running, so nothing is asking and nothing is served"
        }
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
