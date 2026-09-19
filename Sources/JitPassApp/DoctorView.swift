// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Doctor: the findings `jit doctor` reports, as cards grouped by impact
/// (`DoctorBoard`). A header says what is wrong in the user's words, tabs
/// narrow to one tier, and each card has one primary button and a ⋯ menu.
/// A button runs the jit command doctor named: in the app when it can run
/// unattended (every y/N pre-answered, any value typed into a hidden
/// field), in the terminal otherwise, where jit's own confirmations apply.
/// One action at a time: while one runs, or a check, every button is
/// disabled and the running card says so; after, it shows how it ended
/// until the recheck takes it away.
struct DoctorView: View {
    @ObservedObject var model: MenuModel
    @ObservedObject var progress: DoctorProgress
    let actions: DoctorActions
    /// nil is All.
    @State private var tab: DoctorBoard.Tier?
    @State private var reviewing = false

    var body: some View {
        let board = model.doctor.map { DoctorBoard.make($0) }
        VStack(alignment: .leading, spacing: 0) {
            header(board)
            if let board, board.isEmpty, progress.outcome == nil {
                allGood
            } else if let board {
                tabs(board)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(DoctorBoard.Tier.allCases) { tier in
                            if tab == nil || tab == tier {
                                section(tier, shown(board, tier))
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
                }
            } else {
                Spacer()
            }
            footer
        }
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .sheet(isPresented: $reviewing) {
            DoctorReviewSheet(model: model, actions: actions) { reviewing = false }
        }
    }

    // MARK: - Header

    private func header(_ board: DoctorBoard?) -> some View {
        HStack(alignment: .center, spacing: 14) {
            DoctorMark(color: markColor(board), size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(board?.headline ?? (model.doctorRunning ? "Checking…" : "Doctor"))
                    .font(.system(size: 17, weight: .bold))
                if let subline = board?.subline {
                    Text(subline).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
                ForEach(notices, id: \.self) { notice in
                    Text(notice).font(.system(size: 12)).foregroundStyle(Color(StatusMark.red))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if model.doctorRunning {
                ProgressView().controlSize(.small)
            }
            Button("Check Again", action: actions.recheck).disabled(!idle)
            Menu {
                Button("Open in Terminal", action: actions.openInTerminal)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    /// What went wrong outside any card: an action from the Review sheet,
    /// a dry run that failed, a check that gave no report.
    private var notices: [String] {
        var out = model.doctorMessage.map { [$0] } ?? []
        if model.doctorFailed, !model.doctorRunning {
            out.append(model.doctor == nil
                ? "jit doctor gave no report."
                : "jit doctor gave no report; the findings below are from an earlier check.")
        }
        return out
    }

    private func markColor(_ board: DoctorBoard?) -> Color {
        switch board?.mark {
        case .red: Color(StatusMark.red)
        case .amber: Color(StatusMark.amber)
        case .green: Color(StatusMark.green)
        case nil: Color.secondary
        }
    }

    /// Nothing running: no action, no check.
    private var idle: Bool {
        model.doctorBusy == nil && !model.doctorRunning
    }

    // MARK: - Tabs

    private func tabs(_ board: DoctorBoard) -> some View {
        HStack(spacing: 2) {
            tabButton(nil, "All", board.cards.count)
            ForEach(DoctorBoard.Tier.allCases) { tier in
                tabButton(tier, tier.title, board.cards(in: tier).count)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.08)))
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private func tabButton(_ tier: DoctorBoard.Tier?, _ title: String, _ count: Int) -> some View {
        let selected = tab == tier
        return Button {
            tab = tier
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.18) : Color.clear)
                    .shadow(color: .black.opacity(selected ? 0.25 : 0), radius: 1, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(tier != nil && count == 0)
        .opacity(tier != nil && count == 0 ? 0.45 : 1)
    }

    // MARK: - Sections

    /// The tier's cards, and in front of them a card the recheck took away
    /// while it still shows that it is done.
    private func shown(_ board: DoctorBoard, _ tier: DoctorBoard.Tier) -> [DoctorCard] {
        var cards = board.cards(in: tier)
        guard let outcome = progress.outcome, outcome.state == .done, outcome.card.tier == tier else {
            return cards
        }
        if !cards.contains(where: { $0.id == outcome.card.id }) {
            cards.insert(outcome.card, at: 0)
        }
        return cards
    }

    @ViewBuilder
    private func section(_ tier: DoctorBoard.Tier, _ cards: [DoctorCard]) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle().fill(tierColor(tier)).frame(width: 8, height: 8)
                    Text(tier.title).font(.system(size: 13, weight: .semibold))
                    Text("\(cards.count)").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                if tier == .tidy {
                    DoctorTidyList(cards: cards, state: state, onButton: handle)
                } else {
                    ForEach(cards) { card in
                        DoctorCardView(card: card, state: state(card.id), rowState: state, onButton: handle)
                    }
                }
            }
        }
    }

    private func tierColor(_ tier: DoctorBoard.Tier) -> Color {
        switch tier {
        case .broken: Color(StatusMark.red)
        case .recommended: Color(StatusMark.amber)
        case .tidy: Color.secondary.opacity(0.6)
        }
    }

    /// A card's or a row's state: how its fix ended, else whether it is
    /// running, else whether its buttons may be pressed.
    private func state(_ key: String) -> DoctorCardState {
        if let outcome = progress.outcome, outcome.key == key {
            return outcome.state == .done
                ? .done(title: outcome.title, line: outcome.line)
                : .failed(title: outcome.title, line: outcome.line, retry: outcome.button)
        }
        if model.doctorBusy == key {
            return .working(presence: progress.presence)
        }
        return .idle(enabled: idle)
    }

    private func handle(_ button: DoctorButton, _ card: DoctorCard, _ key: String) {
        if button.command == .review {
            reviewing = true
        } else {
            actions.run(button, card, key)
        }
    }

    // MARK: - Nothing to fix, and the footer

    private var allGood: some View {
        VStack(spacing: 12) {
            Spacer()
            DoctorMark(color: Color(StatusMark.green), size: 56)
            Text("Nothing needs you").font(.system(size: 20, weight: .bold))
            Text("Every profile's secrets are in the vault, every tool finds its profile, and the service runs this build of jit.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 420).fixedSize(horizontal: false, vertical: true)
            Button("Check Again", action: actions.recheck).disabled(!idle).padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(footerColor).frame(width: 6, height: 6)
            Text(footerText).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Open in Terminal", action: actions.openInTerminal).buttonStyle(.link)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider() }
    }

    /// "jit 2.0.0 · signed CZC6BH93GJ · 22 profiles, 68 secrets checked at 15:16".
    private var footerText: String {
        guard let report = model.doctor else {
            return model.doctorRunning ? "Checking…" : "Not checked yet"
        }
        return Format.doctorSummary(report) + (model.doctorAt.map { " at " + Format.clock($0) } ?? "")
    }

    /// The jit that answered: green signed, amber not, red no answer.
    private var footerColor: Color {
        if model.doctorFailed {
            return Color(StatusMark.red)
        }
        guard let signature = model.doctor?.tool?.signature else {
            return Color.secondary
        }
        return signature.hasPrefix("signed") ? Color(StatusMark.green) : Color(StatusMark.amber)
    }
}

/// The running fix's Touch ID flag and how the last fix ended, apart from
/// MenuModel: only the Doctor window reads them.
@MainActor
final class DoctorProgress: ObservableObject {
    /// The running action asks for Touch ID, so the card says it waits.
    @Published var presence = false
    @Published var outcome: DoctorOutcome?
}

/// The jitpass mark in a state colour: a dot in a soft ring.
struct DoctorMark: View {
    var color: Color
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.22))
            Circle().fill(color).padding(size * 0.22)
        }
        .frame(width: size, height: size)
    }
}

struct DoctorActions {
    var recheck: () -> Void = {}
    var openInTerminal: () -> Void = {}
    /// A Review sheet row's action, and the finding it belongs to, which
    /// shows as busy while it runs.
    var perform: (DoctorAction, String) -> Void = { _, _ in }
    /// A card's button, the card, and the key (the card's id, or its row's)
    /// that shows the fix running and how it ended.
    var run: (DoctorButton, DoctorCard, String) -> Void = { _, _, _ in }
}
