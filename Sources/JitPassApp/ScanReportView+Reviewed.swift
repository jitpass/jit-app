// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Which question comes before a Mark Reviewed: none for one test fixture
/// (the banner's Undo is the way back), the count for Mark All, and the
/// risk first for a finding only the user can fix.
enum ReviewAsk {
    case none
    case all
    case risky
}

/// The marks on screen in the Show Reviewed… sheet, and whether any was
/// removed, so the sheet's close rescans once.
struct ReviewedList: Identifiable, Equatable {
    let id = UUID()
    var entries: [ScanReviewEntry]
    var removed = 0
}

extension ScanReportView {
    /// Marks exist only on an engine that has `jit review`; an older
    /// one shows none of this.
    var canReview: Bool {
        model.scan.map { ScanReview.supported($0.summary) } ?? false
    }

    func markAllReviewedButton(_ groups: [ScanFileGroup]) -> some View {
        let findings = groups.flatMap(\.findings).filter(\.reviewable)
        return Button("Mark All Reviewed…") { actions.markReviewed(findings, .all) }
            .buttonStyle(AppButton())
            .disabled(findings.isEmpty || model.toolsBusy != nil)
    }

    /// The row menu's mark, on the two tiers it belongs to.
    @ViewBuilder
    func markReviewedItem(_ group: ScanFileGroup, tier: ScanTier) -> some View {
        let findings = group.findings.filter(\.reviewable)
        if canReview, tier == .testFixtures || tier == .needsYou, !findings.isEmpty {
            Button("Mark Reviewed") { actions.markReviewed(findings, tier == .needsYou ? .risky : .none) }
            Divider()
        }
    }
}

/// Show Reviewed…: every mark, each with Unmark. The value is never here;
/// jit does not keep it.
struct ReviewedSheet: View {
    @ObservedObject var model: MenuModel
    let list: ReviewedList
    let unmark: (ScanReviewEntry) -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Win.s5) {
            VStack(alignment: .leading, spacing: Win.s1) {
                Text(Format.reviewedSheetTitle(list.entries.count)).font(Win.cardTitle)
                Text(Format.reviewedSheetNote).font(Win.sub).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(list.entries.enumerated()), id: \.element.id) { index, entry in
                        AppRow(
                            name: Format.fileName(entry.path),
                            detail: entry.line.map { "line \($0)" },
                            fact: Format.reviewedFact(entry),
                            last: index == list.entries.count - 1
                        ) {
                            Button("Unmark") { unmark(entry) }
                                .buttonStyle(AppButton(kind: .quiet))
                                .disabled(model.toolsBusy != nil || entry.markID == nil)
                        }
                    }
                }
                .padding(.horizontal, Win.s5)
                .padding(.vertical, Win.s2)
            }
            .frame(maxHeight: 280)
            .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
            HStack {
                Spacer()
                Button("Done", action: close).buttonStyle(AppButton(kind: .primary)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Win.s6)
        .frame(width: Win.sheetWide)
        // app-sheet-material: the window's own material, not macOS's default sheet.
        .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
    }
}
