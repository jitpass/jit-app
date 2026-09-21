// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The scan report, built from the window system (`docs/design/windows.md`
/// and the design system's own page): header, filter, body, footer, at one
/// inset, holding one card per tier that has anything in it, holding one
/// row per file. A tier with nothing in it has no card, so the window
/// never prints the word "nothing"; a file's flagged lines open in a sheet
/// rather than nesting a fourth level under its row.
struct ScanReportView: View {
    @ObservedObject var model: MenuModel
    let actions: ScanActions

    /// The tier the filter is on; nil is all of them. It is reset by a new
    /// report, because a pill for a tier that scan no longer has would
    /// leave the body empty with no way back.
    @State var tier: ScanTier?

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.scanError {
                failed(error)
            } else if model.scanning {
                scanning
            } else if let report = model.scan {
                report_(report)
            } else {
                chooser
            }
        }
        .frame(
            minWidth: Win.width, maxWidth: .infinity,
            minHeight: Win.minHeight, maxHeight: .infinity,
            alignment: .top
        )
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        .onChange(of: model.scan) { _ in tier = nil }
        .sheet(item: $model.scanSheet) { sheet in
            if case let .result(title, text) = sheet {
                ResultSheet(title: title, text: text, close: actions.closeSheet)
            }
        }
        .sheet(item: $model.scanLines) { group in
            ScanLinesSheet(group: group, actions: actions) { model.scanLines = nil }
        }
    }

    // MARK: - The report

    @ViewBuilder
    private func report_(_ report: ScanReport) -> some View {
        header(report)
        if report.showsTierFilter {
            filter(report).windowRegion()
        }
        ScrollView {
            VStack(alignment: .leading, spacing: Win.s5) {
                ForEach(shown(report)) { tier in
                    card(tier, report)
                }
            }
            .padding(Win.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        footer(report)
    }

    /// The tiers the body draws: the filter's one, or all of the ones this
    /// scan has.
    private func shown(_ report: ScanReport) -> [ScanTier] {
        guard let tier, report.count(in: tier) > 0 else {
            return report.tiersPresent
        }
        return [tier]
    }

    // MARK: - Cards

    @ViewBuilder
    private func card(_ tier: ScanTier, _ report: ScanReport) -> some View {
        if tier == .agentCaches {
            agentCard(report.agentCacheGroups)
        } else {
            let groups = report.groups(in: tier)
            AppCard(
                eyebrow: Format.tierLabel(tier),
                eyebrowTint: Color(Self.tierTint(tier)),
                title: Format.tierTitle(tier, files: groups.count),
                note: Format.tierNote(tier)
            ) {
                if tier == .protect, report.migratable.count > 1 {
                    Button("Protect All \(groups.count)…") { actions.protectAll(report.protectPlan) }
                        .buttonStyle(AppButton(kind: .secondary))
                        .disabled(model.toolsBusy != nil)
                }
            } rows: {
                AppCardRows {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        fileRow(group, tier: tier, last: index == groups.count - 1)
                    }
                }
            }
        }
    }

    static func tierTint(_ tier: ScanTier) -> NSColor {
        switch tier {
        case .protect: StatusMark.amber
        case .needsYou, .agentCaches: StatusMark.red
        case .testFixtures: .tertiaryLabelColor
        }
    }

    /// One file. The name comes first and its folder after it, so two
    /// rows never open with the same six words, and the fact under them
    /// is one clause: the flagged line, or how many there are.
    private func fileRow(_ group: ScanFileGroup, tier: ScanTier, last: Bool) -> some View {
        AppRow(
            name: Format.fileName(group.filePath),
            detail: Format.parentFolder(group.filePath),
            badge: isNew(group.findings) ? "new" : nil,
            fact: group.fact,
            last: last
        ) {
            if group.findings.count > 1, tier != .protect {
                Button("\(group.findings.count) Lines…") { actions.showLines(group) }
                    .buttonStyle(AppButton(kind: .plain))
            }
            Button("Open") { actions.open(group.filePath, group.firstLine) }
                .buttonStyle(AppButton())
            if tier == .protect, let finding = group.findings.first(where: { $0.fixCommand != nil }) {
                Button("Protect…") { actions.protect(finding) }
                    .buttonStyle(AppButton(kind: .secondary))
                    .disabled(model.toolsBusy != nil)
            }
            rowMenu(group)
        }
    }

    /// Whether any of these findings is one the previous whole-Mac scan
    /// did not have. Only the whole-Mac report keeps that comparison; a
    /// folder scan marks nothing.
    func isNew(_ findings: [ScanFinding]) -> Bool {
        guard model.scanScope == nil, let new = model.macScanNew else {
            return false
        }
        return findings.contains { new.contains($0.id) }
    }

    /// Everything cheap and reversible, where a mis-click costs nothing.
    private func rowMenu(_ group: ScanFileGroup) -> some View {
        Menu {
            Button("Reveal in Finder") { actions.reveal(group.filePath) }
            Button("Copy Path") { actions.copyPath(group.filePath) }
            if group.findings.count > 1 {
                Divider()
                Button("Show \(group.findings.count) Lines…") { actions.showLines(group) }
            }
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton())
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Footer

    /// What the scan found on the left, the one action on the right.
    private func footer(_ report: ScanReport) -> some View {
        HStack(spacing: Win.s4) {
            StateDot(tint: Color(report.tiersPresent.isEmpty ? StatusMark.green : Self.tierTint(report.tiersPresent[0])))
            Text(Format.scanFooter(report)).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: Win.s5)
            if report.count(in: .protect) > 0 {
                Button("Protect All \(report.groups(in: .protect).count)…") { actions.protectAll(report.protectPlan) }
                    .buttonStyle(AppButton(kind: .primary))
                    .disabled(model.toolsBusy != nil)
            }
        }
        .padding(.horizontal, Win.s6)
        .padding(.vertical, Win.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WindowSurface.hover)
        .overlay(alignment: .top) { Rectangle().fill(WindowSurface.separator).frame(height: 1) }
    }
}

struct ScanActions {
    var rescan: () -> Void = {}
    var newScan: () -> Void = {}
    var openSettings: () -> Void = {}
    var chooseFolder: () -> Void = {}
    var scanWholeMac: () -> Void = {}
    var protect: (ScanFinding) -> Void = { _ in }
    var protectAll: (ProtectPlan) -> Void = { _ in }
    var closeSheet: () -> Void = {}
    var open: (String, Int?) -> Void = { _, _ in }
    var reveal: (String) -> Void = { _ in }
    var copyPath: (String) -> Void = { _ in }
    var showLines: (ScanFileGroup) -> Void = { _ in }
    var grantFullDiskAccess: () -> Void = {}
    var cleanCaches: () -> Void = {}
}
