// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Where a card's fix is: nothing running (its buttons live or not),
/// running (waiting for Touch ID, or working), or ended.
enum DoctorCardState: Equatable {
    case idle(enabled: Bool)
    case working(presence: Bool)
    case done(title: String, line: String?)
    /// `said` is jit's own last words, shown under the line in the app's
    /// type. They used to open a terminal window over the app.
    case failed(title: String, line: String?, said: String?, retry: DoctorButton)

    var enabled: Bool {
        self == .idle(enabled: true)
    }
}

typealias DoctorButtonHandler = (DoctorButton, DoctorCard, String) -> Void

/// One card: its tier in a small eyebrow, the title that says what stops
/// working, the reason why, then a row per file it lists. The section
/// headers that used to carry the tier are gone with their duplicate
/// counts — the filter above counts, and the card says which tier it is
/// in once.
///
/// Right-click on a card or row naming a file offers Show in Finder and
/// Copy Path, never a click: a mis-click must not open an editor on a
/// file that may hold plaintext.
struct DoctorCardView: View {
    let card: DoctorCard
    let state: DoctorCardState
    let rowState: (String) -> DoctorCardState
    let onButton: DoctorButtonHandler
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.four) {
            switch state {
            case let .done(title, line):
                DoctorEndedLine(done: true, title: title, line: line, said: nil)
            case let .failed(title, line, said, retry):
                DoctorEndedLine(done: false, title: title, line: line, said: said) {
                    Button("Try Again") { onButton(retry, card, card.id) }
                }
            default:
                eyebrow
                top
                rows
                disclosure
            }
        }
        .padding(Design.Space.five)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Flat: a card is a fill on the window material, no border and no
        // shadow. Surfaces do not nest past this one.
        .background(RoundedRectangle(cornerRadius: Design.Radius.panel, style: .continuous).fill(Design.Surface.card))
        .contentShape(Rectangle())
        .doctorFileMenu(card.file)
    }

    /// "● Fix now": which tier this card is in, where the card is, rather
    /// than in a header above a group of them.
    private var eyebrow: some View {
        HStack(spacing: Design.Space.three) {
            Circle().fill(Self.tierColor(card.tier)).frame(width: Design.Size.dot, height: Design.Size.dot)
            Text(card.tier.title).font(Design.Text.eyebrow).foregroundStyle(Design.Label.secondary)
            if card.changedSinceIgnored {
                Text("· was ignored, and it changed since")
                    .font(Design.Text.eyebrow).foregroundStyle(Design.Label.secondary)
            }
        }
    }

    static func tierColor(_ tier: DoctorBoard.Tier) -> Color {
        switch tier {
        case .broken: Color(StatusMark.red)
        case .recommended: Color(StatusMark.amber)
        case .tidy: Color.secondary.opacity(0.6)
        }
    }

    private var top: some View {
        HStack(alignment: .top, spacing: Design.Space.five) {
            VStack(alignment: .leading, spacing: Design.Space.one) {
                Text(card.title).font(Design.Text.cardTitle).foregroundStyle(Design.Label.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if case let .working(presence) = state {
                    DoctorWorkingLine(presence: presence)
                } else if let reason = card.reason {
                    // Capped at 62 characters: past that the eye loses the
                    // line on the way back.
                    Text(reason).font(Design.Text.cardNote).foregroundStyle(Design.Label.secondary)
                        .frame(maxWidth: CGFloat(Design.Size.noteWidth) * 7, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = card.detail {
                    Text(detail).font(Design.Text.command).foregroundStyle(Design.Label.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: Design.Space.four)
            DoctorButtons(card: card, key: card.id, enabled: state.enabled, onButton: onButton)
        }
    }

    /// A multi-row card's rows, under a hairline: one file each.
    @ViewBuilder
    private var rows: some View {
        if !card.rows.isEmpty {
            Rectangle().fill(Design.Surface.separator).frame(height: 1)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(card.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Rectangle().fill(Design.Surface.rowLine).frame(height: 1)
                    }
                    DoctorRowView(row: row, card: card, state: rowState(row.id), onButton: onButton)
                        .padding(.vertical, Design.Space.four)
                }
            }
        }
    }

    /// "Show the 7 profiles": the names in two columns, each with what is
    /// true of it.
    @ViewBuilder
    private var disclosure: some View {
        if !card.listed.isEmpty {
            Button(card.disclosure(open: open)) { open.toggle() }
                .buttonStyle(.link).font(Design.Text.button)
            if open {
                let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
                    ForEach(card.listed) { row in
                        (Text(row.name) + Text(" · \(row.note)").foregroundColor(Design.Label.secondary))
                            .font(Design.Text.command).lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(.leading, 2)
            }
        }
    }
}

/// A row of a multi-row card, with its own busy and ended states. A row
/// about a file reads as the file: its name, the folders that tell it
/// from its siblings, and the one clause that says what is true of it.
struct DoctorRowView: View {
    let row: DoctorCardRow
    let card: DoctorCard
    let state: DoctorCardState
    let onButton: DoctorButtonHandler

    var body: some View {
        HStack(alignment: row.name == nil ? .firstTextBaseline : .center, spacing: Design.Space.five) {
            switch state {
            case let .done(title, line):
                DoctorEndedLine(done: true, title: title, line: line, said: nil)
            case let .failed(title, line, said, retry):
                DoctorEndedLine(done: false, title: title, line: line, said: said) {
                    Button("Try Again") { onButton(retry, card, row.id) }
                }
            case let .working(presence):
                text
                Spacer(minLength: Design.Space.four)
                DoctorWorkingLine(presence: presence)
            case let .idle(enabled):
                text
                Spacer(minLength: Design.Space.four)
                ForEach(row.buttons) { button in
                    Button(button.title) { onButton(button, card, row.id) }
                        .font(Design.Text.button).help(button.help).disabled(!enabled)
                }
                if !row.menu.isEmpty {
                    DoctorMenuButton(entries: row.menu, help: "More for \(row.name ?? row.text)") { button in
                        onButton(button, card, row.id)
                    }
                    .disabled(!enabled)
                }
            }
        }
        .contentShape(Rectangle())
        .doctorFileMenu(row.file)
    }

    @ViewBuilder
    private var text: some View {
        if let name = row.name {
            HStack(spacing: Design.Space.five) {
                Image(systemName: "doc").font(.system(size: Design.Size.glyph * 0.8))
                    .foregroundStyle(Design.Label.primary).opacity(0.5)
                    .frame(width: Design.Size.glyph)
                VStack(alignment: .leading, spacing: Design.Space.one) {
                    // The name, then the part that tells this row from the
                    // three under it. Four rows opening on the same six
                    // words are four rows nobody can scan.
                    (Text(name).font(Design.Text.rowName).foregroundColor(Design.Label.primary)
                        + Text(row.folder.map { "  \($0)" } ?? "").font(Design.Text.commandSmall)
                        .foregroundColor(Design.Label.secondary))
                        .lineLimit(1).truncationMode(.middle)
                    if let fact = row.fact {
                        Text(fact).font(Design.Text.rowFact).foregroundStyle(Design.Label.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
        } else {
            Text(row.text)
                .font(row.mono ? Design.Text.command : Design.Text.cardNote)
                .foregroundStyle(Design.Label.primary)
                .lineLimit(1).truncationMode(row.mono ? .head : .tail)
        }
    }
}

/// A card's primary button (blue when it is the card's one action, grey
/// when it only shows something) and its ⋯ menu.
struct DoctorButtons: View {
    let card: DoctorCard
    let key: String
    let enabled: Bool
    let onButton: DoctorButtonHandler

    var body: some View {
        HStack(spacing: Design.Space.three) {
            if let primary = card.primary {
                if card.primaryProminent {
                    Button(primary.title) { onButton(primary, card, key) }
                        .buttonStyle(.borderedProminent).font(Design.Text.button).help(primary.help)
                } else {
                    Button(primary.title) { onButton(primary, card, key) }.font(Design.Text.button).help(primary.help)
                }
            }
            if !card.menu.isEmpty {
                DoctorMenuButton(entries: card.menu, help: "More actions for \(card.subject)") { button in
                    onButton(button, card, key)
                }
            }
        }
        .disabled(!enabled)
    }
}

/// The ⋯ beside a card or a row: everything that is not one of the two
/// verbs the reader came for.
struct DoctorMenuButton: View {
    let entries: [DoctorMenuEntry]
    let help: String
    let onButton: (DoctorButton) -> Void

    var body: some View {
        Menu {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .separator:
                    Divider()
                case let .button(button):
                    Button(button.title) { onButton(button) }.help(button.help)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
    }
}

/// "Waiting for Touch ID…" or "Working…", after an amber spinner.
struct DoctorWorkingLine: View {
    let presence: Bool

    var body: some View {
        HStack(spacing: Design.Space.four) {
            ProgressView().controlSize(.mini).tint(Color(StatusMark.amber))
            Text(presence ? "Waiting for Touch ID…" : "Working…")
                .font(Design.Text.cardNote).foregroundStyle(Design.Label.secondary)
        }
    }
}

/// How a fix ended, in the row that asked for it: a green check and what
/// now works, or a red cross, what the app can say about it, what jit
/// said in its own box, and Try Again.
struct DoctorEndedLine<Trailing: View>: View {
    let done: Bool
    let title: String
    let line: String?
    let said: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.five) {
            Image(systemName: done ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: Design.Size.glyph))
                .foregroundStyle(Color(done ? StatusMark.green : StatusMark.red))
            VStack(alignment: .leading, spacing: Design.Space.one) {
                Text(title).font(Design.Text.rowName).foregroundStyle(Design.Label.primary)
                if let line {
                    Text(line).font(Design.Text.rowFact).foregroundStyle(Design.Label.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let said, !said.isEmpty {
                    DoctorSaidBox(text: said)
                }
            }
            Spacer(minLength: Design.Space.four)
            trailing()
        }
    }
}

extension DoctorEndedLine where Trailing == EmptyView {
    init(done: Bool, title: String, line: String?, said: String?) {
        self.init(done: done, title: title, line: line, said: said) { EmptyView() }
    }
}

/// jit's own words, in the app's type on the app's material. The only
/// other place they existed was a black terminal pane over the window.
struct DoctorSaidBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Design.Text.commandSmall)
            .foregroundStyle(Design.Label.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Design.Space.four)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous).fill(Design.Surface.verbatim))
            .padding(.top, Design.Space.one)
    }
}

extension View {
    /// Right-click on a view that names a file: Show in Finder (selects it,
    /// never opens it; disabled when it is gone) and Copy Path.
    @ViewBuilder
    func doctorFileMenu(_ path: String?) -> some View {
        if let path {
            contextMenu {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
                .disabled(!FileManager.default.fileExists(atPath: path))
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(path, forType: .string)
                }
            }
        } else {
            self
        }
    }
}
