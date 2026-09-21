// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The AI Agents window, built from the window system (`docs/design/
/// mockups/AI-Agents-redesign.html` and the design system's Windows
/// page): banner, header, filter, body at one inset, footer. The body
/// holds one card per subject that has anything in it, and each card
/// carries its own tier in its eyebrow, so the red one is findable
/// without the reader opening every tooltip.
///
/// The four subjects keep the order the website's "ai agents" page tells
/// them, with the caches next to the keys because they are the two facts
/// about one agent: the agents and their keys, the copies they already
/// made, the MCP configs, and the files they read. The order never
/// changes with the state, so the window does not rearrange itself under
/// the pointer.
///
/// Every fact is the engine's and every button is one jit command. What
/// used to wait for a hover is on screen.
struct AgentsView: View {
    @ObservedObject var model: MenuModel
    let actions: AgentsActions

    /// The tier the filter is on; nil is all of them. Reset by a new
    /// listing or scan, because a pill for a tier the window no longer
    /// has would leave the body empty with no way back.
    @State var tier: AgentsBoard.Tier?

    var body: some View {
        let board = AgentsBoard.make(model)
        VStack(spacing: 0) {
            if let outcome = model.agentsOutcome {
                WindowBanner(tint: Color(outcome.failed ? StatusMark.red : StatusMark.green), text: outcome.title) {
                    Button("What jit Did…") { actions.openSheet(.result(title: outcome.title, text: outcome.text)) }
                        .buttonStyle(AppButton(kind: .plain))
                }
            }
            header(board)
            if showsFilter(board) {
                AppSegmented(items: pills(board), selection: $tier).windowRegion()
            }
            body(board)
            footer(board)
        }
        .frame(
            minWidth: Win.width, maxWidth: .infinity,
            minHeight: Win.minimum(Win.height), maxHeight: .infinity,
            alignment: .top
        )
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onChange(of: model.macScan) { _, _ in tier = nil }
        .onChange(of: model.toolListing) { _, _ in tier = nil }
        .onPreferenceChange(WindowHeightKey.self) { height in
            actions.fit(height + Self.chrome(filter: showsFilter(board), banner: model.agentsOutcome != nil))
        }
        .sheet(item: $model.agentsSheet) { sheet in
            switch sheet {
            case let .wrap(tool):
                if let record = model.toolListing?.tool(named: tool) {
                    WrapSheet(
                        model: model,
                        actions: ToolsActions(closeSheet: actions.closeSheet, wrap: actions.wrap),
                        tool: record
                    )
                }
            case .handWrap:
                // The Tools window's button; never opened from here.
                EmptyView()
            case let .result(title, text):
                ResultSheet(title: title, text: text, close: actions.closeSheet)
            case .scanDepth:
                // The Findings window's question; never opened from here.
                EmptyView()
            }
        }
        .onAppear(perform: actions.reload)
    }

    /// The regions above and below the body, which the window adds to the
    /// height the body asks for.
    static func chrome(filter: Bool, banner: Bool) -> CGFloat {
        112 + (filter ? 49 : 0) + (banner ? 39 : 0)
    }

    // MARK: - Header

