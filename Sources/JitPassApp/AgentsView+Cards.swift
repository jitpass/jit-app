// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The four subjects the AI Agents window has, in the order it draws
/// them. A card appears only when it has something in it, and the order
/// never changes with the state: a window that sorts itself by severity
/// moves the row out from under the pointer between one scan and the next.
enum AgentsCard: String, Identifiable, CaseIterable {
    /// The agents themselves, and where each one's own key sits.
    case agents
    /// The copies they already made, grouped by agent and cache area.
    case caches
    /// The keys written into MCP server configs.
    case mcp
    /// The decoys, the asking, and the grants.
    case reads

    var id: String {
        rawValue
    }

    func tier(_ board: AgentsBoard) -> AgentsBoard.Tier {
        switch self {
        case .agents: board.agentsTier
        case .caches: board.cachesTier
        case .mcp: board.mcpTier
        case .reads: board.readsTier
        }
    }

    /// How many rows this card lists, so a filter pill counts what the
    /// reader will actually see.
    func rows(_ board: AgentsBoard) -> Int {
        switch self {
        case .agents: board.agents.count
        case .caches: board.cacheGroups.count
        case .mcp: board.mcpGroups.count
        case .reads: 3
        }
    }

    /// The cards with something in them, in order.
    static func shown(_ board: AgentsBoard) -> [AgentsCard] {
        allCases.filter { card in
            switch card {
            case .agents: board.hasAgents
            case .caches: !board.cacheGroups.isEmpty
            case .mcp: !board.mcpGroups.isEmpty
            case .reads: true
            }
        }
    }

    /// The tiers the shown cards carry, in the cards' own order, each one
    /// once: the pills of the filter.
    static func tiersPresent(_ board: AgentsBoard) -> [AgentsBoard.Tier] {
        var seen: Set<AgentsBoard.Tier> = []
        return shown(board).map { $0.tier(board) }.filter { seen.insert($0).inserted }
    }
}

/// The cards themselves. Every sentence that used to wait for a hover is
/// a card note or a row fact here, and every button is one jit command
/// after a sheet or a dialog that says what it runs.
extension AgentsView {
    // MARK: - Agents

    static let agentsNote = "Where each agent's own key sits. A key in the vault is handed to the agent "
        + "when it launches and never written to a file."

