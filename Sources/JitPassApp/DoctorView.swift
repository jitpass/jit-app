// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Doctor: the same findings `jit doctor` reports, problems first, grouped
/// by kind under a title and a one-line note, each row with buttons named
/// for what they do. A button runs the jit command doctor named: in the
/// app when it can run unattended (every y/N pre-answered, any value typed
/// into a hidden field), in the terminal otherwise, where jit's own
/// confirmations apply. A destructive one is red and confirmed by the app
/// first. One action at a time: while one runs, or a check, every button
/// is disabled and the running row says so until the recheck lands.
struct DoctorView: View {
    @ObservedObject var model: MenuModel
    let actions: DoctorActions
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            if let report = model.doctor {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("Problems", report.problemGroups, glyph: "✗", color: Color(StatusMark.red))
                        section("Warnings", report.warningGroups, glyph: "○", color: Color(StatusMark.amber))
                    }
                    .padding(.bottom, 12)
                    .padding(.trailing, 14)
                }
            } else {
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 560, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if model.doctorRunning {
                    ProgressView().controlSize(.small)
                    Text("Checking…").font(.headline)
                } else if let report = model.doctor {
                    Circle().fill(dot(report)).frame(width: 12, height: 12)
                    Text(report.verdict.capitalized).font(.headline)
                } else {
                    Text("Doctor").font(.headline)
                }
                Spacer(minLength: 16)
                Button("Check Again", action: actions.recheck).disabled(!idle)
                Button("Open in Terminal", action: actions.openInTerminal)
            }
            if let report = model.doctor {
                Text(Format.doctorSummary(report)).font(.subheadline).foregroundStyle(.secondary)
            }
            if let message = model.doctorMessage {
                Text(message).font(.subheadline).foregroundStyle(Color(StatusMark.red))
            }
            if model.doctorFailed, !model.doctorRunning {
                Text(model.doctor == nil
                    ? "jit doctor gave no report."
                    : "jit doctor gave no report; the findings below are from an earlier check.")
                    .font(.subheadline).foregroundStyle(Color(StatusMark.red))
            }
        }
    }

    /// Nothing running: no action, no check.
    private var idle: Bool {
        model.doctorBusy == nil && !model.doctorRunning
    }

    private func dot(_ report: DoctorReport) -> Color {
        if !report.problems.isEmpty {
            return Color(StatusMark.red)
        }
        return report.warnings.isEmpty ? Color(StatusMark.green) : Color(StatusMark.amber)
    }

    private func section(_ title: String, _ groups: [DoctorGroup], glyph: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("\(groups.reduce(0) { $0 + (DoctorAdvice.listedKinds.contains($1.kind) ? 1 : $1.items.count) })")
                    .foregroundStyle(.secondary)
            }
            if groups.isEmpty {
                Text("none").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                HStack(alignment: .top, spacing: 8) {
                    Text(glyph).foregroundStyle(color).frame(width: 12)
                    if DoctorAdvice.listedKinds.contains(group.kind) {
                        listedGroup(group)
                    } else {
                        plainGroup(group)
                    }
                }
            }
        }
    }

    private func groupHeader(_ group: DoctorGroup, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(group.title).font(.system(size: 12, weight: .semibold))
            if let count {
                Text("\(count)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            if !group.groupActions.isEmpty {
                if model.doctorBusy == groupRow(group) {
                    working
                } else {
                    ForEach(group.groupActions, id: \.command) { action in
                        Button(action.title) { actions.perform(action, groupRow(group)) }
                            .controlSize(.small).disabled(!idle).help(action.command)
                    }
                }
            }
        }
    }

    /// A group with one row per finding.
    private func plainGroup(_ group: DoctorGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            groupHeader(group, count: group.items.count > 1 ? group.items.count : nil)
            if let note = group.note {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(group.items) { item in
                row(item, in: group)
            }
        }
    }

    /// A group shown as a count with its rows behind a disclosure: the
    /// orphaned secrets, forty-five paths a reader wants folded.
    private func listedGroup(_ group: DoctorGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            groupHeader(group, count: group.items.count)
            if let note = group.note {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button(expanded.contains(group.kind) ? "Hide" : "Show \(group.items.count)") {
                    if !expanded.insert(group.kind).inserted {
                        expanded.remove(group.kind)
                    }
                }
                .buttonStyle(.link).font(.system(size: 11))
                buttons(DoctorAdvice.orphanActions, row: groupRow(group))
            }
            if expanded.contains(group.kind) {
                ForEach(group.items) { item in
                    Text(item.path ?? item.summary).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head).padding(.leading, 8)
                }
            }
        }
    }

    private func row(_ item: DoctorItem, in group: DoctorGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if DoctorAdvice.rowIsPath(item) {
                    Text(group.rowText(item)).font(.system(size: 12, design: .monospaced))
                        .lineLimit(1).truncationMode(.head)
                } else {
                    Text(group.rowText(item)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                buttons(DoctorAdvice.actions(for: item), row: item.id)
            }
            if let note = DoctorAdvice.rowNote(item) {
                Text(note).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A row's buttons, or in their place, while its action runs and until
    /// the recheck after it lands, a spinner saying so.
    @ViewBuilder
    private func buttons(_ list: [DoctorAction], row: String) -> some View {
        if model.doctorBusy == row {
            working
        } else {
            HStack(spacing: 10) {
                ForEach(list, id: \.command) { action in
                    Button(action.title) { actions.perform(action, row) }
                        .buttonStyle(.link).font(.system(size: 11))
                        .foregroundStyle(action.destructive ? Color(StatusMark.red) : Color.accentColor)
                        .help(action.command)
                }
            }
            .disabled(!idle)
            // A link-styled button keeps its colour when disabled.
            .opacity(idle ? 1 : 0.4)
        }
    }

    private var working: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("Working…").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// The busy key for a group's own buttons, apart from any row's id.
    private func groupRow(_ group: DoctorGroup) -> String {
        "group:\(group.kind)"
    }
}

struct DoctorActions {
    var recheck: () -> Void = {}
    var openInTerminal: () -> Void = {}
    /// The action, and the row it belongs to (a finding's id or a group's
    /// key), which shows as busy while it runs.
    var perform: (DoctorAction, String) -> Void = { _, _ in }
}
