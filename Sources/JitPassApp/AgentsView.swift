// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The AI Agents window, built from the window system (the design
/// system's Windows page): banner, header, body at one inset, footer. It
/// is a digest (design/scan-and-protect.md D10): one row per agent, four
/// facts in a fixed order, each read from its home — Tools, Findings,
/// Decoys, Grants — and one link to the home of the fact that needs the
/// reader. It answers the one question no other window puts in a
/// sentence, "what is this agent doing on my Mac", and owns no fact and
/// no verb of its own: two windows acting on one fact is where "Protect
/// cleared my AI-cache alerts" came from.
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
            header(board)
            body(board)
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
                // The Tools and Findings windows' questions; never opened
                // from a digest.
                EmptyView()
            }
        }
        .onAppear(perform: actions.reload)
    }

    /// The regions above and below the body, which the window adds to the
    /// height the body asks for.
    static func chrome(banner: Bool) -> CGFloat {
        112 + (banner ? 39 : 0)
    }

    // MARK: - Header

    /// What you are looking at, counted once, and the one sentence that
    /// changes how the rows are read: every fact has a home elsewhere.
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
                Button("Scan Now…", action: actions.scanNow)
                    .buttonStyle(AppButton()).disabled(model.scanning)
                moreMenu
            }
            .padding(.top, Win.s1)
        }
        .windowRegion()
    }

    /// The homes this window reads from, in one menu.
    private var moreMenu: some View {
        Menu {
            Button("Refresh Listing", action: actions.reload).disabled(model.toolsRefreshing)
            Divider()
            Button("Tools…", action: actions.openTools)
            Button("Findings…", action: actions.openScan)
            Button("Audit…", action: actions.openAudit)
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
        if !board.hasAgents, model.toolListing != nil, model.toolsMessage == nil {
            noAgents.measureWindowHeight()
            Spacer(minLength: 0)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Win.s5) {
                    if let message = model.toolsMessage {
                        failed(message)
                    }
                    if board.hasAgents {
                        digestCard(board)
                    }
                }
                .padding(Win.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .measureWindowHeight()
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
                + " and others. Install one and it shows up here, with its key, its caches, its reads and its grant."
        ) {
            Button("Tools…", action: actions.openTools).buttonStyle(AppButton())
        }
    }

    // MARK: - Footer

    /// The one runtime fact that is about every agent at once: whether
    /// they have to ask. Settings is where it changes.
    private func footer(_ board: AgentsBoard) -> some View {
        HStack(spacing: Win.s4) {
            StateDot(tint: Color(board.consent == false ? StatusMark.amber : board.tier.tint))
            Text(Format.askingFact(board)).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: Win.s5)
            Button("Settings…", action: actions.openSettings).buttonStyle(AppButton())
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
    var scanNow: () -> Void = {}
    var openGrants: () -> Void = {}
    var openScan: () -> Void = {}
    var openSettings: () -> Void = {}
    var openTools: () -> Void = {}
    var openAudit: () -> Void = {}
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