    func agentsCard(_ board: AgentsBoard) -> some View {
        AppCard(
            eyebrow: board.agentsTier.word,
            eyebrowTint: Color(board.agentsTier.tint),
            title: "Agents and their keys",
            note: Self.agentsNote
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(board.agents.enumerated()), id: \.element.id) { index, agent in
                    agentRow(agent, board: board, last: index == board.agents.count - 1)
                }
            }
        }
    }

    /// One agent: its name, the scanner's name for it, and its two facts
    /// in one clause — where the key is, and what the caches hold.
    private func agentRow(_ agent: ToolRecord, board: AgentsBoard, last: Bool) -> some View {
        AppRow(
            name: agent.tool,
            detail: agent.agentLabel ?? agent.shortDoc,
            fact: Format.agentFact(agent, board: board, scan: model.macScan),
            last: last
        ) {
            if model.toolsBusy == agent.tool {
                Text("Touch ID…").font(Win.button12).foregroundStyle(.secondary)
            } else {
                agentButtons(agent)
            }
        }
        .disabled(model.toolsBusy != nil)
    }

    @ViewBuilder
    private func agentButtons(_ agent: ToolRecord) -> some View {
        let state = agent.keyState(scan: model.macScan)
        if agent.wrapped {
            if !agent.isHealthy {
                Button("Repair…") { actions.openSheet(.wrap(tool: agent.tool)) }
                    .buttonStyle(AppButton(kind: .secondary))
            }
            Button("Unwrap…") { actions.unwrap(agent.tool) }.buttonStyle(AppButton())
        } else if state.found {
            if case let .found(source) = state, source.hasPrefix("~") || source.hasPrefix("/") {
                Button("Open") { actions.open(source) }.buttonStyle(AppButton())
            }
            Button("Move to Vault…") { actions.openSheet(.wrap(tool: agent.tool)) }
                .buttonStyle(AppButton(kind: .secondary))
        } else {
            // Nothing in the open to take. The offer stays for a key the
            // reader has to paste, and it never nags.
            Button("Add Key…") { actions.openSheet(.wrap(tool: agent.tool)) }.buttonStyle(AppButton())
        }
    }

    // MARK: - Cached copies

    static let cachesNote = "An agent keeps a snapshot of every file it reads, of pasted text, of your "
        + "shell environment and of the conversation. These hold values the vault still uses."

    func cachesCard(_ board: AgentsBoard) -> some View {
        AppCard(
            eyebrow: board.cachesTier.word,
            eyebrowTint: Color(board.cachesTier.tint),
            title: Format.count(board.copies, "copy", plural: "copies") + " an agent kept",
            note: Self.cachesNote
        ) {
            Button("Clean Caches…", action: actions.cleanCaches)
                .buttonStyle(AppButton(kind: .secondary)).disabled(model.toolsBusy != nil)
        } rows: {
            AppCardRows {
                ForEach(Array(board.cacheGroups.enumerated()), id: \.element.id) { index, group in
                    AppRow(
                        name: group.agent,
                        detail: group.area,
                        fact: Format.agentCacheDetail(group),
                        last: index == board.cacheGroups.count - 1
                    ) {
                        if let file = group.files.first {
                            Button("Open") { actions.open(file) }.buttonStyle(AppButton())
                            fileMenu(file)
                        }
                    }
                }
            }
        }
    }

    // MARK: - MCP servers

    static let mcpNote = "A key written into an MCP server's env block is a key in a config file. "
        + "Protect moves it into the vault and rewrites the file to point at it."

    func mcpCard(_ board: AgentsBoard) -> some View {
        AppCard(
            eyebrow: board.mcpTier.word,
            eyebrowTint: Color(board.mcpTier.tint),
            title: Format.count(board.mcpKeys, "key") + " in an MCP config",
            note: Self.mcpNote
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(board.mcpGroups.enumerated()), id: \.element.id) { index, group in
                    AppRow(
                        name: Format.fileName(group.filePath),
                        detail: Format.parentFolder(group.filePath),
                        fact: Format.mcpFact(group),
                        last: index == board.mcpGroups.count - 1
                    ) {
                        Button("Open") { actions.open(group.filePath) }.buttonStyle(AppButton())
                        if group.findings.contains(where: \.migratable) {
                            Button("Protect…") { actions.protectFile(group.filePath) }
                                .buttonStyle(AppButton(kind: .secondary)).disabled(model.toolsBusy != nil)
                        }
                        fileMenu(group.filePath)
                    }
                }
            }
        }
    }

    // MARK: - What agents read

    static let readsNote = "A protected file answers an agent with a decoy: the value in its transcript "
        + "is fake, and so is the one it sends upstream."

    func readsCard(_ board: AgentsBoard) -> some View {
        AppCard(
            eyebrow: board.readsTier.word,
            eyebrowTint: Color(board.readsTier.tint),
            title: "What agents read",
            note: Self.readsNote
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                AppRow(name: "Decoys", fact: Format.decoysFact(board), wraps: true) {
                    Button("Scan", action: actions.openScan).buttonStyle(AppButton())
                }
                AppRow(name: "Asking", fact: Format.askingFact(board), wraps: true) {
                    Button("Settings…", action: actions.openSettings).buttonStyle(AppButton())
                }
                AppRow(name: "Grants", fact: Format.grantsFact(board), wraps: true, last: true) {
                    if !board.grants.isEmpty {
                        Button("Grants", action: actions.openGrants).buttonStyle(AppButton())
                    }
                    Button("New Grant…", action: actions.newGrant).buttonStyle(AppButton(kind: .secondary))
                }
            }
        }
    }

    // MARK: - Shared

    /// Everything cheap and reversible about a file, where a mis-click
    /// costs nothing.
    private func fileMenu(_ path: String) -> some View {
        Menu {
            Button("Reveal in Finder") { actions.reveal(path) }
            Button("Copy Path") { actions.copyPath(path) }
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton())
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
