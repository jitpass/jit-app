// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The orphaned secrets, as a list you choose from instead of two modals
/// holding CLI output. Sizes and colours come from the JitPass design
/// system's App tokens: `app-headline` 15/700 for the title, `app-row` 13
/// for a row, `app-detail` 12 for a fact line, `app-sheet-note` 11 for the
/// keys, and `accent-dim` behind a selected row. State colour stays in
/// `StatusMark`, which holds the same hexes as `app-unlocked`,
/// `app-locked` and `app-asking`.
///
/// One row per project (the first path segment, as everywhere else in this
/// window), expandable to its keys, with the origin jit recorded beside it. Delete takes the selection
/// through the same `jit vault rm` dry run every other delete here uses, so
/// a secret that stopped being an orphan since the listing is refused
/// rather than deleted.
///
/// Stale mount registrations are listed apart and cleared apart: jit makes
/// that registry edit only inside `vault orphans --prune`, which deletes
/// every orphaned secret in the same pass, so the button says so and the
/// dialog says it again.
/// The design system's app spacing and row sizes, by their token names, so
/// a number in this file can be checked against the system rather than
/// guessed. Anything not named here is a multiple of `divider`.
private enum Token {
    /// space-app-sheet
    static let sheet: CGFloat = 18
    /// space-app-row-gap: control to label inside a row.
    static let rowGap: CGFloat = 12
    /// space-app-divider
    static let divider: CGFloat = 5
    /// size-status-row: the height of a row that states something.
    static let statusRow: CGFloat = 26
    /// radius-row: a row's own highlight.
    static let rowRadius: CGFloat = 5
}

struct VaultOrphansSheet: View {
    @ObservedObject var model: MenuModel
    let actions: VaultActions

