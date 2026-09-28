// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import os
import SwiftUI

private let vaultViewLog = Logger(subsystem: "com.jitpass.app", category: "vault")

/// The vault as two panes: profiles (the first path segment, the unit
/// `jit vault list` groups by and `jit vault rm <group>` deletes by) on the
/// left, and the selected profile on one scroll on the right: its secrets
/// as one card, its plain settings as another, each row carrying its own
/// verbs (docs/design/mockups/Vault-v2.html). A value appears only under
/// its own row, after its own Touch ID, for
/// `StatusItemController.revealSeconds`. The footer holds the vault's
/// counts, and in their place the latest word: a failure, a success, or
/// the Touch ID being waited on.
struct VaultView: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions

    @State private var filter = ""
    @State private var selectedGroup: String?

    var body: some View {
        VStack(spacing: 0) {
            cleanupBanner
            HStack(spacing: 0) {
                sidebar.frame(width: Design.Window.sidebar)
                Divider()
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
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
            case let .moveOut(paths):
                MoveOutSheet(model: model, actions: actions, paths: paths)
            case .checkSettings:
                CheckSettingsSheet(model: model, actions: actions)
            }
        }
        .onAppear(perform: actions.reload)
        .onChange(of: model.vaultListing) { _, _ in keepSelectionValid() }
        .onChange(of: filter) { _, _ in keepSelectionValid() }
        .onChange(of: selectedGroup) { _, _ in actions.hideReveal() }
        .onChange(of: model.vaultReveal) { _, new in
            guard let new else {
                return
            }
            vaultViewLog.notice("view sees reveal for \(new.path, privacy: .public)")
        }
    }

    private var groups: [VaultGroup] {
        model.vaultListing?.groups(matching: filter, settings: model.vaultSettings) ?? []
    }

    private var selected: VaultGroup? {
        groups.first { $0.name == selectedGroup }
    }

    /// The first profile is selected when nothing is, and a selection that
    /// the filter or a delete removed falls back to the first.
    private func keepSelectionValid() {
        if selected == nil {
            selectedGroup = groups.first?.name
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .help("Type \"linked\" to find the secrets stored as a 1Password reference.")
                .padding(.horizontal, Win.s5).padding(.top, Win.s5).padding(.bottom, Win.s3)
            if model.vaultListing == nil {
                Text("Reading…").foregroundStyle(.secondary).padding(Win.s5)
                Spacer()
            } else if groups.isEmpty {
                Text(filter.isEmpty ? "The vault is empty." : "Nothing matches.")
                    .foregroundStyle(.secondary).padding(Win.s5)
                Spacer()
            } else {
                List(groups, selection: $selectedGroup) { group in
                    HStack(spacing: Win.s4) {
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
        }
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
                profileHeader(group)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: Win.s5) {
                        if !group.secrets.isEmpty {
                            secretsCard(group)
                        }
                        let kept = settings(group)
                        if !kept.isEmpty {
                            settingsCard(kept, onlySettings: group.secrets.isEmpty)
                        }
                    }
                    .padding(.horizontal, Win.s6).padding(.vertical, Win.s5)
                }
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

    private func profileHeader(_ group: VaultGroup) -> some View {
        HStack(alignment: .center, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(group.name).font(Win.head)
                Text(profileLine(group)).font(Win.sub).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Win.s5)
            Button("Add…") { actions.openSheet(.add(group: group.name, replacing: nil)) }
                .buttonStyle(AppButton())
            profileMenu(group)
        }
        .disabled(model.vaultBusy != nil)
        .padding(.horizontal, Win.s6).padding(.vertical, Win.s5)
    }

    // MARK: - Footer

    /// The vault's counts; a failure, a success or a Touch ID being waited
    /// on takes their place until the next action.
    private var footer: some View {
        HStack(spacing: Win.s4) {
            if let message = model.vaultMessage {
                Text(message).foregroundStyle(Color(StatusMark.red)).lineLimit(2).help(message)
            } else if let busy = model.vaultBusy {
                Text("Touch ID for \(busy)…").foregroundStyle(.secondary).lineLimit(1)
            } else if let notice = model.vaultNotice {
                Text(notice).foregroundStyle(Color(StatusMark.green)).lineLimit(1)
            } else {
                Text(Format.vaultFooter(model.vaultListing, settings: model.vaultSettings?.settings.count ?? 0))
                    .foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                    .help("Linked: stored as a 1Password reference, resolved through the 1Password CLI at each use.")
            }
            Spacer(minLength: Win.s5)
            Button("Maintenance…") { actions.openSheet(.maintenance) }
                .buttonStyle(AppButton(kind: .quiet))
                .disabled(model.vaultBusy != nil)
                .help("Orphans, backups, export, import, rekey, duplicates")
        }
        .font(Win.sub)
        .padding(.horizontal, Win.s6)
        .padding(.vertical, Win.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.hover)
        .overlay(alignment: .top) { Rectangle().fill(WindowSurface.separator).frame(height: 1) }
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
    /// Values out of the vault into plain settings, after the sheet asked.
    var moveOut: ([String]) -> Void = { _ in }
    /// A setting into the vault: its Touch ID is the question.
    var moveIn: (String) -> Void = { _ in }
    /// `jit migrate settings`, after the sheet asked.
    var checkSettings: () -> Void = {}
}
