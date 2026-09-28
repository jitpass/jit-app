// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import AppKit
import JitAgentClient

/// Findings' review marks: `jit scan review` for a finding the user checked
/// and says is not live, `jit scan unreview` to take a mark back. The app
/// never sees a value; jit rescans the named lines itself.
extension StatusItemController {
    /// Everything `jit scan review|unreview` printed, as a failure when it
    /// did not exit 0.
    nonisolated static func review(_ arguments: [String]) -> Result<String, Error> {
        JitCLI.invoke(["scan"] + arguments + ["--format", "json"]).flatMap { outcome in
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
            alert.addButton(withTitle: "Mark Reviewed")
            alert.addButton(withTitle: "Cancel")
            guard alert.runFrontmost() == .alertFirstButtonReturn else {
                return
            }
        }
        model.findingsOutcome = nil
        let targets = ScanReview.targets(findings)
        runTools(
            "review",
            refresh: false,
            failed: "Mark Reviewed",
            reportsTo: .findings,
            work: { Self.review(["review"] + targets) },
            then: { [weak self] _ in
                guard let self else {
                    return
                }
                model.scanLines = nil
                model.scan = model.scan?.removingReviewed(findings)
                model.macScan = model.macScan?.removingReviewed(findings)
                if let report = model.macScan, let at = model.macScanAt, let kind = model.macScanKind {
                    LastScanStore.save(LastScan(report: report, at: at, kind: kind, deepAt: model.macDeepScanAt))
                }
                model.findingsOutcome = WindowOutcome(title: Format.reviewedBanner(findings), text: "", unreview: targets)
            }
        )
    }

    /// The banner's Undo: the marks go, and the rescan brings the findings back.
    func unreview(_ targets: [String]) {
        model.findingsOutcome = nil
        runTools(
            "review",
            refresh: false,
            failed: "Undo",
            reportsTo: .findings,
            work: { Self.review(["unreview"] + targets) },
            then: { [weak self] output in
                let result = try? JSONDecoder().decode(ScanReviewResult.self, from: Data(output.utf8))
                self?.model.findingsOutcome = WindowOutcome(
                    title: Format.unreviewedBanner(result?.unreviewed?.count ?? targets.count),
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
            work: { Self.review(["review", "--list"]) },
            then: { [weak self] output in
                let result = try? JSONDecoder().decode(ScanReviewResult.self, from: Data(output.utf8))
                self?.model.scanReviewed = ReviewedList(entries: result?.reviewed ?? [])
            }
        )
    }

    func unmarkFromList(_ entry: ScanReviewEntry) {
        runTools(
            "review",
            refresh: false,
            failed: "Unmark",
            reportsTo: .findings,
            work: { Self.review(["unreview", entry.target]) },
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
