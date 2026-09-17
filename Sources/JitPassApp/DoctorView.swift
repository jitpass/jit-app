// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Doctor: the same findings `jit doctor` reports, problems first, grouped
/// by kind under a title and a one-line note, each row with buttons named
/// for what they do. The app shows and never fixes; every button runs its
/// command in the terminal, where jit's own confirmations apply. A
/// destructive one is red and confirmed by the app first.
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
                Button("Check Again", action: actions.recheck).disabled(model.doctorRunning)
                Button("Open in Terminal", action: actions.openInTerminal)
            }
            if let report = model.doctor {
                Text(Format.doctorSummary(report)).font(.subheadline).foregroundStyle(.secondary)
            }
            if let message = model.doctorMessage {
                Text(message).font(.subheadline).foregroundStyle(Color(StatusMark.red))
            }
        }
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
            if let action = group.groupAction {
                Button(action.title) { actions.perform(action) }.controlSize(.small)
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
                row(item)
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
                buttons(DoctorAdvice.orphanActions)
            }
            if expanded.contains(group.kind) {
                ForEach(group.items) { item in
                    Text(item.path ?? item.summary).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head).padding(.leading, 8)
                }
            }
        }
    }

    private func row(_ item: DoctorItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if DoctorAdvice.rowIsPath(item) {
                Text(DoctorAdvice.rowText(item)).font(.system(size: 12, design: .monospaced))
                    .lineLimit(1).truncationMode(.head)
            } else {
                Text(DoctorAdvice.rowText(item)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            buttons(DoctorAdvice.actions(for: item))
            if item.isGlobalProfileProblem, let profile = item.profile {
                Button("Delete Profile") { actions.deleteProfile(profile) }
                    .buttonStyle(.link).font(.system(size: 11)).foregroundStyle(Color(StatusMark.red))
            }
        }
    }

    private func buttons(_ list: [DoctorAction]) -> some View {
        HStack(spacing: 10) {
            ForEach(list, id: \.command) { action in
                Button(action.title) { actions.perform(action) }
                    .buttonStyle(.link).font(.system(size: 11))
                    .foregroundStyle(action.destructive ? Color(StatusMark.red) : Color.accentColor)
                    .help(action.command)
            }
        }
    }
}

struct DoctorActions {
    var recheck: () -> Void = {}
    var openInTerminal: () -> Void = {}
    var perform: (DoctorAction) -> Void = { _ in }
    var deleteProfile: (String) -> Void = { _ in }
}
