// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The scan report, compact: the score, then "jit will protect these" and
/// "only you can fix these", each finding on one line. The terminal keeps
/// the full evidence, and every fix stays a terminal command, because
/// `jit migrate` is the guided write path with its own confirmations.
struct ScanReportView: View {
    @ObservedObject var model: MenuModel
    let actions: ScanActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 8)
            if let error = model.scanError {
                Text(error).foregroundStyle(.secondary).padding(.vertical, 20)
            } else if let report = model.scan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        section("jit will protect these", report.migratable, fixable: true)
                        section("Only you can fix these", report.manual, fixable: false)
                    }
                    .padding(.bottom, 12)
                    .padding(.trailing, 14)
                }
            } else {
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if model.scanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning your Mac…").font(.headline)
                } else if let s = model.scan?.summary {
                    Circle().fill(Severity.color(s.riskLevel)).frame(width: 12, height: 12)
                    Text("Exposure \(s.exposureScore) / 100 · \(s.riskLevel)").font(.headline)
                } else {
                    Text("Exposure").font(.headline)
                }
                Spacer(minLength: 16)
                Button("Rescan", action: actions.rescan).disabled(model.scanning)
                Button("Open in Terminal", action: actions.openInTerminal)
            }
            if !model.scanning, let s = model.scan?.summary {
                Text(Format.scanSummary(s)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func section(_ title: String, _ findings: [ScanFinding], fixable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text("\(findings.count)").foregroundStyle(.secondary)
            }
            if findings.isEmpty {
                Text("nothing").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(findings) { f in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Severity.color(f.severity)).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Format.home(f.filePath)).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Text(Format.findingType(f.findingType) + " · " + f.evidence)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if fixable, let fix = f.fixCommand {
                        Button("Fix") { actions.fix(fix) }
                            .buttonStyle(.link).font(.system(size: 12))
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
    }
}

struct ScanActions {
    var rescan: () -> Void = {}
    var openInTerminal: () -> Void = {}
    var fix: (String) -> Void = { _ in }
}