    /// What you are looking at, counted once, and the one sentence that
    /// changes the decision: what jit checked, and what it cannot undo.
    private func header(_ board: AgentsBoard) -> some View {
        HStack(alignment: .top, spacing: Win.s5) {
            WindowMark(tint: Color(board.tier.tint), hollow: !board.scanned && board.hasAgents)
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(Format.agentsHeadline(board)).font(Win.head)
                Text(Format.agentsSubline(board)).font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Win.s5)
            HStack(spacing: Win.s3) {
                if model.scanning || model.toolsRefreshing {
                    ProgressView().controlSize(.small)
                }
                Button(board.scanned ? "Rescan" : "Scan Now", action: actions.scanNow)
                    .buttonStyle(AppButton()).disabled(model.scanning)
                moreMenu
            }
            .padding(.top, Win.s1)
        }
        .windowRegion()
    }

    /// The surfaces this window sends you to, in one menu, so the header
    /// never holds four buttons that truncate as it narrows.
    private var moreMenu: some View {
        Menu {
            Button("Refresh Listing", action: actions.reload).disabled(model.toolsRefreshing)
            Divider()
            Button("Tools…", action: actions.openTools)
            Button("Audit…", action: actions.openAudit)
            Button("Settings…", action: actions.openSettings)
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton())
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Filter

    /// A filter over four cards is furniture unless one of them needs the
    /// reader: then it is the way to the one that does.
    func showsFilter(_ board: AgentsBoard) -> Bool {
        let cards = AgentsCard.shown(board)
        return cards.count >= 4 && cards.contains { $0.tier(board).needsAttention }
    }

    private func pills(_ board: AgentsBoard) -> [AppSegmentItem<AgentsBoard.Tier?>] {
        let cards = AgentsCard.shown(board)
        var items: [AppSegmentItem<AgentsBoard.Tier?>] = [
            AppSegmentItem(value: nil, title: "All", count: cards.reduce(0) { $0 + $1.rows(board) })
        ]
        for tier in AgentsCard.tiersPresent(board) {
            let rows = cards.filter { $0.tier(board) == tier }.reduce(0) { $0 + $1.rows(board) }
            items.append(AppSegmentItem(
                value: tier,
                title: tier.word,
                count: rows,
                dot: tier.needsAttention ? Color(tier.tint) : nil
            ))
        }
        return items
    }

    // MARK: - Body

    @ViewBuilder
    private func body(_ board: AgentsBoard) -> some View {
        if board.isClear, model.toolsMessage == nil, model.agentsOutcome == nil {
            clear(board).measureWindowHeight()
            Spacer(minLength: 0)
        } else if !board.hasAgents, model.toolListing != nil, model.toolsMessage == nil {
            noAgents.measureWindowHeight()
            Spacer(minLength: 0)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Win.s5) {
                    if let message = model.toolsMessage {
                        failed(message)
                    }
                    ForEach(shown(board)) { card in
                        self.card(card, board)
                    }
                }
                .padding(Win.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .measureWindowHeight()
            }
        }
    }

    /// The cards the body draws: the filter's tier, or every card that
    /// has something in it.
    private func shown(_ board: AgentsBoard) -> [AgentsCard] {
        let cards = AgentsCard.shown(board)
        guard let tier, cards.contains(where: { $0.tier(board) == tier }) else {
            return cards
        }
        return cards.filter { $0.tier(board) == tier }
    }

    @ViewBuilder
    private func card(_ card: AgentsCard, _ board: AgentsBoard) -> some View {
        switch card {
        case .agents: agentsCard(board)
        case .caches: cachesCard(board)
        case .mcp: mcpCard(board)
        case .reads: readsCard(board)
        }
    }

    /// A command that did not work: the sentence that says what to do,
    /// and jit's own words under it. The one place raw output belongs on
    /// screen, and never in a black pane.
    private func failed(_ message: String) -> some View {
        AppCard(
            eyebrow: AgentsBoard.Tier.fixNow.word,
            eyebrowTint: Color(StatusMark.red),
            title: "jit did not finish that",
            note: "Nothing was changed. Fix what it names below and run it again."
        ) {
            Button("Dismiss") { model.toolsMessage = nil }.buttonStyle(AppButton())
        } rows: {
            AppCardRows {
                AppNoteRow(mark: .failed, name: "jit said", verbatim: message, last: true) { EmptyView() }
            }
        }
    }

    // MARK: - Empty states

    /// Nothing to report, said as what is true rather than as an empty
    /// list.
    private func clear(_ board: AgentsBoard) -> some View {
        WindowEmptyState(
            tint: Color(StatusMark.green),
            title: "Nothing of yours is sitting in an agent",
            message: Format.agentsClear(board)
        ) {
            Button("Rescan", action: actions.scanNow).buttonStyle(AppButton()).disabled(model.scanning)
        }
    }

    private var noAgents: some View {
        WindowEmptyState(
            tint: Color(StatusMark.green),
            hollow: true,
            title: "No AI agent CLI on this Mac",
            message: "jit wraps " + ToolRecord.agentTools.sorted().prefix(4).joined(separator: ", ")
                + " and others. Install one and it shows up here, with its key and its caches."
        ) {
            Button("Tools…", action: actions.openTools).buttonStyle(AppButton())
        }
    }

    // MARK: - Footer

    /// What jit checked and when. This footer only states: the one action
    /// for each finding is on the card that found it, and a Clean Caches
    /// here as well would be the same button twice for the same file.
    private func footer(_ board: AgentsBoard) -> some View {
        HStack(spacing: Win.s4) {
            StateDot(tint: Color(board.tier.tint))
            Text(Format.agentsFooter(board)).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: Win.s5)
        }
        .padding(.horizontal, Win.s6)
        .padding(.vertical, Win.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.hover)
        .overlay(alignment: .top) { Rectangle().fill(WindowSurface.separator).frame(height: 1) }
    }
}

struct AgentsActions {
    var reload: () -> Void = {}
    var openSheet: (ToolsSheet) -> Void = { _ in }
    var closeSheet: () -> Void = {}
    var wrap: (String, String?) -> Void = { _, _ in }
    var unwrap: (String) -> Void = { _ in }
    var cleanCaches: () -> Void = {}
    var protectFile: (String) -> Void = { _ in }
    var scanNow: () -> Void = {}
    var newGrant: () -> Void = {}
    var openGrants: () -> Void = {}
    var openScan: () -> Void = {}
    var openSettings: () -> Void = {}
    var openTools: () -> Void = {}
    var openAudit: () -> Void = {}
    var open: (String) -> Void = { _ in }
    var reveal: (String) -> Void = { _ in }
    var copyPath: (String) -> Void = { _ in }
    /// The window asks to be the height of what it holds.
    var fit: (CGFloat) -> Void = { _ in }
}

/// What the last action in this window did: the banner's sentence, with
/// jit's own words one click away rather than in a modal that reports
/// success.
/// What just happened in a window, for its banner: the sentence, jit's
/// own words behind "What jit Did…", whether it failed, and the files an
/// Undo would restore.
struct WindowOutcome: Equatable {
    var title: String
    var text: String
    var failed = false
    var undo: [String] = []
}
