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
            } else if model.scanning, model.scan == nil || (model.scanDeep && !vaultUnlocked) {
                // A first scan, or a deep scan waiting on the vault, takes the
                // window. A rescan after a Protect keeps the report on screen
                // and spins in the header: reading the Mac again is not news.
                scanning
            } else if let report = model.scan, !model.scanChoosing {
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
            switch sheet {
            case let .result(title, text):
                ResultSheet(title: title, text: text, close: actions.closeSheet)
            case let .scanDepth(scope):
                ScanDepthSheet(model: model, scope: scope, start: { actions.startScan(scope, $0) }, close: actions.closeSheet)
            default:
                EmptyView()
            }
        }
        .sheet(item: $model.scanLines) { group in
            ScanLinesSheet(group: group, actions: actions) { model.scanLines = nil }
        }
    }

    // MARK: - The report

    @ViewBuilder
    private func report_(_ report: ScanReport) -> some View {
        banner
        header(report)
        if report.showsTierFilter {
            filter(report).windowRegion()
        }
        if report.tiersPresent.isEmpty {
            clean(report)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Win.s5) {
                    ForEach(shown(report)) { tier in
                        card(tier, report)
                    }
                }
                .padding(Win.s6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        footer(report)
    }

    /// What just happened, above the header: the Protect's sentence in
    /// the state's colour, jit's own words one click away, and Undo when
    /// there is a file to restore. Only after something happened.
    @ViewBuilder
    private var banner: some View {
        if let outcome = model.findingsOutcome {
            WindowBanner(tint: Color(outcome.failed ? StatusMark.red : StatusMark.green), text: outcome.title) {
                if !outcome.text.isEmpty {
                    Button("What jit Did…") { actions.showOutcome(outcome) }.buttonStyle(AppButton(kind: .plain))
                }
                if !outcome.undo.isEmpty {
                    Button("Undo") { actions.undoProtect(outcome.undo) }.buttonStyle(AppButton())
                        .disabled(model.toolsBusy != nil)
                }
            }
        }
    }

    /// A report with nothing in it says the true thing, not that a list
    /// is empty.
    private func clean(_ report: ScanReport) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            WindowEmptyState(
                tint: Color(StatusMark.green),
                title: model.scanScope == nil ? "No secret is exposed on this Mac" : "No secret is exposed in " + Format
                    .home(model.scanScope ?? ""),
                message: ScanWording.cleanMessage(
                    filesRead: report.summary.filesScanned, schedule: model.scanSchedule, last: model.macScanAt ?? Date()
                )
            ) {
                Button("Scan Now…") { actions.askDepth(model.scanScope) }.buttonStyle(AppButton()).disabled(model.scanning)
            }
            Spacer(minLength: 0)
        }
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
            agentCard(report.agentCacheGroups, shapes: report.cacheShapeGroups)
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
                        if tier == .vaultCopies {
                            vaultCopyRow(group, last: index == groups.count - 1)
                        } else {
                            fileRow(group, tier: tier, last: index == groups.count - 1)
                        }
                    }
                }
            }
        }
    }

    static func tierTint(_ tier: ScanTier) -> NSColor {
        switch tier {
        case .protect: StatusMark.amber
        case .vaultCopies, .needsYou, .agentCaches: StatusMark.red
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

    /// A deep scan's find: the vault path first — the one card whose secret
    /// jit knows by name — then where the copy sits, then the scanner's own
    /// sentence. Clean Caches for a copy in an agent's cache; a copy in a
    /// plain file is the reader's to delete, after rotating.
    private func vaultCopyRow(_ group: ScanFileGroup, last: Bool) -> some View {
        let first = group.findings.first
        let location = Format.home(group.filePath) + (group.firstLine.map { " : \($0)" } ?? "")
        return AppRow(
            name: first?.keyName ?? Format.fileName(group.filePath),
            detail: location,
            badge: isNew(group.findings) ? "new" : nil,
            fact: first?.evidence ?? "",
            last: last
        ) {
            Button("Open") { actions.open(group.filePath, group.firstLine) }.buttonStyle(AppButton())
            if first?.agent != nil {
                Button("Clean Caches…", action: actions.cleanCaches)
                    .buttonStyle(AppButton(kind: .secondary)).disabled(model.toolsBusy != nil)
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
    /// Back from the chooser to the report it sits over.
    var showFindings: () -> Void = {}
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
    var undoProtect: ([String]) -> Void = { _ in }
    var showOutcome: (WindowOutcome) -> Void = { _ in }
    /// Redact tokens found by format: in these files (empty: every agent
    /// cache), on these lines (empty: every line); `what` names it for the
    /// dialog ("the SendGrid API Key on line 1046", "8 tokens in this file").
    var redact: ([String], [Int], String, String?) -> Void = { _, _, _, _ in }
    /// Raise the depth sheet for a scope (nil: the whole Mac).
    var askDepth: (String?) -> Void = { _ in }
    /// The sheet's answer: scan this scope at this depth.
    var startScan: (String?, ScanMode) -> Void = { _, _ in }
}