    @State private var filter = ""
    @State private var selection: Set<String> = []
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let orphans = model.vaultOrphans {
                if orphans.isEmpty {
                    empty
                } else {
                    toolbar(orphans)
                    Divider()
                    list(orphans)
                    Divider()
                    footer(orphans)
                }
            } else {
                Text("Reading the vault…").foregroundStyle(.secondary).padding(Token.sheet + Token.rowGap)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 620)
        .frame(minHeight: 240, maxHeight: 620)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(model.vaultBusy != nil)
        .onAppear(perform: actions.loadOrphans)
        // The listing lands after the sheet is on screen, so both of these
        // belong to its arrival, not to onAppear, where there is nothing
        // to expand or to drop yet.
        .onChange(of: model.vaultOrphans) { _, _ in
            dropVanishedSelection()
            expandWhatFits()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Orphaned secrets").font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Done", action: actions.closeSheet).keyboardShortcut(.cancelAction)
            }
            Text(summary).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.vaultMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(Color(StatusMark.red))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let notice = model.vaultNotice {
                Text(notice).font(.system(size: 12)).foregroundStyle(Color(StatusMark.green))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let busy = model.vaultBusy {
                Text("Touch ID for \(busy)…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(Token.sheet)
    }

    /// What the window is about, in counts the user can check against the
    /// rows, and the one thing jit cannot promise: it never looked outside
    /// the home folder.
    private var summary: String {
        guard let orphans = model.vaultOrphans, !orphans.isEmpty else {
            return "Nothing jit can see uses these, and jit only searches your home folder."
        }
        var parts: [String] = []
        let secrets = orphans.orphans.count
        if secrets > 0 {
            let projects = orphans.groups.count
            parts.append("\(secrets) secret\(secrets == 1 ? "" : "s") in \(projects) project\(projects == 1 ? "" : "s")")
        }
        if !orphans.staleMounts.isEmpty {
            parts.append("\(orphans.staleMounts.count) stale mount registration\(orphans.staleMounts.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
            + ". No profile or pointer file jit can find uses them, but a project outside your home folder is never searched: "
            + "check the origins before deleting."
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("No orphaned secrets").font(.system(size: 15, weight: .bold))
            Text("Every secret in the vault belongs to a profile jit can see.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(Token.sheet + Token.rowGap)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Toolbar

    private func toolbar(_ orphans: VaultOrphans) -> some View {
        HStack(spacing: 10) {
            TextField("Filter by project, key or origin", text: $filter)
                .textFieldStyle(.roundedBorder)
            Button(allSelected(orphans) ? "Select None" : "Select All") {
                selection = allSelected(orphans) ? [] : Set(orphans.groups(matching: filter).map(\.name))
            }
            .buttonStyle(.link)
        }
        .padding(.horizontal, Token.sheet).padding(.vertical, Token.divider * 2)
    }

    private func allSelected(_ orphans: VaultOrphans) -> Bool {
        let shown = orphans.groups(matching: filter).map(\.name)
        return !shown.isEmpty && shown.allSatisfy { selection.contains($0) }
    }

    // MARK: - List

    @ViewBuilder private func list(_ orphans: VaultOrphans) -> some View {
        let shown = orphans.groups(matching: filter)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if shown.isEmpty, !orphans.orphans.isEmpty {
                    Text("Nothing matches \"\(filter)\".").foregroundStyle(.secondary).padding(Token.sheet)
                }
                ForEach(shown) { group in
                    groupRow(group)
                    Divider()
                }
                if !orphans.staleMounts.isEmpty {
                    StaleMountsSection(orphans: orphans, clear: actions.clearStaleMounts)
                }
            }
        }
        .frame(maxHeight: 420)
    }

    private func groupRow(_ group: VaultOrphanGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Token.divider + 3) {
                Toggle("", isOn: binding(for: group.name)).labelsHidden()
                    .help("Include \(group.name) in the delete")
                Button {
                    if expanded.contains(group.name) {
                        expanded.remove(group.name)
                    } else {
                        expanded.insert(group.name)
                    }
                } label: {
                    Image(systemName: expanded.contains(group.name) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 12)
                }
                .buttonStyle(.plain)
                .help(expanded.contains(group.name) ? "Hide the keys" : "Show the keys")
                Text(group.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Text("\(group.orphans.count) secret\(group.orphans.count == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text(Format.orphanOrigin(group))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 210, alignment: .trailing)
                    .help(group.origins.isEmpty ? "jit recorded no origin for these" : group.origins.joined(separator: "\n"))
            }
            .frame(height: Token.statusRow)
            .padding(.horizontal, Token.sheet)
            .contentShape(Rectangle())
            .onTapGesture { toggle(group.name) }
            if expanded.contains(group.name) {
                KeyChips(group.keys)
                    .padding(.leading, Token.sheet + keyIndent).padding(.trailing, Token.sheet)
                    .padding(.bottom, Token.divider + 2)
            }
        }
        // A selected row takes the brand's own tint, not the system
        // accent: jit's design system spends one hue, and `accent-dim`
        // (the green at 0.13) is what it puts behind a selected thing.
        // The checkbox itself stays the system accent, as every macOS
        // control does.
        .background(
            RoundedRectangle(cornerRadius: Token.rowRadius)
                .fill(selection.contains(group.name) ? Color(StatusMark.green).opacity(0.13) : .clear)
                .padding(.horizontal, Token.divider)
        )
    }

    // MARK: - Footer

    /// Show Origin appears only when there is a file to show. jit records
    /// an origin at migrate time and none for a secret set directly, so a
    /// selection can have one, some or no origins at all; a button that is
    /// always there and always grey teaches nothing, and the row already
    /// says "origin not recorded". It takes whichever of the selected
    /// projects do have one, rather than going dark because one does not.
    private func footer(_ orphans: VaultOrphans) -> some View {
        let chosen = orphans.groups.filter { selection.contains($0.name) }
        let paths = chosen.flatMap(\.paths)
        let origins = Self.origins(of: chosen)
        return HStack(spacing: 10) {
            Text(count(chosen, secrets: paths.count)).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            if !origins.isEmpty {
                Button(origins.count == 1 ? "Show Origin in Finder" : "Show \(origins.count) Origins in Finder") {
                    actions.revealOrigins(origins)
                }
                .controlSize(.small)
                .help(origins.joined(separator: "\n"))
            }
            Button(role: .destructive) { actions.delete(paths) } label: {
                Text(paths.isEmpty ? "Delete" : "Delete \(paths.count)…")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(StatusMark.red))
            .controlSize(.small)
            .disabled(paths.isEmpty)
        }
        .padding(.horizontal, Token.sheet).padding(.vertical, Token.rowGap)
    }

    /// Every file the selected projects were migrated from, each once.
    static func origins(of groups: [VaultOrphanGroup]) -> [String] {
        var seen: [String] = []
        for origin in groups.flatMap(\.origins) where !seen.contains(origin) {
            seen.append(origin)
        }
        return seen
    }

    private func count(_ chosen: [VaultOrphanGroup], secrets: Int) -> String {
        guard secrets > 0 else {
            return "Nothing selected"
        }
        return "\(secrets) secret\(secrets == 1 ? "" : "s") selected in "
            + "\(chosen.count) project\(chosen.count == 1 ? "" : "s")"
    }

    /// Where a project's name starts: the checkbox, the disclosure and the
    /// two gaps before it, so its keys line up under it.
    private var keyIndent: CGFloat {
        16 + 12 + (Token.divider + 3) * 2
    }

    // MARK: - Selection

    private func binding(for name: String) -> Binding<Bool> {
        Binding(get: { selection.contains(name) }, set: { _ in toggle(name) })
    }

    private func toggle(_ name: String) {
        if selection.contains(name) {
            selection.remove(name)
        } else {
            selection.insert(name)
        }
    }

    /// A list short enough to read whole opens read whole: the keys are
    /// what tells you whether a project is yours to delete, and a window
    /// with room to spare should not make you click twice to see them.
    /// Past that many projects the list is for scanning, and the rows stay
    /// closed until asked.
    private func expandWhatFits() {
        guard expanded.isEmpty, let groups = model.vaultOrphans?.groups, groups.count <= Self.expandUpTo else {
            return
        }
        expanded = Set(groups.map(\.name))
    }

    static let expandUpTo = 4

    /// A delete leaves the selection naming projects that are gone; drop
    /// them so the footer never counts secrets that no longer exist.
    private func dropVanishedSelection() {
        let live = Set(model.vaultOrphans?.groups.map(\.name) ?? [])
        selection.formIntersection(live)
        expanded.formIntersection(live)
    }
}
