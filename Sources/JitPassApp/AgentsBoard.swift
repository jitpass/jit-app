// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// What the AI Agents window is looking at, worked out once so the
/// header's mark, every row's dot and the footer cannot disagree about
/// the same fact.
///
/// The window is a digest (design/scan-and-protect.md D10): one row per
/// agent, four facts each, every fact read from its home — `jit wrap
/// list` for the key, the last whole-Mac scan for the cached copies, the
/// audit for the decoy reads, the service for the grants and for consent.
/// The board adds no check of its own and offers no verb of its own.
struct AgentsBoard {
    /// The window's state word and colour. Four states, the app's and the
    /// CLI's, and no fifth.
    enum Tier {
        /// A copy of a live secret is sitting somewhere it should not be.
        case fixNow
        /// Only the user can close this one: a key to move, a shim to fix.
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
    }

    struct Row: Identifiable {
        let agent: ToolRecord
        let digest: AgentDigest

        var id: String {
            agent.id
        }

        var tint: NSColor {
            switch digest.state {
            case .red: StatusMark.red
            case .amber: StatusMark.amber
            case .green: StatusMark.green
            }
        }
    }

    var rows: [Row] = []
    /// Whether a whole-Mac scan has run: without one the caches are
    /// unknown, not clean.
    var scanned = false
    var checkedAt: Date?
    /// nil when the service is not running, so the window says that and
    /// not "consent is off".
    var consent: Bool?

    var hasAgents: Bool {
        !rows.isEmpty
    }

    /// Rows whose dot is not green: what the headline counts.
    var needingYou: Int {
        rows.filter { $0.digest.state != .green }.count
    }

    /// The window's one state: the worst row it is drawing.
    var tier: Tier {
        if rows.contains(where: { $0.digest.state == .red }) {
            return .fixNow
        }
        if rows.contains(where: { $0.digest.state == .amber }) {
            return .needsYou
        }
        return scanned ? .working : .notYet
    }

    @MainActor
    static func make(_ model: MenuModel) -> AgentsBoard {
        var board = AgentsBoard()
        let scan = model.macScan
        board.scanned = scan != nil
        board.checkedAt = model.macScanAt
        board.consent = model.consentEnabled
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let agents = model.toolListing?.agents ?? []
        board.rows = agents.map { agent in
            let label = agent.agentLabel
            let copies = label.map { scan?.agentCopies(in: $0) ?? 0 } ?? 0
            let areas = label.map { name in (scan?.agentCacheGroups ?? []).filter { $0.agent == name }.map(\.area) } ?? []
            let grant = model.grants.first { $0.name == agent.tool || $0.anchor?.contains(agent.tool) == true }
            let digest = AgentDigest.make(AgentDigest.Input(
                tool: agent.tool,
                key: agent.keyState(scan: scan),
                wrapped: agent.wrapped,
                healthy: agent.isHealthy,
                stateLabel: agent.stateLabel,
                scanned: scan != nil,
                copies: copies,
                areas: areas,
                readsToday: model.decoyReads24h == nil ? nil : model.decoyReadsByProgram[agent.tool] ?? 0,
                grantUntil: grant.map { Date(timeIntervalSince1970: TimeInterval($0.expiresUnix)) },
                home: home
            ))
            return Row(agent: agent, digest: digest)
        }
        return board
    }
}
