// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The vault as a whole, one row per command: what there is, and the
/// button that acts on it. Orphans are listed with their origins because
/// the CLI's own warning is that an orphan may be another project's.
struct MaintenanceSheet: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vault Maintenance").font(.headline)
                Text("Each button says what it runs before it runs. Touch ID follows each.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            orphansRow
            Divider()
            row("Migrate backups", value: backupsValue) {
                Button("Prune…", action: actions.pruneBackups).disabled(backupsCount == 0)
            }
            .help("jit vault prune: every backup but the newest per file")
            row("Export", value: "a passphrase-encrypted copy of every secret") {
                Button("Export…", action: actions.exportVault)
            }
            row("Import", value: "restore from an export; same paths are overwritten") {
                Button("Import…", action: actions.importVault)
            }
            row("Rekey", value: "new master key, every secret re-wrapped") {
                Button("Rekey…", action: actions.rekey)
            }
            row("Duplicates", value: "the same value stored twice; one Touch ID per class") {
                Button("Open in Terminal", action: actions.duplicatesInTerminal)
            }
            if let message = model.vaultMessage {
                Text(message).font(.subheadline).foregroundStyle(Color(StatusMark.red))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notice = model.vaultNotice {
                Text(notice).font(.subheadline).foregroundStyle(Color(StatusMark.green))
            }
            HStack {
                if let busy = model.vaultBusy {
                    Text("Touch ID for \(busy)…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close", action: actions.closeSheet).keyboardShortcut(.cancelAction)
            }
        }
        .disabled(model.vaultBusy != nil)
        .padding(18)
        .frame(width: 520)
        .onAppear(perform: actions.loadOrphans)
    }

    private var backupsCount: Int {
        model.vaultListing?.backups.count ?? 0
    }

    private var backupsValue: String {
        backupsCount == 0 ? "none" : "\(backupsCount), kept for jit migrate undo"
    }

    @ViewBuilder private var orphansRow: some View {
        if let orphans = model.vaultOrphans {
            row("Orphans", value: orphansValue(orphans)) {
                Button("Prune…", action: actions.pruneOrphans).disabled(orphans.isEmpty)
            }
            if !orphans.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(orphans.orphans) { orphan in
                        Text(orphan.path + (orphan.origin.isEmpty ? "" : " · from " + orphan.origin))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    ForEach(orphans.staleMounts) { mount in
                        Text("stale mount " + Format.home(mount.mountPath))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxHeight: 120)
                .help("A secret used only by a project you are not in and have not mounted looks orphaned too.")
            }
        } else {
            row("Orphans", value: "reading…") { EmptyView() }
        }
    }

    private func orphansValue(_ orphans: VaultOrphans) -> String {
        var parts: [String] = []
        if !orphans.orphans.isEmpty {
            parts.append("\(orphans.orphans.count) secret\(orphans.orphans.count == 1 ? "" : "s") no profile references")
        }
        if !orphans.staleMounts.isEmpty {
            parts.append("\(orphans.staleMounts.count) stale mount registration\(orphans.staleMounts.count == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "none" : parts.joined(separator: " · ")
    }

    private func row(_ title: String, value: String, @ViewBuilder button: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.semibold)
                Text(value).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            button().controlSize(.small)
        }
    }
}
