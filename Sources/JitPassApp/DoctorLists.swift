// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

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

/// The Ignored tab: a row each (name · section · since), its dot the
/// colour of where it would be (red for a problem, as jit prints it), and
/// Show Again, which asks nothing.
struct DoctorIgnoredList: View {
    let rows: [DoctorIgnoredRow]
    let state: (String) -> DoctorCardState
    let onShowAgain: (DoctorButton, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Color.secondary.opacity(0.6)).frame(width: 8, height: 8)
                Text("Ignored").font(.system(size: 13, weight: .semibold))
                Text("\(rows.count)").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                    }
                    line(row).padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }

    private func line(_ row: DoctorIgnoredRow) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color(row.section)).frame(width: 6, height: 6)
            Text(row.text).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
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

    private func color(_ section: DoctorBoard.Tier) -> Color {
        switch section {
        case .broken: Color(StatusMark.red)
        case .recommended: Color(StatusMark.amber)
        case .tidy: Color.secondary.opacity(0.6)
        }
    }
}
