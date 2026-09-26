// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Tools window: what runs through jit, and is it working. One card
/// per state — Fix now, Silent, Working — one row per wrapped tool with
/// what jit hands it and one fact from the audit: last use, other
/// readers, sessions. A key still in the open is Findings' fact and
/// appears here only as a line in the header pointing there — except a
/// token in a tool's own keychain, which the scan cannot see yet, whose
/// line wraps it from here. No catalogue: a tool that is not on this Mac
/// is not a fact about this Mac (docs/design/mockups/Agents-Tools-Files).
struct ToolsView: View {
    @ObservedObject var model: MenuModel
    let actions: ToolsActions

    var body: some View {
        let board = ToolsBoard.make(model)
        VStack(spacing: 0) {
            if board.hasWraps || !board.known.isEmpty {
                header(board)
                ScrollView {
                    VStack(alignment: .leading, spacing: Win.s5) {
                        if let message = model.toolsMessage {
                            failed(message)
                        }
                        ForEach(ToolsBoard.tiers, id: \.self) { tier in
                            let rows = board.rows.filter { $0.card.tier == tier }
                            if !rows.isEmpty {
                                card(tier, rows)
                            }
                        }
                        if !board.known.isEmpty {
                            knownCard(board.known)
                        }
                    }
                    .padding(Win.s6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                empty(board)
            }
            footer(board)
        }
        .frame(minWidth: Win.width, maxWidth: .infinity, minHeight: Win.minimum(Win.height), maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .sheet(item: $model.toolsSheet) { sheet in
            switch sheet {
            case let .wrap(tool):
                if let record = model.toolListing?.tool(named: tool) {
                    WrapSheet(model: model, actions: actions, tool: record)
                }
            case .handWrap:
                HandWrapSheet(model: model, actions: actions)
            case let .result(title, text):
                ResultSheet(title: title, text: text, close: actions.closeSheet)
            case .scanDepth, .changes:
                // Findings' sheets; never opened here.
                EmptyView()
            }
        }
        .onAppear(perform: actions.reload)
    }

    // MARK: - Header

    private func header(_ board: ToolsBoard) -> some View {
        HStack(alignment: .top, spacing: Win.s5) {
            WindowMark(tint: Color(board.tint))
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(Format.toolsHeadline(board)).font(Win.head)
                let todos = todos(board)
                if !todos.isEmpty {
                    HeaderTodoLines(todos: todos).padding(.top, Win.s2)
                }
                Text(Format.toolsSubline(board)).font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, todos.isEmpty ? 0 : Win.s3)
            }
            Spacer(minLength: Win.s5)
            HStack(spacing: Win.s3) {
                if model.toolsRefreshing || model.toolsBusy != nil {
                    ProgressView().controlSize(.small)
                }
                Button("Wrap Another…") { actions.openSheet(.handWrap) }.buttonStyle(AppButton()).disabled(model.toolsBusy != nil)
                    .help("A tool jit's catalog does not know, which reads a token from an environment variable.")
                moreMenu
            }
            .padding(.top, Win.s1)
        }
        .windowRegion()
    }

    private func todos(_ board: ToolsBoard) -> [HeaderTodo] {
        var lines: [HeaderTodo] = []
        for row in board.rows {
            guard let text = row.card.todo else {
                continue
            }
            switch row.card.verb {
            case let .logIn(mint):
                lines
                    .append(HeaderTodo(id: "session:" + row.id, text: text, verb: "log in again", tint: Color(StatusMark.red)) {
                        actions.mintInTerminal(mint)
                    })
            case .repair:
                lines
                    .append(HeaderTodo(id: "repair:" + row.id, text: text, verb: "repair it", tint: Color(StatusMark.red)) {
                        actions.openSheet(.wrap(tool: row.id))
                    })
            default:
                lines.append(HeaderTodo(
                    id: "silent:" + row.id,
                    text: text,
                    verb: "check with Doctor",
                    tint: Color(StatusMark.amber),
                    action: actions.openDoctor
                ))
            }
        }
        for tool in board.toWrap {
            let line = Format.toolKeyLine(tool, scan: model.macScan)
            let tint = line.wrapsHere ? Color(.tertiaryLabelColor) : Color(StatusMark.amber)
            lines.append(HeaderTodo(id: "key:" + tool.tool, text: line.text, verb: line.verb, tint: tint) {
                if line.wrapsHere {
                    actions.openSheet(.wrap(tool: tool.tool))
                } else {
                    actions.openScan()
                }
            })
        }
        return lines
    }

    private var moreMenu: some View {
        Menu {
            Button("Refresh", action: actions.reload).disabled(model.toolsRefreshing)
            Divider()
            Button("Findings…", action: actions.openScan)
            Button("Doctor…", action: actions.openDoctor)
            Button("Vault…", action: actions.openVault)
            Button("AI Jobs…", action: actions.openAIJobs)
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton())
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Cards

    private func card(_ tier: ToolCard.Tier, _ rows: [ToolsBoard.Row]) -> some View {
        AppCard(
            eyebrow: Format.toolTierWord(tier),
            eyebrowTint: Color(ToolsBoard.tint(tier)),
            title: Format.toolTierTitle(tier, count: rows.count),
            note: Format.toolTierNote(tier)
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    toolRow(row, last: index == rows.count - 1)
                }
            }
        }
    }

