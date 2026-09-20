// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import os
import SwiftUI

private let vaultViewLog = Logger(subsystem: "com.jitpass.app", category: "vault")

/// The vault as two panes: profiles (the first path segment, the unit
/// `jit vault list` groups by and `jit vault rm <group>` deletes by) on the
/// left, the selected profile's secrets as a table on the right, and one
/// bar under the table for the selected secret's actions. A value appears
/// in that bar only, after its own Touch ID, for
/// `StatusItemController.revealSeconds`.
struct VaultView: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions

    @State private var filter = ""
    @State private var selectedGroup: String?
    @State private var selectedPath: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 230)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .sheet(item: $model.vaultSheet) { sheet in
            switch sheet {
            case let .add(group, replacing):
                AddSecretSheet(model: model, actions: actions, group: group ?? selectedGroup ?? "", replacing: replacing)
            case let .link(group, replacing):
                LinkSecretSheet(model: model, actions: actions, group: group ?? selectedGroup ?? "", replacing: replacing)
            case let .history(path):
                HistorySheet(model: model, actions: actions, path: path)
            case .maintenance:
                MaintenanceSheet(model: model, actions: actions)
            case .orphans:
                VaultOrphansSheet(model: model, actions: actions)
            case .duplicates:
                DuplicatesSheet(model: model, actions: actions)
            }
        }
        .onAppear(perform: actions.reload)
        .onChange(of: model.vaultListing) { _, _ in keepSelectionValid() }
        .onChange(of: filter) { _, _ in keepSelectionValid() }
        .onChange(of: selectedPath) { _, _ in actions.hideReveal() }
        .onChange(of: model.vaultReveal) { _, new in
            guard let new else {
                return
            }
            let selected = selectedPath ?? "nil"
            vaultViewLog.notice("view sees reveal for \(new.path, privacy: .public); selected=\(selected, privacy: .public)")
        }
    }

    private var groups: [VaultGroup] {
        model.vaultListing?.groups(matching: filter) ?? []
    }

    private var selected: VaultGroup? {
        groups.first { $0.name == selectedGroup }
    }

    private var selectedSecret: VaultSecret? {
        selected?.secrets.first { $0.path == selectedPath }
    }

    /// The first profile is selected when nothing is, and a selection that
    /// the filter or a delete removed falls back to the first.
    private func keepSelectionValid() {
        if selected == nil {
            selectedGroup = groups.first?.name
        }
        if selectedSecret == nil {
            selectedPath = nil
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.vaultSummary).font(.headline)
                .help(
                    "Linked: stored as a 1Password reference, resolved through the 1Password CLI at each use. Type \"linked\" to find them."
                )
                .padding(.horizontal, 14).padding(.top, 16)
            TextField("filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 6)
            if model.vaultListing == nil {
                Text("Reading…").foregroundStyle(.secondary).padding(14)
                Spacer()
            } else if groups.isEmpty {
                Text(filter.isEmpty ? "The vault is empty." : "Nothing matches.")
                    .foregroundStyle(.secondary).padding(14)
                Spacer()
            } else {
                List(groups, selection: $selectedGroup) { group in
                    HStack(spacing: 8) {
                        Circle().fill(dotColor(group)).frame(width: 7, height: 7)
                        Text(group.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if group.hasLink {
                            Image(systemName: "link").font(.system(size: 10)).foregroundStyle(.secondary)
                                .help("Holds a 1Password link")
                        }
                        Text("\(group.secrets.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .tag(group.name)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            Divider()
            HStack {
                Text(backupsLine).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Maintenance…") { actions.openSheet(.maintenance) }.controlSize(.small)
                    .disabled(model.vaultBusy != nil)
                    .help("Orphans, backups, export, import, rekey, duplicates")
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private var backupsLine: String {
        let count = model.vaultListing?.backups.count ?? 0
        return count == 0 ? "no migrate backups" : "\(count) migrate backup\(count == 1 ? "" : "s")"
    }

    /// Green: migrated from a file that still exists. Amber: the origin file
    /// is gone, the shape `jit vault orphans` and `duplicates --prune` care
    /// about. Grey: no origin recorded (set by hand, migrated before jit
    /// kept one, or assembled from several files), so there is no file to
    /// check. A blank read as missing, so every row gets a dot.
    private func dotColor(_ group: VaultGroup) -> Color {
        guard let origin = group.origin else {
            return Color.secondary.opacity(0.5)
        }
        return VaultOrigin.exists(origin) ? Color(StatusMark.green) : Color(StatusMark.amber)
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if let group = selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.name).font(.title3).fontWeight(.semibold)
                        Text(profileLine(group)).font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("Add…") { actions.openSheet(.add(group: group.name, replacing: nil)) }
                    Button("Link 1Password…") { actions.openSheet(.link(group: group.name, replacing: nil)) }
                    Button("Delete Profile…") { actions.delete(group.secrets.map(\.path)) }
                }
                .disabled(model.vaultBusy != nil)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

                Table(group.secrets, selection: $selectedPath) {
                    TableColumn("Name") { secret in
                        HStack(spacing: 6) {
                            Image(systemName: secret.isLinked ? "link" : "key.fill")
                                .foregroundStyle(.secondary).font(.system(size: 10))
                            Text(secret.name)
                        }
                    }
                    TableColumn("Class") { secret in
                        Text(secret.isLinked ? "1Password" : (secret.secretClass ?? "")).foregroundStyle(.secondary)
                    }
                    .width(min: 70, ideal: 90)
                    TableColumn("Updated") { secret in
                        Text(secret.updated.map { Format.ago($0) } ?? "").foregroundStyle(.secondary)
                    }
                    .width(min: 90, ideal: 120)
                }
                .contextMenu(forSelectionType: String.self) { paths in
                    if let path = paths.first, paths.count == 1, let secret = group.secrets.first(where: { $0.path == path }) {
                        rowMenu(secret)
                    }
                }
                .scrollContentBackground(.hidden)

                Divider()
                selectionBar(group)
            }
        } else {
            VStack {
                Spacer()
                Text(model.vaultListing == nil ? "Reading the vault…" : "Select a profile").foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// "4 secrets · from ~/.clisso.yaml", with "(file gone)" when the
    /// origin no longer exists; "set by hand" when nothing was recorded.
    private func profileLine(_ group: VaultGroup) -> String {
        var parts = ["\(group.secrets.count) secret\(group.secrets.count == 1 ? "" : "s")"]
        if let origin = group.origin {
            parts.append("from " + origin + (VaultOrigin.exists(origin) ? "" : " (file gone)"))
        } else if group.secrets.allSatisfy({ $0.origin == nil }) {
            parts.append("set by hand")
        } else {
            parts.append("from several files")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Selection bar

    /// One place for the selected secret: its actions, or the revealed
    /// value with its countdown, or the failure line. The table above never
    /// reflows for any of them.
    private func selectionBar(_: VaultGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.vaultMessage {
                Text(message).font(.subheadline).foregroundStyle(Color(StatusMark.red))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notice = model.vaultNotice {
                Text(notice).font(.subheadline).foregroundStyle(Color(StatusMark.green))
            }
            if let secret = selectedSecret {
                if let reveal = model.vaultReveal, reveal.path == secret.path {
                    revealRow(reveal)
                } else {
                    HStack(spacing: 8) {
                        Text(secret.name).fontWeight(.semibold)
                        if !secret.usedBy.isEmpty {
                            Text("used by " + secret.usedBy.joined(separator: ", "))
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                .help("The profiles that reference this secret: what a wrap injects or a mount serves.")
                        }
                        if let expires = secret.expires {
                            Text(Format.expiry(expires))
                                .foregroundStyle(expires > Date() ? Color.secondary : Color(StatusMark.amber))
                        }
                        if model.vaultBusy == secret.path {
                            Text("Touch ID…").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reveal") { actions.reveal(secret.path) }
                        Button("Copy") { actions.copy(secret.path) }
                        Button("Replace…") { actions.openSheet(replaceSheet(secret)) }
                        Button("History…") { actions.openSheet(.history(path: secret.path)) }
                        Button("Delete…") { actions.delete([secret.path]) }
                    }
                    .disabled(model.vaultBusy != nil)
                }
            } else if let busy = model.vaultBusy {
                Text("Touch ID for \(busy)…").foregroundStyle(.secondary)
            } else {
                Text("Select a secret. Every read or change is its own Touch ID; nothing here rides the service session.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The value, its countdown, and Hide. Never selectable: the reveal is
    /// for reading, the clipboard path is Copy.
    private func revealRow(_ reveal: VaultReveal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(reveal.text)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(6)
                .textSelection(.disabled)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(StatusMark.amber).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text("\(reveal.secondsLeft)s").foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button("Hide", action: actions.hideReveal)
        }
    }

    @ViewBuilder private func rowMenu(_ secret: VaultSecret) -> some View {
        Button("Reveal for \(StatusItemController.revealSeconds)s") { actions.reveal(secret.path) }
        Button("Copy to Clipboard") { actions.copy(secret.path) }
        Divider()
        Button("Replace…") { actions.openSheet(replaceSheet(secret)) }
        Button("History…") { actions.openSheet(.history(path: secret.path)) }
        Divider()
        Button("Delete…") { actions.delete([secret.path]) }
    }

    /// A linked secret is replaced with another link; a value with a value.
    private func replaceSheet(_ secret: VaultSecret) -> VaultSheet {
        secret.isLinked ? .link(group: secret.group, replacing: secret.path) : .add(group: secret.group, replacing: secret.path)
    }
}

/// Whether a recorded origin file ("~/.clisso.yaml") is still on disk.
enum VaultOrigin {
    static func exists(_ origin: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = origin.hasPrefix("~/") ? home + origin.dropFirst(1) : origin
        return FileManager.default.fileExists(atPath: path)
    }
}

struct VaultActions {
    var reload: () -> Void = {}
    var openSheet: (VaultSheet) -> Void = { _ in }
    var closeSheet: () -> Void = {}
    var reveal: (String) -> Void = { _ in }
    var hideReveal: () -> Void = {}
    var copy: (String) -> Void = { _ in }
    /// path, value, replacing an existing secret
    var set: (String, String, Bool) -> Void = { _, _, _ in }
    /// path, op:// reference, verify through op, replacing
    var link: (String, String, Bool, Bool) -> Void = { _, _, _, _ in }
    var loadHistory: (String) -> Void = { _ in }
    /// path, stamp
    var restore: (String, Int64) -> Void = { _, _ in }
    var delete: ([String]) -> Void = { _ in }
    var openInTerminal: () -> Void = {}
    var loadOrphans: () -> Void = {}
    /// `jit vault orphans --prune`: the stale mount registrations, and
    /// every orphaned secret still listed with them.
    var clearStaleMounts: () -> Void = {}
    /// Select the files these secrets were migrated from in Finder.
    var revealOrigins: ([String]) -> Void = { _ in }
    var pruneBackups: () -> Void = {}
    var exportVault: () -> Void = {}
    var importVault: () -> Void = {}
    var rekey: () -> Void = {}
    var compareDuplicates: () -> Void = {}
    var pruneDuplicates: () -> Void = {}
}
