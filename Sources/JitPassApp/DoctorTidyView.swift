// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Tidy up: one card of one-line rows ("No recovery file yet · the vault
/// only opens on this Mac"), a grey button each.
struct DoctorTidyList: View {
    let cards: [DoctorCard]
    let state: (String) -> DoctorCardState
    let onButton: DoctorButtonHandler

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                if index > 0 {
                    Divider()
                }
                row(card, state(card.id))
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .doctorFileMenu(card.file)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    @ViewBuilder
    private func row(_ card: DoctorCard, _ state: DoctorCardState) -> some View {
        switch state {
        case let .done(title, line):
            DoctorEndedLine(done: true, title: title, line: line, compact: true)
        case let .failed(title, line, retry):
            DoctorEndedLine(done: false, title: title, line: line, compact: true) {
                Button("Try Again") { onButton(retry, card, card.id) }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    (Text(card.title) + Text(card.reason.map { " · \($0)" } ?? "").font(.system(size: 12)).foregroundColor(.secondary))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if case let .working(presence) = state {
                        DoctorWorkingLine(presence: presence)
                    } else {
                        DoctorButtons(card: card, key: card.id, enabled: state.enabled, onButton: onButton)
                    }
                }
                if card.changedSinceIgnored {
                    Text("Was ignored; it changed since").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(card.rows) { row in
                    Text(row.text).font(.system(size: 11, design: row.mono ? .monospaced : .default)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head).padding(.leading, 8)
                        .doctorFileMenu(row.file)
                }
            }
        }
    }
}

/// Review…: the profiles no known tool uses, each with its own Remove
/// Profile and the dialog it always had, worded from `jit profile rm
/// --dry-run`. Read live from the report, so a removed profile leaves the
/// list when the recheck lands.
struct DoctorReviewSheet: View {
    @ObservedObject var model: MenuModel
    let actions: DoctorActions
    let done: () -> Void

    private var items: [DoctorItem] {
        (model.doctor?.warnings ?? []).filter { $0.kind == "no_known_tool" }
    }

    private var idle: Bool {
        model.doctorBusy == nil && !model.doctorRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profiles no tool uses").font(.system(size: 15, weight: .bold))
            Text("Nothing jit can see uses these. It can't see scripts or aliases, so remove one only if you no longer use it.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if items.isEmpty {
                Text("None left.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Text(DoctorAdvice.rowText(item)).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if model.doctorBusy == item.id {
                        DoctorWorkingLine(presence: true)
                    } else {
                        ForEach(DoctorAdvice.actions(for: item), id: \.command) { action in
                            Button(action.buttonTitle) { actions.perform(action, item.id) }
                                .help(action.command).disabled(!idle)
                        }
                    }
                }
                .contentShape(Rectangle())
                .doctorFileMenu(DoctorAdvice.filePath(item))
            }
            HStack {
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

/// The ignored findings folded into one line, "3 ignored · Show"; open,
/// a row each (name · section · since) with Show Again.
struct DoctorIgnoredFold: View {
    let rows: [DoctorIgnoredRow]
    let state: (String) -> DoctorCardState
    let onShowAgain: (DoctorButton, String) -> Void
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("\(rows.count) ignored").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("·").font(.system(size: 12)).foregroundStyle(.secondary)
                Button(open ? "Hide" : "Show") { open.toggle() }.buttonStyle(.link).font(.system(size: 12))
            }
            if open {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.text).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        switch state(row.id) {
                        case let .working(presence):
                            DoctorWorkingLine(presence: presence)
                        case let .idle(enabled):
                            if let again = row.showAgain {
                                Button(again.title) { onShowAgain(again, row.id) }.help(again.help).disabled(!enabled)
                            }
                        default:
                            EmptyView()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
