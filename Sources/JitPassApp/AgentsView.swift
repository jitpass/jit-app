// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The AI Agents window, built from the window system: banner, header,
/// body at one inset, footer. One card per agent, rows for its facts —
/// what is in its files, what it can reach, what it did, its key — each
/// in the numbers Findings, the service and the audit hold. An agent is
/// not a tool: it records. So the first row is what it has seen, and the
/// row's verbs are the same Clean Caches and Redact Findings runs
/// (design/scan-and-protect.md D10, revised 2026-09-22: a digest nobody
/// acts from is a digest nobody reads, which is how one stayed green over
/// 34 copies).
struct AgentsView: View {
    @ObservedObject var model: MenuModel
    let actions: AgentsActions

    var body: some View {
        let board = AgentsBoard.make(model)
        VStack(spacing: 0) {
            if let outcome = model.agentsOutcome {
                WindowBanner(tint: Color(outcome.failed ? StatusMark.red : StatusMark.green), text: outcome.title) {
                    Button("What jit Did…") { actions.openSheet(.result(title: outcome.title, text: outcome.text)) }
                        .buttonStyle(AppButton(kind: .plain))
                }
            }
            VStack(spacing: 0) {
                header(board)
                body(board)
            }
            .measureWindowHeight()
            footer(board)
        }
        .frame(
            minWidth: Win.width, maxWidth: .infinity,
            minHeight: Win.minimum(Win.height), maxHeight: .infinity,
            alignment: .top
        )
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onPreferenceChange(WindowHeightKey.self) { height in
            actions.fit(height + Self.chrome(banner: model.agentsOutcome != nil))
        }
        .sheet(item: $model.agentsSheet) { sheet in
            switch sheet {
            case let .result(title, text):
                ResultSheet(title: title, text: text, close: actions.closeSheet)
            case .wrap, .handWrap, .scanDepth:
                // The Tools and Findings windows' questions; never opened here.
                EmptyView()
            }
        }
        .onAppear(perform: actions.reload)
    }

    /// The regions outside the measured header and body: the footer, and
    /// the banner when one is up.
    static func chrome(banner: Bool) -> CGFloat {
        37 + (banner ? 39 : 0)
    }

    // MARK: - Header

    /// What you are looking at, then one line per agent that asks
    /// something, then where the facts come from. One menu on the right:
    /// scanning is Findings' verb, and the sentence links there.
    private func header(_ board: AgentsBoard) -> some View {
        HStack(alignment: .top, spacing: Win.s5) {
            WindowMark(tint: Color(board.tier.tint), hollow: !board.scanned && board.hasAgents)
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(Format.agentsHeadline(board, apps: model.connectableApps.count)).font(Win.head)
                if board.hasAgents {
                    HeaderTodoLines(todos: todos(board)).padding(.top, Win.s2)
                }
                Text(Format.agentsSubline(board)).font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, board.hasAgents ? Win.s3 : 0)
            }
            Spacer(minLength: Win.s5)
            HStack(spacing: Win.s3) {
                if model.scanning || model.toolsRefreshing {
                    ProgressView().controlSize(.small)
                }
                moreMenu
            }
            .padding(.top, Win.s1)
        }
        .windowRegion()
    }

    /// One line per agent with copies in its files; the verbs are the
    /// card's own, so the line scrolls to nothing and just acts.
    private func todos(_ board: AgentsBoard) -> [HeaderTodo] {
        board.rows.compactMap { row in
            guard let text = row.card.todo else {
                return nil
            }
            let verb = row.card.offersClean ? "clear the copies" : "redact the tokens"
            return HeaderTodo(id: row.id, text: text, verb: verb, tint: Color(StatusMark.red)) {
                if row.card.offersClean {
                    actions.cleanCaches()
                } else {
                    actions.redact(row.agent)
                }
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Refresh", action: actions.reload).disabled(model.toolsRefreshing)
            Divider()
            Button("Findings…", action: actions.openScan)
            Button("Tools…", action: actions.openTools)
            Button("Audit…") { actions.openAudit(nil) }
            Button("Grants…", action: actions.openGrants)
            Button("Settings…", action: actions.openSettings)
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton())
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Body

    @ViewBuilder
    private func body(_ board: AgentsBoard) -> some View {
        if !board.hasAgents, model.connectableApps.isEmpty, model.toolListing != nil, model.toolsMessage == nil {
            noAgents
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Win.s5) {
                    if let message = model.toolsMessage {
                        failed(message)
                    }
                    ForEach(board.rows) { row in
                        agentCard(row, scanned: board.scanned)
                    }
                    ForEach(model.connectableApps) { app in
                        appCard(app)
                    }
                }
                .padding(Win.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    private var noAgents: some View {
        WindowEmptyState(
            tint: Color(StatusMark.green),
            hollow: true,
            title: "No AI agent CLI on this Mac",
            message: "jit wraps " + ToolRecord.agentTools.sorted().prefix(4).joined(separator: ", ")
                + " and others. Install one and it shows up here, with what is in its files, what it can reach and what it did."
        ) {
            Button("Tools…", action: actions.openTools).buttonStyle(AppButton())
        }
    }

    // MARK: - Footer

    /// The footer states; it configures nothing.
    private func footer(_ board: AgentsBoard) -> some View {
        HStack(spacing: Win.s4) {
            StateDot(tint: Color(board.tier.tint))
            Text(Format.agentsFooter(board, activity: model.agentActivity, apps: model.connectableApps.count)).font(Win.sub)
                .foregroundStyle(.secondary).lineLimit(1)
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
    /// Clean every agent's caches: the same command and dialog Findings runs.
    var cleanCaches: () -> Void = {}
    /// Redact the tokens in this agent's files: Findings' Redact, narrowed.
    var redact: (ToolRecord) -> Void = { _ in }
    var setRedactAfterScan: (ToolRecord, Bool) -> Void = { _, _ in }
    var openGrants: () -> Void = {}
    var openAIJobs: () -> Void = {}
    var connectApp: (MCPApp) -> Void = { _ in }
    var disconnectApp: (MCPApp) -> Void = { _ in }
    var openScan: () -> Void = {}
    var openSettings: () -> Void = {}
    var openTools: () -> Void = {}
    /// The audit, narrowed to what this agent launched when a tool is given.
    var openAudit: (ToolRecord?) -> Void = { _ in }
    /// The window asks to be the height of what it holds.
    var fit: (CGFloat) -> Void = { _ in }
}

/// What just happened in a window, for its banner: the sentence, jit's
/// own words behind "What jit Did…", whether it failed, and the files an
/// Undo would restore.
struct WindowOutcome: Equatable {
    var title: String
    var text: String
    var failed = false
    var undo: [String] = []
}