    private func toolRow(_ row: ToolsBoard.Row, last: Bool) -> some View {
        let busy = model.toolsBusy != nil
        return AppRow(name: row.tool.tool, detail: row.card.detail, fact: row.card.fact, last: last) {
            if model.toolsBusy == row.tool.tool {
                Text("Touch ID…").font(Win.sub).foregroundStyle(.secondary)
            }
            switch row.card.verb {
            case .repair:
                Button("Repair…") { actions.openSheet(.wrap(tool: row.tool.tool)) }.buttonStyle(AppButton(kind: .secondary)).disabled(busy)
            case let .logIn(mint):
                Button("Log In…") { actions.mintInTerminal(mint) }.buttonStyle(AppButton(kind: .secondary)).disabled(busy)
                    .help("Runs `\(mint)` in your terminal: a fresh login with your MFA, caught into the vault.")
            case .verify:
                Button("Verify") { actions.verify(row.tool.tool) }.buttonStyle(AppButton()).disabled(busy)
            case .none:
                EmptyView()
            }
            Menu {
                if !row.tool.injects.isEmpty {
                    Button("Show in Vault", action: actions.openVault)
                }
                if row.tool.wrapped, !row.tool.isNative {
                    Button("Unwrap…") { actions.unwrap(row.tool.tool) }.disabled(busy)
                }
            } label: {
                Text("···")
            }
            .menuStyle(.button).buttonStyle(AppButton()).menuIndicator(.hidden).fixedSize()
        }
    }

