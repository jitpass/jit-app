// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Findings' review marks: `jit review` for a finding the user checked and
/// says is not live, `jit unreview` to take a mark back by its id. The app
/// never sees a value; jit rescans the named lines itself.
extension StatusItemController {
    /// Everything `jit review|unreview` printed, as a failure when it did
    /// not exit 0.
    nonisolated static func review(_ arguments: [String]) -> Result<String, Error> {
        JitCLI.invoke(arguments).flatMap { outcome in
            outcome.status == 0 ? .success(outcome.output) : .failure(JitCLI.CLIError.failed(outcome.output))
        }
    }

    func markReviewed(_ findings: [ScanFinding], ask: ReviewAsk) {
        guard !findings.isEmpty else {
            return
        }
        if ask != .none {
            let question = ask == .risky ? Format.reviewRiskyQuestion : Format.reviewAllQuestion(findings)
            let alert = NSAlert()
            alert.messageText = question.title
            alert.informativeText = question.message
            // A likely live key: Return cancels. Mark All keeps Return on
            // Mark Reviewed; its question already counts what goes.
            let risky = ask == .risky
            alert.addButton(withTitle: risky ? "Cancel" : "Mark Reviewed")
            alert.addButton(withTitle: risky ? "Mark Reviewed" : "Cancel")
            let marked: NSApplication.ModalResponse = risky ? .alertSecondButtonReturn : .alertFirstButtonReturn
            guard alert.runFrontmost() == marked else {
                return
            }
        }
        model.findingsOutcome = nil
        let arguments = ScanReview.arguments(for: findings)
        runTools(
            "review",
            refresh: false,
            failed: "Mark Reviewed",
            reportsTo: .findings,
            work: { Self.review(arguments) },
            then: { [weak self] output in
                guard let self else {
                    return
                }
                // Undo removes exactly the marks this run made, by id.
                let result = try? JSONDecoder().decode(ScanReviewResult.self, from: Data(output.utf8))
                let marks = (result?.reviewed ?? []).compactMap(\.markID)
                // Only the rows jit marked leave: one it skipped (a copy
                // Protect or Redact fixes) stays on screen. An engine whose
                // answer does not parse gets the old word: all of them.
                let settled = result.map { ScanReview.marked(findings, by: $0) } ?? findings
                model.protectedSinceScan.add(reviewed: settled, at: Date())
                model.scanLines = nil
                model.scan = model.scan?.removingReviewed(settled)
                model.macScan = model.macScan?.removingReviewed(settled)
                if let report = model.macScan, let at = model.macScanAt, let kind = model.macScanKind {
                    LastScanStore.save(LastScan(report: report, at: at, kind: kind, deepAt: model.macDeepScanAt))
                }
                model.findingsOutcome = WindowOutcome(
                    title: Format.reviewedBanner(settled, missed: result?.missed?.count ?? 0), text: "", unreview: marks
                )
            }
        )
    }

    /// The banner's Undo: the marks go, and the rescan brings the findings back.
    func unreview(_ markIDs: [String]) {
        model.findingsOutcome = nil
        runTools(
            "review",
            refresh: false,
            failed: "Undo",
            reportsTo: .findings,
            work: { Self.review(ScanReview.unreviewArguments(markIDs)) },
            then: { [weak self] output in
                let result = try? JSONDecoder().decode(ScanReviewResult.self, from: Data(output.utf8))
                self?.model.findingsOutcome = WindowOutcome(
                    title: Format.unreviewedBanner(result?.unreviewed?.count ?? markIDs.count),
                    text: ""
                )
                self?.runScan(wholeMac: true, kind: .afterProtect)
            }
        )
    }

    func showReviewed() {
        runTools(
            "review",
            refresh: false,
            failed: "Show Reviewed",
            reportsTo: .findings,
            work: { Self.review(ScanReview.listArguments) },
            then: { [weak self] output in
                let result = try? JSONDecoder().decode(ScanReviewResult.self, from: Data(output.utf8))
                self?.model.scanReviewed = ReviewedList(entries: result?.reviewed ?? [])
            }
        )
    }

    func unmarkFromList(_ entry: ScanReviewEntry) {
        guard let markID = entry.markID else {
            return
        }
        runTools(
            "review",
            refresh: false,
            failed: "Unmark",
            reportsTo: .findings,
            work: { Self.review(ScanReview.unreviewArguments([markID])) },
            then: { [weak self] _ in
                guard let self, var list = model.scanReviewed else {
                    return
                }
                list.entries.removeAll { $0.id == entry.id }
                list.removed += 1
                model.scanReviewed = list
            }
        )
    }

    /// Done: one rescan for however many marks the sheet removed.
    func closeReviewed() {
        let removed = model.scanReviewed?.removed ?? 0
        model.scanReviewed = nil
        if removed > 0 {
            model.findingsOutcome = WindowOutcome(title: Format.unreviewedBanner(removed), text: "")
            runScan(wholeMac: true, kind: .afterProtect)
        }
    }
}
