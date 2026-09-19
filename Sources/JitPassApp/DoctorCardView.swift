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
    case failed(title: String, line: String?, retry: DoctorButton)

    var enabled: Bool {
        self == .idle(enabled: true)
    }
}

typealias DoctorButtonHandler = (DoctorButton, DoctorCard, String) -> Void

/// One card: the title says what stops working, the reason why, a mono
/// line names the file and profile; one primary button, the ⋯ menu for
/// the rest. Right-click on a card or row naming a file offers Show in
/// Finder and Copy Path, never a click: a mis-click must not open an
/// editor on a file that may hold plaintext.
struct DoctorCardView: View {
    let card: DoctorCard
    let state: DoctorCardState
    let rowState: (String) -> DoctorCardState
    let onButton: DoctorButtonHandler
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch state {
            case let .done(title, line):
                DoctorEndedLine(done: true, title: title, line: line)
            case let .failed(title, line, retry):
                DoctorEndedLine(done: false, title: title, line: line) {
                    Button("Try Again") { onButton(retry, card, card.id) }
                }
            default:
                top
                rows
                disclosure
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isDone ? 1 : 0.5)
        )
        .contentShape(Rectangle())
        .doctorFileMenu(card.file)
    }

    private var isDone: Bool {
        if case .done = state {
            return true
        }
        return false
    }

    private var borderColor: Color {
        isDone ? Color(StatusMark.green).opacity(0.45) : Color.primary.opacity(0.08)
    }

    private var top: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.title).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                if card.changedSinceIgnored {
                    HStack(spacing: 6) {
                        Circle().fill(Color(StatusMark.amber)).frame(width: 6, height: 6)
                        Text("Was ignored; it changed since").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                if case let .working(presence) = state {
                    DoctorWorkingLine(presence: presence)
                } else if let reason = card.reason {
                    Text(reason).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let detail = card.detail {
                    Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
            DoctorButtons(card: card, key: card.id, enabled: state.enabled, onButton: onButton)
        }
    }

    /// A multi-row card's rows: the line in mono, its own buttons.
    private var rows: some View {
        ForEach(card.rows) { row in
            DoctorRowView(row: row, card: card, state: rowState(row.id), onButton: onButton)
        }
    }

    /// "Show the 7 profiles": the names in two columns, each with what is
    /// true of it.
    @ViewBuilder
    private var disclosure: some View {
        if !card.listed.isEmpty {
            Button(card.disclosure(open: open)) { open.toggle() }
                .buttonStyle(.link).font(.system(size: 12))
            if open {
                let columns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
                    ForEach(card.listed) { row in
                        (Text(row.name) + Text(" · \(row.note)").foregroundColor(.secondary))
                            .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    }
                }
                .padding(.leading, 2)
            }
        }
    }
}

/// A row of a multi-row card, with its own busy and ended states.
struct DoctorRowView: View {
    let row: DoctorCardRow
    let card: DoctorCard
    let state: DoctorCardState
    let onButton: DoctorButtonHandler

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            switch state {
            case let .done(title, line):
                DoctorEndedLine(done: true, title: title, line: line, compact: true)
            case let .failed(title, line, retry):
                DoctorEndedLine(done: false, title: title, line: line, compact: true) {
                    Button("Try Again") { onButton(retry, card, row.id) }
                }
            case let .working(presence):
                rowText
                Spacer(minLength: 8)
                DoctorWorkingLine(presence: presence)
            case let .idle(enabled):
                rowText
                Spacer(minLength: 8)
                ForEach(row.buttons) { button in
                    Button(button.title) { onButton(button, card, row.id) }.help(button.help).disabled(!enabled)
                }
            }
        }
        .contentShape(Rectangle())
        .doctorFileMenu(row.file)
    }

    private var rowText: some View {
        Text(row.text)
            .font(row.mono ? .system(size: 12, design: .monospaced) : .system(size: 12))
            .lineLimit(1).truncationMode(row.mono ? .head : .tail)
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
        HStack(spacing: 8) {
            if let primary = card.primary {
                if card.primaryProminent {
                    Button(primary.title) { onButton(primary, card, key) }
                        .buttonStyle(.borderedProminent).help(primary.help)
                } else {
                    Button(primary.title) { onButton(primary, card, key) }.help(primary.help)
                }
            }
            if !card.menu.isEmpty {
                Menu {
                    ForEach(Array(card.menu.enumerated()), id: \.offset) { _, entry in
                        switch entry {
                        case .separator:
                            Divider()
                        case let .button(button):
                            Button(button.title) { onButton(button, card, key) }.help(button.help)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions for \(card.subject)")
            }
        }
        .disabled(!enabled)
    }
}

/// "Waiting for Touch ID…" or "Working…", after an amber spinner.
struct DoctorWorkingLine: View {
    let presence: Bool

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini).tint(Color(StatusMark.amber))
            Text(presence ? "Waiting for Touch ID…" : "Working…").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

/// How a fix ended: a green check and what now works, or a red cross,
/// what jit said, and Try Again.
struct DoctorEndedLine<Trailing: View>: View {
    let done: Bool
    let title: String
    let line: String?
    var compact = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: compact ? 13 : 17))
                .foregroundStyle(Color(done ? StatusMark.green : StatusMark.red))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: compact ? 12 : 13, weight: .semibold))
                if let line {
                    Text(line).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension DoctorEndedLine where Trailing == EmptyView {
    init(done: Bool, title: String, line: String?, compact: Bool = false) {
        self.init(done: done, title: title, line: line, compact: compact) { EmptyView() }
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
