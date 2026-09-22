// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// What the AI Agents window is looking at, worked out once so the
/// header's mark, every card's eyebrow and the footer cannot disagree
/// about the same fact. One card per agent (MenuModel.agentCards); the
/// board only sums them.
struct AgentsBoard {
    /// The window's state word and colour. Four states, the app's and the
    /// CLI's, and no fifth.
    enum Tier {
        /// A copy of a secret is sitting in an agent's files.
        case fixNow
        /// Only the user can close this one: a key to move, Asking to turn on.
        case needsYou
        /// Nothing is wrong, but jit has not looked yet.
        case notYet
        /// It is doing its job right now.
        case working

        var word: String {
            switch self {
            case .fixNow: "Fix now"
            case .needsYou: "Needs you"
            case .notYet: "Not yet"
            case .working: "Working"
            }
        }

        var tint: NSColor {
            switch self {
            case .fixNow: StatusMark.red
            case .needsYou, .notYet: StatusMark.amber
            case .working: StatusMark.green
            }
        }

        static func of(_ state: AgentCard.State, scanned: Bool) -> Tier {
            switch state {
            case .red: .fixNow
            case .amber: .needsYou
            case .green: scanned ? .working : .notYet
            }
        }
    }

    struct Row: Identifiable {
        let agent: ToolRecord
        let card: AgentCard
        var id: String {
            agent.id
        }
    }

    var rows: [Row] = []
    var scanned = false
    var scanAt: Date?
    var scanDeep = false

    var hasAgents: Bool {
        !rows.isEmpty
    }

    var tier: Tier {
        if rows.contains(where: { $0.card.state == .red }) {
            return .fixNow
        }
        if rows.contains(where: { $0.card.state == .amber }) {
            return .needsYou
        }
        return scanned ? .working : .notYet
    }

    @MainActor
    static func make(_ model: MenuModel) -> AgentsBoard {
        var board = AgentsBoard()
        board.scanned = model.macScan != nil
        board.scanAt = model.macScanAt
        board.scanDeep = model.macScanKind?.isDeep == true
        board.rows = model.agentCards.map { Row(agent: $0.tool, card: $0.card) }
        return board
    }
}
