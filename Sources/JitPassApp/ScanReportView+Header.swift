// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// The Findings window's first two regions: the header that names what
/// you are looking at and counts it once — and, for the whole Mac, owns
/// the schedule: who ran it, when, when the next is due, what is new —
/// and the filter that appears only when there is more than one tier to
/// narrow.
extension ScanReportView {
    /// What you are looking at, counted once, and the one sentence that
    /// changes the decision: where jit looked, and what it could not see.
    func header(_ report: ScanReport?) -> some View {
        HStack(spacing: Win.s5) {
            WindowMark(tint: headTint(report))
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(headline(report)).font(Win.head)
                if let report {
                    todoLines(report).padding(.top, Win.s2)
                }
                Text(subline(report))
                    .font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Win.s3)
            }
            Spacer(minLength: Win.s5)
            HStack(spacing: Win.s3) {
                if !model.fullDiskAccess {
                    Button("Grant Access…", action: actions.grantFullDiskAccess)
                        .buttonStyle(AppButton())
                        .help("Opens System Settings › Privacy & Security › Full Disk Access. Add JitPass there.")
                }
                if model.scanning {
                    ProgressView().controlSize(.small)
                }
                Button("Scan Now…") { actions.askDepth(model.scanScope) }
                    .buttonStyle(AppButton()).disabled(model.scanning || model.scan == nil)
                moreMenu
            }
        }
        .windowRegion()
    }

    /// Everything else a scan can do: one menu, so the header never holds
    /// five buttons that truncate the moment the window narrows.
    var moreMenu: some View {
        Menu {
            Button("New Scan", action: actions.newScan)
            Button("Scan Folder…", action: actions.chooseFolder)
            Divider()
            Button("Scan Whole Mac…", action: actions.scanWholeMac)
            Button("Excluded Folders…", action: actions.openSettings)
            if model.fullDiskAccess {
                Button("Full Disk Access Settings…", action: actions.grantFullDiskAccess)
            }
        } label: {
            Text("···")
        }
        .menuStyle(.button)
        .buttonStyle(AppButton())
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// One line per tier with something in it: the card's numbers, then
    /// the card's verb as a link that narrows the window to that card.
    func todoLines(_ report: ScanReport) -> some View {
        HeaderTodoLines(todos: report.todos(deepAvailable: deepAvailable).map { todo in
            HeaderTodo(id: todo.id, text: todo.text, verb: todo.verb, tint: Self.todoTint(todo)) { act(on: todo) }
        })
    }

    private var deepAvailable: Bool {
        ScanMode.deepAvailable(secretsStored: model.cli?.vault?.secretsStored)
    }

    private func act(on todo: ScanTodo) {
        switch todo.action {
        case let .show(shown): tier = shown
        case .deepScan: actions.askDepth(model.scanScope)
        case .none: break
        }
    }

    static func todoTint(_ todo: ScanTodo) -> Color {
        switch todo.action {
        case let .show(shown): Color(tierTint(shown))
        case .deepScan: Color(.tertiaryLabelColor)
        case .none: Color(StatusMark.green)
        }
    }

    /// The schedule's line for the whole Mac; a folder scan has no
    /// schedule and no previous run, so it says only where and when.
    func subline(_ report: ScanReport?) -> String {
        let fixtures = report?.count(in: .testFixtures) ?? 0
        if let folder = model.scanScope {
            return ScanWording.folderSubline(
                folder: Format.home(folder), at: nil,
                excludes: model.scanExcludes.count, fullDiskAccess: model.fullDiskAccess,
                deep: model.scan?.summary.deep == true, fixtures: fixtures
            )
        }
        guard let at = model.macScanAt, let kind = model.macScanKind else {
            return ScanWording.folderSubline(
                folder: "Whole Mac", at: model.macScanAt,
                excludes: model.scanExcludes.count, fullDiskAccess: model.fullDiskAccess, fixtures: fixtures
            )
        }
        return ScanWording.wholeMacSubline(ScanRun(
            kind: kind, at: at, schedule: model.scanSchedule,
            newCount: model.macScanNew?.count, previousAt: model.previousMacScanAt,
            excludes: model.scanExcludes.count, fullDiskAccess: model.fullDiskAccess,
            vaultCopies: model.macScan?.vaultCopies.count ?? 0,
            vaultCopiesFrom: kind.isDeep ? nil : model.macDeepScanAt,
            fixtures: fixtures
        ))
    }

    func headline(_ report: ScanReport?) -> String {
        guard let summary = report?.summary else {
            return model.scanning ? "Scanning…" : "No findings yet"
        }
        return Format.scanHeadline(summary, wholeMac: model.scanScope == nil, secretsStored: model.cli?.vault?.secretsStored)
    }

    /// Green when no line asks anything of the reader, amber while one
    /// does. The mark is the window's one state, and it always has the
    /// headline beside it.
    func headTint(_ report: ScanReport?) -> Color {
        guard let report else {
            return Color(StatusMark.amber)
        }
        let asks = report.todos(deepAvailable: false).contains {
            if case .show = $0.action {
                true
            } else {
                false
            }
        }
        return Color(asks ? StatusMark.amber : StatusMark.green)
    }

    /// One pill per tier this scan has, with its count. A tier with
    /// nothing in it is absent, never greyed. No dot: a scan's tiers are
    /// all findings, so a dot on every pill would say nothing.
    func filter(_ report: ScanReport) -> some View {
        AppSegmented(items: pills(report), selection: $tier)
    }

    private func pills(_ report: ScanReport) -> [AppSegmentItem<ScanTier?>] {
        [AppSegmentItem(value: nil, title: "All", count: report.summary.totalFindings)]
            + report.tiersPresent.map {
                AppSegmentItem(value: $0, title: Format.tierLabel($0), count: report.count(in: $0))
            }
    }
}
