// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// What the AI Agents window is looking at, worked out once so the
/// header's mark, every card's eyebrow, the footer's dot and the empty
/// state cannot disagree about the same fact.
///
/// Every value here is the engine's: `jit wrap list` for the agents and
/// their keys, the last whole-Mac scan for the cached copies and the MCP
/// configs, `jit status` for the mounts serving decoys, and the service
/// for consent and the live grants. The board adds no check of its own.
struct AgentsBoard {
    /// A card's tier: the word beside its dot, and the colour of the dot.
    /// Four states, the app's and the CLI's, and no fifth.
    enum Tier {
        /// A copy of a live secret is sitting somewhere it should not be.
        case fixNow
        /// Only the user can close this one: a key to move, a setting to
        /// turn back on.
        case needsYou
        /// Nothing is wrong, but the protection is not there yet either.
        case notYet
        /// The vault holds it and jit hands it over at launch.
        case protected
        /// jit looked and there was nothing in the open to take.
        case nothingToMove
        /// It is doing its job right now.
        case working

        var word: String {
            switch self {
            case .fixNow: "Fix now"
            case .needsYou: "Needs you"
            case .notYet: "Not yet"
            case .protected: "Protected"
            case .nothingToMove: "Nothing to move"
            case .working: "Working"
            }
        }

        var tint: NSColor {
            switch self {
            case .fixNow: StatusMark.red
            case .needsYou, .notYet: StatusMark.amber
            case .protected, .nothingToMove, .working: StatusMark.green
            }
        }

        /// Whether this tier is something the reader has to come back to.
        /// The filter only appears when at least one card says yes.
        var needsAttention: Bool {
            self == .fixNow || self == .needsYou || self == .notYet
        }
    }

    var agents: [ToolRecord] = []
    /// Agents whose own key sits in a plaintext file or a tool's login:
    /// the ones a Move to Vault would change.
    var keysInTheOpen: [ToolRecord] = []
    var keysInVault = 0
    var cacheGroups: [ScanAgentGroup] = []
    var mcpGroups: [ScanFileGroup] = []
    /// Whether a whole-Mac scan has run: without one the caches and the
    /// MCP configs are unknown, not clean.
    var scanned = false
    var checkedAt: Date?
    /// nil when the service is not running, so the window says that and
    /// not "consent is off".
    var consent: Bool?
    var decoys = 0
    var decoysServingReal = false
    var grants: [GrantStatus] = []

    var copies: Int {
        cacheGroups.reduce(0) { $0 + $1.findings.count }
    }

    /// MCP keys `jit migrate` can move. The rest are in args, headers or a
    /// url, which no process can be handed: jit reports them and stops.
    var mcpMovable: Int {
        mcpGroups.reduce(0) { $0 + $1.findings.filter(\.migratable).count }
    }

    var mcpKeys: Int {
        mcpGroups.reduce(0) { $0 + $1.findings.count }
    }

    // MARK: - Tiers

    /// Where each agent's own key sits.
    var agentsTier: Tier {
        if !keysInTheOpen.isEmpty {
            return .needsYou
        }
        return keysInVault > 0 ? .protected : .nothingToMove
    }

    /// Only drawn when there is something in it, so it has one tier.
    var cachesTier: Tier {
        .fixNow
    }

    var mcpTier: Tier {
        mcpMovable > 0 ? .fixNow : .needsYou
    }

    /// The decoys, the asking, and the grants that keep an agent working
    /// while nobody is at the keyboard.
    var readsTier: Tier {
        if consent == false {
            return .needsYou
        }
        return decoys > 0 ? .working : .notYet
    }

    /// The window's one state: the worst tier it is drawing.
    var tier: Tier {
        if !cacheGroups.isEmpty {
            return .fixNow
        }
        if !mcpGroups.isEmpty {
            return mcpTier
        }
        for tier in [agentsTier, readsTier] where tier.needsAttention {
            return tier
        }
        return scanned ? .working : .notYet
    }

    /// Nothing to fix, nothing waiting on the reader, and a scan behind
    /// it: the window has a sentence to say instead of a list.
    var isClear: Bool {
        scanned && !agents.isEmpty && cacheGroups.isEmpty && mcpGroups.isEmpty
            && !agentsTier.needsAttention && !readsTier.needsAttention
    }

    var hasAgents: Bool {
        !agents.isEmpty
    }

    // MARK: - Making one

    @MainActor
    static func make(_ model: MenuModel) -> AgentsBoard {
        var board = AgentsBoard()
        let listing = model.toolListing
        board.agents = listing?.agents ?? []
        board.keysInTheOpen = board.agents.filter { $0.keyState(scan: model.macScan).found }
        board.keysInVault = board.agents.filter(\.isProtected).count
        if let scan = model.macScan {
            board.scanned = true
            board.cacheGroups = scan.agentCacheGroups
            board.mcpGroups = scan.mcpByFile
        }
        board.checkedAt = model.macScanAt
        board.consent = model.consentEnabled
        board.decoys = model.cli?.mounts?.registered ?? 0
        board.decoysServingReal = model.cli?.mounts?.servingReal ?? false
        board.grants = model.grants
        return board
    }
}
