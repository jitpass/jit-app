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
                Text(subline())
                    .font(Win.sub).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let fraction = coverage(report), fraction < 1 {
                    CoverageBar(fraction: fraction, tint: Color(StatusMark.amber))
                        .frame(width: 320).padding(.top, Win.s3)
                }
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

    /// The schedule's line for the whole Mac; a folder scan has no
    /// schedule and no previous run, so it says only where and when.
    func subline() -> String {
        if let folder = model.scanScope {
            return ScanWording.folderSubline(
                folder: Format.home(folder), at: nil,
                excludes: model.scanExcludes.count, fullDiskAccess: model.fullDiskAccess,
                deep: model.scan?.summary.deep == true
            )
        }
        guard let at = model.macScanAt, let kind = model.macScanKind else {
            return ScanWording.folderSubline(
                folder: "Whole Mac", at: model.macScanAt,
                excludes: model.scanExcludes.count, fullDiskAccess: model.fullDiskAccess
            )
        }
        return ScanWording.wholeMacSubline(ScanRun(
            kind: kind, at: at, schedule: model.scanSchedule,
            newCount: model.macScanNew?.count, previousAt: model.previousMacScanAt,
            excludes: model.scanExcludes.count, fullDiskAccess: model.fullDiskAccess,
            vaultCopies: model.macScan?.vaultCopies.count ?? 0
        ))
    }

    func headline(_ report: ScanReport?) -> String {
        guard let summary = report?.summary else {
            return model.scanning ? "Scanning…" : "No findings yet"
        }
        return Format.scanHeadline(summary, wholeMac: model.scanScope == nil)
    }

    /// Green when the vault holds everything jit knows of, amber while
    /// anything is still in the open. The mark is the window's one state,
    /// and it always has the headline beside it.
    func headTint(_ report: ScanReport?) -> Color {
        guard let summary = report?.summary else {
            return Color(StatusMark.amber)
        }
        let clean = summary.percent >= 100 && report?.tiersPresent.contains(.needsYou) != true
        return Color(clean ? StatusMark.green : StatusMark.amber)
    }

    /// The share of known secrets already in the vault. A folder scan has
    /// no ledger of its own, so it has no bar.
    func coverage(_ report: ScanReport?) -> Double? {
        guard model.scanScope == nil, let s = report?.summary, s.secretsTotal > 0 else {
            return nil
        }
        return Double(s.secretsProtected) / Double(s.secretsTotal)
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