    /// The tools jit recognises on this Mac and does not run yet: what
    /// each one's credential is, where its key sits, and the one verb that
    /// changes that — Wrap for a key jit can take from here, Protect for a
    /// file Findings would protect the same way.
    private func knownCard(_ tools: [ToolRecord]) -> some View {
        let busy = model.toolsBusy != nil
        return AppCard(
            eyebrow: "On this Mac", eyebrowTint: Color(.tertiaryLabelColor),
            title: Format.count(tools.count, "tool") + " jit recognises, not through it yet",
            note: Format.knownToolsNote
        ) {
            EmptyView()
        } rows: {
            AppCardRows {
                ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                    AppRow(name: tool.tool, fact: Format.knownToolFact(tool, scan: model.macScan), last: index == tools.count - 1) {
                        if model.toolsBusy == tool.tool {
                            Text("Touch ID…").font(Win.sub).foregroundStyle(.secondary)
                        } else if tool.isNative {
                            if tool.keyState(scan: model.macScan).needsAction {
                                Button("Protect…") { actions.protect(tool.tool) }.buttonStyle(AppButton(kind: .secondary)).disabled(busy)
                            }
                        } else if tool.isGrant, !tool.mountMigrated {
                            if case let .found(path) = tool.keyState(scan: model.macScan) {
                                Button("Protect…") { actions.protectFile(path) }.buttonStyle(AppButton(kind: .secondary)).disabled(busy)
                            }
                        } else {
                            Button("Wrap…") { actions.openSheet(.wrap(tool: tool.tool)) }.buttonStyle(AppButton(kind: .secondary))
                                .disabled(busy)
                        }
                    }
                }
            }
        }
    }

    private func failed(_ message: String) -> some View {
        AppCard(
            eyebrow: "Fix now", eyebrowTint: Color(StatusMark.red),
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

    // MARK: - Empty

    private func empty(_ board: ToolsBoard) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            WindowEmptyState(
                tint: Color(StatusMark.amber), hollow: true,
                title: board.listing == nil ? "Reading…" : "Nothing runs through jit yet",
                message: Format.toolsEmptyMessage(board, scan: model.macScan)
            ) {
                if !board.toWrap.isEmpty {
                    Button("Findings…", action: actions.openScan).buttonStyle(AppButton())
                }
                Button("Wrap Another…") { actions.openSheet(.handWrap) }.buttonStyle(AppButton()).disabled(model.toolsBusy != nil)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer

    private func footer(_ board: ToolsBoard) -> some View {
        HStack(spacing: Win.s4) {
            StateDot(tint: Color(board.tint))
            Text(Format.toolsFooter(board)).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: Win.s5)
        }
        .padding(.horizontal, Win.s6)
        .padding(.vertical, Win.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.hover)
        .overlay(alignment: .top) { Rectangle().fill(WindowSurface.separator).frame(height: 1) }
    }
}

/// What the Tools window is looking at, worked out once.
struct ToolsBoard {
    struct Row: Identifiable {
        let tool: ToolRecord
        let card: ToolCard
        var id: String {
            tool.tool
        }
    }

    static let tiers: [ToolCard.Tier] = [.fixNow, .silent, .working]

    var listing: ToolListing?
    /// Every tool that runs through jit: wrapped, or native and protected.
    var rows: [Row] = []
    /// Installed tools with a key jit could take: Findings' fact, or the
    /// keychain's, which only the listing sees.
    var toWrap: [ToolRecord] = []
    /// Every installed tool jit recognises and does not run yet — a fact
    /// about this Mac, unlike the catalogue of tools it cannot see.
    var known: [ToolRecord] = []
    var installed = 0
    var activity: [String: ToolActivity] = [:]

    var hasWraps: Bool {
        !rows.isEmpty
    }

    var needingYou: Int {
        rows.filter { $0.card.tier != .working }.count
    }

    var tint: NSColor {
        if rows.contains(where: { $0.card.tier == .fixNow }) {
            return StatusMark.red
        }
        if rows.contains(where: { $0.card.tier == .silent }) || toWrap.contains(where: { $0.keyState(scan: nil).needsAction }) {
            return StatusMark.amber
        }
        return rows.isEmpty ? StatusMark.amber : StatusMark.green
    }

    static func tint(_ tier: ToolCard.Tier) -> NSColor {
        switch tier {
        case .fixNow: StatusMark.red
        case .silent: StatusMark.amber
        case .working: StatusMark.green
        }
    }

    @MainActor
    static func make(_ model: MenuModel) -> ToolsBoard {
        var board = ToolsBoard()
        board.listing = model.toolListing
        board.activity = model.toolActivity
        let tools = (model.toolListing?.others ?? [])
        board.installed = tools.count
        board.rows = tools.filter { $0.wrapped || $0.isProtected }.map { tool in
            Row(
                tool: tool,
                card: ToolCard.make(tool, sessions: model.cli?.sessions(mintedBy: tool.tool) ?? [], activity: model.toolActivity[tool.tool])
            )
        }
        // A key in a file is Findings' fact and amber; a token in the
        // tool's own keychain is encrypted at rest, so its line is an
        // offer, grey, and only this listing can see it.
        board.toWrap = tools.filter { !$0.wrapped && !$0.isProtected && $0.keyState(scan: model.macScan).found }
        board.known = tools.filter { !$0.wrapped && !$0.isProtected }
        return board
    }
}

struct ToolsActions {
    var reload: () -> Void = {}
    var openSheet: (ToolsSheet) -> Void = { _ in }
    var closeSheet: () -> Void = {}
    /// tool, and the key to store first when jit has nothing to discover
    var wrap: (String, String?) -> Void = { _, _ in }
    /// tool, variable, key: store the key at wrap-<tool>/VAR, then wrap add
    var handWrap: (String, String, String) -> Void = { _, _, _ in }
    var protect: (String) -> Void = { _ in }
    /// migrate one credential file, for a grant tool whose mount is not there yet
    var protectFile: (String) -> Void = { _ in }
    var unwrap: (String) -> Void = { _ in }
    var verify: (String) -> Void = { _ in }
    var mintInTerminal: (String) -> Void = { _ in }
    var cleanCaches: () -> Void = {}
    var openVault: () -> Void = {}
    var openSettings: () -> Void = {}
    var openScan: () -> Void = {}
    var openDoctor: () -> Void = {}
    var openAIJobs: () -> Void = {}
}
