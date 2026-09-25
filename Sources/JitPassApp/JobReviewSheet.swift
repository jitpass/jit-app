// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient
import SwiftUI

/// Review a stopped job (the Jobs mockup, frame F). Names every changed
/// file with the one button that helps for it: git's diff where git tracks
/// the file, the file itself where it does not. The notes lead with the risk,
/// because a changed library is exactly what a patient attack looks like.
/// Approve Again is the same `job_allow` with every setting kept, and its own
/// Touch ID.
struct JobReviewSheet: View {
    @ObservedObject var model: MenuModel
    let actions: JobReviewActions

    var body: some View {
        if let review = model.jobReview {
            VStack(alignment: .leading, spacing: Win.s5) {
                VStack(alignment: .leading, spacing: Win.s3) {
                    Text("Review \(review.job.name)").font(Win.cardTitle)
                    Text(Format.reviewSentence(review)).font(Design.Text.row).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !review.items.isEmpty {
                    AppCardRows {
                        ForEach(Array(review.items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item, last: index == review.items.count - 1)
                        }
                    }
                    .padding(.horizontal, Win.s4)
                    .background(WindowSurface.card, in: RoundedRectangle(cornerRadius: Win.card, style: .continuous))
                }
                if let diff = model.jobReviewDiff {
                    ScrollView {
                        Text(diff).font(Win.command).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Win.s4)
                    }
                    .frame(maxHeight: 180)
                    .background(WindowSurface.verbatim, in: RoundedRectangle(cornerRadius: Win.control, style: .continuous))
                }
                if let error = model.jobError {
                    AppNoteRow(mark: .failed, name: Format.jobFailure, verbatim: error, last: true) { EmptyView() }
                } else {
                    notes
                }
                footer
            }
            .padding(Win.s6)
            .frame(width: Win.sheetWide)
            .background(VisualEffectBackground(material: .underWindowBackground, cornerRadius: 0))
        }
    }

    private func itemRow(_ item: JobReview.Item, last: Bool) -> some View {
        AppRow(name: item.label, badge: item.kind, fact: Format.reviewFact(item, tracked: model.jobReviewTracked), last: last) {
            if let file = item.file {
                if model.jobReviewTracked.contains(file) {
                    Button("Show Changes…") { actions.showChanges(file) }.buttonStyle(AppButton(kind: .quiet))
                } else {
                    Button("Open File") { actions.openFile(file) }.buttonStyle(AppButton(kind: .quiet))
                }
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: Win.s2) {
            Rectangle().fill(WindowSurface.separator).frame(height: 1).padding(.bottom, Win.s4)
            ForEach(Format.reviewNotes, id: \.self) { line in
                Text("• " + line).font(Win.rowFact).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Win.s4) {
            if model.jobBusy {
                ProgressView().controlSize(.small)
                Text(Format.jobFooterWaiting).font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Touch ID follows.").font(Win.sub).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Win.s5)
            Button("Cancel", action: actions.cancel).buttonStyle(AppButton(kind: .secondary))
                .keyboardShortcut(.cancelAction)
            Button("Approve Again with Touch ID", action: actions.approveAgain).buttonStyle(AppButton(kind: .primary))
                .disabled(model.jobBusy)
        }
    }
}

struct JobReviewActions {
    var showChanges: (String) -> Void = { _ in }
    var openFile: (String) -> Void = { _ in }
    var approveAgain: () -> Void = {}
    var cancel: () -> Void = {}
}
