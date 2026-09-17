// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// What `jit vault duplicates` found: one block per look-alike pair with
/// the verdict and, when jit is sure, the command that retires the stale
/// copy. Prune runs only on the copies the CLI itself would delete.
struct DuplicatesSheet: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicates").font(.headline)
                Text(summary).font(.subheadline).foregroundStyle(.secondary)
            }
            if let report = model.vaultDuplicates {
                if report.findings.isEmpty {
                    Text("No file is stored twice.").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.findings) { finding in
                                block(finding)
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
                if !report.sharedCredentials.isEmpty {
                    Text(sharedLine(report)).font(.system(size: 11)).foregroundStyle(.secondary)
                        .help(
                            "The same value under the same names from different files: not a copy, but every place a rotation must reach."
                        )
                }
            }
            if let message = model.vaultMessage {
                Text(message).font(.subheadline).foregroundStyle(Color(StatusMark.red)).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if let busy = model.vaultBusy {
                    Text("Touch ID for \(busy)…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", action: actions.closeSheet).keyboardShortcut(.cancelAction)
                if let report = model.vaultDuplicates, !report.prunablePaths.isEmpty {
                    Button("Prune \(report.prunablePaths.count)…", action: actions.pruneDuplicates)
                }
            }
            .disabled(model.vaultBusy != nil)
        }
        .padding(18)
        .frame(width: 560)
    }

    private var summary: String {
        guard let report = model.vaultDuplicates else {
            return "Reading…"
        }
        let n = report.findings.count
        return "\(report.secretsCompared) secrets compared · \(n) look-alike pair\(n == 1 ? "" : "s")"
    }

    private func sharedLine(_ report: VaultDuplicates) -> String {
        let n = report.sharedCredentials.count
        let names = report.sharedCredentials.map { $0.groups.joined(separator: " = ") }.joined(separator: "; ")
        return "\(n) shared credential\(n == 1 ? "" : "s"), not copies: " + names
    }

    private func block(_ finding: VaultDuplicate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(dot(finding)).frame(width: 7, height: 7)
                Text(finding.groups.joined(separator: "  ·  ")).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            }
            Text(finding.keys.joined(separator: ", ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Text(finding.verdict).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let command = finding.removeCommand, !finding.prunable {
                Text(command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Amber: a stale copy jit can prune. Grey: informational, the user's call.
    private func dot(_ finding: VaultDuplicate) -> Color {
        finding.prunable ? Color(StatusMark.amber) : Color.secondary.opacity(0.5)
    }
}
