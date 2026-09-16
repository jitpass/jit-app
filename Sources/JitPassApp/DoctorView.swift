// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Doctor: the same findings list `jit doctor` prints, problems first, each
/// with the CLI's advice and a Run link for the one command it names. The
/// app shows and never fixes; every fix runs in the terminal.
struct DoctorView: View {
    @ObservedObject var model: MenuModel
    let actions: DoctorActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            if let report = model.doctor {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        section("Problems", report.problems, glyph: "✗", color: Color(StatusMark.red))
                        section("Warnings", report.warnings, glyph: "○", color: Color(StatusMark.amber))
                    }
                    .padding(.bottom, 12)
                    .padding(.trailing, 14)
                }
            } else {
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
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
        }
    }

    private func dot(_ report: DoctorReport) -> Color {
        if !report.problems.isEmpty {
            return Color(StatusMark.red)
        }
        return report.warnings.isEmpty ? Color(StatusMark.green) : Color(StatusMark.amber)
    }

    private func section(_ title: String, _ items: [DoctorItem], glyph: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("\(items.count)").foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text("none").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text(glyph).foregroundStyle(color).frame(width: 12)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.summary).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        if let command = item.command {
                            HStack(spacing: 8) {
                                Text("→ " + command).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Button("Run") { actions.run(command) }.buttonStyle(.link).font(.system(size: 11))
                            }
                        }
                    }
                }
            }
        }
    }
}

struct DoctorActions {
    var recheck: () -> Void = {}
    var openInTerminal: () -> Void = {}
    var run: (String) -> Void = { _ in }
}
