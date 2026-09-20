// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Every sentence the AI Agents window says, so a test can hold the
/// wording and one change reaches the window, the empty state and the
/// footer together.
extension Format {
    /// The AI Agents window's headline: the one thing the reader came for,
    /// counted once. The cards below it never repeat this number.
    static func agentsHeadline(_ board: AgentsBoard) -> String {
        guard board.hasAgents else {
            return "No AI agent CLI on this Mac"
        }
        if board.copies > 0 {
            if board.copies == 1, board.cacheGroups.count == 1 {
                return "\(board.cacheGroups[0].agent) is holding a copy of one secret"
            }
            return "\(board.copies) copies of your secrets are sitting in "
                + count(board.cacheGroups.count, "agent cache", plural: "agent caches")
        }
        if board.mcpKeys > 0 {
            return count(board.mcpKeys, "key") + " written into "
                + count(board.mcpGroups.count, "MCP config")
        }
        if !board.keysInTheOpen.isEmpty {
            return count(board.keysInTheOpen.count, "agent key") + " sitting in the open"
        }
        if !board.scanned {
            return count(board.agents.count, "AI agent") + " on this Mac, not searched yet"
        }
        return "Nothing of yours is sitting in an agent"
    }

    /// The sentence under it: what jit looked at, and the limit that
    /// changes how the rest is read.
    static func agentsSubline(_ board: AgentsBoard) -> String {
        guard board.hasAgents else {
            return "jit wraps " + ToolRecord.agentTools.sorted().prefix(4).joined(separator: ", ")
                + " and others. Install one and it shows up here."
        }
        guard board.scanned else {
            return "jit has not searched this Mac yet. A scan finds the copies an agent has kept "
                + "and the keys written into MCP configs."
        }
        return "jit checked " + count(board.agents.count, "agent") + ", their keys, their caches and "
            + "every MCP config in your home folder. A value an agent already sent upstream needs "
            + "rotating; jit cannot take that back."
    }

    /// The footer: what was checked and when, with no number jit did not
    /// actually count.
    static func agentsFooter(_ board: AgentsBoard) -> String {
        guard board.scanned else {
            return "Never searched · a scan finds cached copies and MCP keys"
        }
        var parts = ["Checked " + names(board.agents.map(\.tool))]
        parts.append(board.mcpKeys == 0
            ? "no MCP config holds a key"
            : count(board.mcpKeys, "key") + " in " + count(board.mcpGroups.count, "MCP config"))
        if let at = board.checkedAt {
            parts.append(clock(at))
        }
        return parts.joined(separator: " · ")
    }

    /// What an all-clear window says instead of listing nothing.
    static func agentsClear(_ board: AgentsBoard) -> String {
        var parts: [String] = []
        parts.append(board.keysInVault > 0
            ? "Every agent's key is in the vault"
            : "No agent keeps a key in a file jit can see")
        parts.append("their caches are clean")
        parts.append("no MCP config holds a key")
        if board.decoys > 0 {
            parts.append(count(board.decoys, "file") + " answers them with decoys")
        }
        return parts.joined(separator: ", ") + "."
    }

    /// One agent row's fact: where its key sits, and what its caches hold.
    static func agentFact(_ tool: ToolRecord, board: AgentsBoard, scan: ScanReport?) -> String {
        var parts = [agentKeyFact(tool, scan: scan)]
        if let label = tool.agentLabel {
            parts.append(agentCacheFact(label, board: board, scan: scan))
        }
        return parts.joined(separator: " · ")
    }

    static func agentKeyFact(_ tool: ToolRecord, scan: ScanReport?) -> String {
        if tool.wrapped {
            return tool.isHealthy ? "Key in the vault, handed over at launch" : "Key in the vault, but the " + tool.stateLabel
        }
        switch tool.keyState(scan: scan) {
        case .protected:
            return "Key in the vault, handed over at launch"
        case let .found(source) where source.hasPrefix("~") || source.hasPrefix("/"):
            return "Key in plain text in " + home(source)
        case .found:
            return "Key in \(tool.tool)'s own login, not in the vault"
        case .none:
            return "No key in a file or a keychain"
        case .unknown:
            return "Key not checked yet"
        }
    }

    static func agentCacheFact(_ label: String, board: AgentsBoard, scan: ScanReport?) -> String {
        guard board.scanned, let scan else {
            return "caches not searched yet"
        }
        let copies = scan.agentCopies(in: label)
        return copies == 0 ? "caches clean" : count(copies, "cached copy", plural: "cached copies")
    }

    /// "9 copies in 4 files, from ~/proj/.env and ~/.aws/credentials".
    static func agentCacheDetail(_ group: ScanAgentGroup) -> String {
        var text = count(group.findings.count, "copy", plural: "copies")
            + " in " + count(group.files.count, "file")
        let origins = group.origins.map(home)
        if !origins.isEmpty {
            text += ", from " + origins.prefix(2).joined(separator: ", ") + (origins.count > 2 ? ", …" : "")
        }
        return text
    }

    /// One MCP config's fact: the keys it holds, and which of them only
    /// the reader can move.
    static func mcpFact(_ group: ScanFileGroup) -> String {
        let keys = group.findings.compactMap(\.keyName)
        var text = keys.isEmpty ? count(group.findings.count, "key") : keys.prefix(3).joined(separator: ", ")
        if keys.count > 3 {
            text += ", …"
        }
        let stuck = group.findings.filter { !$0.migratable }.count
        if stuck == group.findings.count {
            text += " · reported, not moved: jit cannot hand these to a process"
        } else if stuck > 0 {
            text += " · \(stuck) reported, not moved"
        }
        return text
    }

    static func decoysFact(_ board: AgentsBoard) -> String {
        guard board.decoys > 0 else {
            return "None yet · protect a file in the Scan window and it answers with fakes"
        }
        return count(board.decoys, "file") + " answers with fakes"
            + (board.decoysServingReal ? " · real values only inside a run you allowed" : "")
    }

    static func askingFact(_ board: AgentsBoard) -> String {
        switch board.consent {
        case true: "JitPass asks you before an agent's tool gets a machine credential"
        case false: "Off · an agent's tool gets machine credentials without asking you"
        default: "The service is not running, so nothing is asking and nothing is served"
        }
    }

    static func grantsFact(_ board: AgentsBoard) -> String {
        guard !board.grants.isEmpty else {
            return "None active · an agent working while you are away needs one"
        }
        let lines = board.grants.prefix(2).map { grant in
            (grant.name ?? grant.anchor ?? "pid \(grant.pid)") + " until " + clock(grant.expires)
        }
        return lines.joined(separator: " · ") + (board.grants.count > 2 ? " · …" : "")
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
