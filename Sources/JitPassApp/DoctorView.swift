// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Doctor: the findings `jit doctor` reports, as cards grouped by impact
/// (`DoctorBoard`). A header says what is wrong in the user's words, a
/// filter narrows to one tier, and each card carries its tier in its own
/// eyebrow, its rows, and a ⋯ menu.
///
/// Nothing here opens a terminal, and nothing shows one. A fix runs in the
/// app, asks its one question in a sheet, and answers in the row that
/// asked: the black output pane, the footer's Open in Terminal and the
/// same entry in every ⋯ menu are gone. A command that genuinely cannot
/// run unattended (a tool log-in) still says so on its own button.
///
/// One action at a time: while one runs, or a check, every button is
/// disabled and the running row says so; after, it shows how it ended
/// until the recheck takes it away.
struct DoctorView: View {
    @ObservedObject var model: MenuModel
    @ObservedObject var progress: DoctorProgress
    let actions: DoctorActions
    @State private var tab = DoctorTab.all

    var body: some View {
        let board = model.doctor.map { DoctorBoard.make($0, offersVaultKeyMove: model.offersVaultKeyMove) }
        VStack(alignment: .leading, spacing: 0) {
            header(board)
            if let board, board.isEmpty, progress.outcome == nil, board.showing(tab) != .ignored {
                allGood(board)
            } else if let board {
                filter(board)
                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Space.five) {
                        ForEach(shown(board), id: \.id) { card in
                            DoctorCardView(card: card, state: state(card.id), rowState: state, onButton: handle)
                        }
                        if board.showing(tab) == .ignored {
                            DoctorIgnoredList(rows: board.ignored, state: state, onShowAgain: actions.showAgain)
                        }
                    }
                    .padding(Design.Space.six)
                    .measureDoctorHeight()
                }
            } else {
                Spacer()
            }
            footer
        }
        .frame(
            minWidth: Design.Window.minimum(for: Design.Window.medium).width, maxWidth: .infinity,
            minHeight: Design.Window.minimum(for: Design.Window.medium).height, maxHeight: .infinity
        )
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        // The last ignored row shown again: the tab goes, so does its
        // selection. Nothing else ever switches tabs for the user.
        .onChange(of: model.doctor) { _, report in
            if tab == .ignored, report?.ignored.isEmpty ?? true {
                tab = .all
            }
        }
        .onPreferenceChange(DoctorHeightKey.self) { height in
            actions.fit(height)
        }
        .sheet(item: $model.doctorSheet) { sheet in
            switch sheet {
            case .review:
                DoctorReviewSheet(model: model, actions: actions) { model.doctorSheet = nil }
            case let .confirm(request):
                DoctorConfirmSheet(request: request, answer: actions.answer)
            case let .output(output):
                DoctorOutputSheet(output: output) { model.doctorSheet = nil }
            }
        }
    }

    /// Header, filter and footer: what the window is, above and below the
    /// findings it asks to be sized to.
    static let chrome: CGFloat = 140

    // MARK: - Header

    private func header(_ board: DoctorBoard?) -> some View {
        HStack(alignment: .center, spacing: Design.Space.five) {
            DoctorMark(color: markColor(board), size: Design.Size.mark)
            VStack(alignment: .leading, spacing: Design.Space.one) {
                Text(board?.headline ?? (model.doctorRunning ? "Checking…" : "Doctor"))
                    .font(Design.Text.windowHead).foregroundStyle(Design.Label.primary)
                if let subline = board?.subline {
                    Text(subline).font(Design.Text.windowSub).foregroundStyle(Design.Label.secondary).lineLimit(2)
                }
                ForEach(notices, id: \.self) { notice in
                    Text(notice).font(Design.Text.windowSub).foregroundStyle(Color(StatusMark.red))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Design.Space.five)
            if model.doctorRunning {
                ProgressView().controlSize(.small)
            }
            Button("Check Again", action: actions.recheck).disabled(!idle).font(Design.Text.button)
            Menu {
                // What Open in Terminal was really asked for: the findings
                // somewhere else. This hands them over as text instead of
                // asking the reader to run the check a second time.
                Button("Copy Report", action: actions.copyReport).disabled(board == nil)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.horizontal, Design.Space.six)
        .padding(.vertical, Design.Space.five)
        .overlay(alignment: .bottom) { Divider() }
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

    // MARK: - Filter

    private func filter(_ board: DoctorBoard) -> some View {
        let selected = board.showing(tab)
        return HStack(spacing: Design.Space.one) {
            ForEach(board.tabs) { item in
                filterButton(item, selected: selected == item.tab)
            }
        }
        .padding(Design.Space.one)
        .background(RoundedRectangle(cornerRadius: Design.Radius.callout, style: .continuous).fill(Design.Surface.segmentTrack))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Space.six)
        .padding(.vertical, Design.Space.five)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func filterButton(_ item: DoctorTabItem, selected: Bool) -> some View {
        Button {
            tab = item.tab
        } label: {
            HStack(spacing: Design.Space.three) {
                Text(item.title).foregroundStyle(selected ? Design.Label.primary : Design.Label.secondary)
                Text("\(item.count)").foregroundStyle(Design.Label.tertiary).monospacedDigit()
            }
            .font(Design.Text.button)
            .padding(.horizontal, Design.Space.five)
            .padding(.vertical, Design.Space.two)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.segment, style: .continuous)
                    .fill(selected ? Design.Surface.segmentOn : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cards

    /// The cards the filter shows, in tier order, and in front of them a
    /// card the recheck took away while it still says it is done.
    private func shown(_ board: DoctorBoard) -> [DoctorCard] {
        var cards = board.cards.filter { board.shows($0.tier, on: tab) }
        guard let outcome = progress.outcome, outcome.state == .done,
              board.shows(outcome.card.tier, on: tab), !cards.contains(where: { $0.id == outcome.card.id })
        else {
            return cards
        }
        cards.insert(outcome.card, at: 0)
        return cards
    }

    /// A card's or a row's state: how its fix ended, else whether it is
    /// running, else whether its buttons may be pressed.
    private func state(_ key: String) -> DoctorCardState {
        if let outcome = progress.outcome, outcome.key == key {
            return outcome.state == .done
                ? .done(title: outcome.title, line: outcome.line)
                : .failed(title: outcome.title, line: outcome.line, said: outcome.said, retry: outcome.button)
        }
        if model.doctorBusy == key {
            return .working(presence: progress.presence)
        }
        return .idle(enabled: idle)
    }

    private func handle(_ button: DoctorButton, _ card: DoctorCard, _ key: String) {
        if button.command == .review {
            model.doctorSheet = .review
        } else {
            actions.run(button, card, key)
        }
    }

    // MARK: - Nothing to fix, and the footer

    private func allGood(_ board: DoctorBoard) -> some View {
        VStack(spacing: Design.Space.five) {
            DoctorMark(color: Color(StatusMark.green), size: Design.Size.markLarge)
            Text("Nothing needs you").font(Design.Text.emptyTitle).foregroundStyle(Design.Label.primary)
            Text("Every profile's secrets are in the vault, every tool finds its profile, and the service runs this build of jit.")
                .font(Design.Text.windowSub).foregroundStyle(Design.Label.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 400).fixedSize(horizontal: false, vertical: true)
            Button("Check Again", action: actions.recheck).disabled(!idle).font(Design.Text.button)
            // The one other way to the Ignored tab: nothing else is on
            // screen to hold it.
            if !board.ignored.isEmpty {
                Button("\(board.ignored.count) ignored") { tab = .ignored }
                    .buttonStyle(.link).font(Design.Text.button)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .measureDoctorHeight()
    }

    /// What answered and when. The footer states; it never links out. One
    /// that offers to open a terminal is saying the window did not work.
    private var footer: some View {
        HStack(spacing: Design.Space.four) {
            Circle().fill(footerColor).frame(width: Design.Size.dot, height: Design.Size.dot)
            Text(footerText).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Design.Space.four)
        }
        .font(Design.Text.rowFact)
        .foregroundStyle(Design.Label.secondary)
        .padding(.horizontal, Design.Space.six)
        .padding(.vertical, Design.Space.four)
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

/// How tall the findings are, so the window can open at the height of
/// what it found instead of a fixed 720 with 330 of nothing below the
/// last card.
struct DoctorHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func measureDoctorHeight() -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: DoctorHeightKey.self, value: proxy.size.height)
        })
    }
}

/// The running fix's Touch ID flag and how the last fix ended, apart from
/// MenuModel: only the Doctor window reads them.
@MainActor
final class DoctorProgress: ObservableObject {
    /// The running action asks for Touch ID, so the row says it waits.
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
    /// The findings as text, for a ticket or a colleague.
    var copyReport: () -> Void = {}
    /// A Review sheet row's action, and the finding it belongs to, which
    /// shows as busy while it runs.
    var perform: (DoctorAction, String) -> Void = { _, _ in }
    /// A card's button, the card, and the key (the card's id, or its row's)
    /// that shows the fix running and how it ended.
    var run: (DoctorButton, DoctorCard, String) -> Void = { _, _, _ in }
    /// An ignored row's Show Again, and the row's id.
    var showAgain: (DoctorButton, String) -> Void = { _, _ in }
    /// The confirm sheet's answer: true runs what it asked about.
    var answer: (Bool) -> Void = { _ in }
    /// How tall the window would like to be.
    var fit: (CGFloat) -> Void = { _ in }
}
