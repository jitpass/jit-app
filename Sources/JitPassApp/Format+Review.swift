// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
import JitAgentClient

/// Findings' review marks: the words for marking a finding checked and not
/// live, and for the list of the ones marked.
extension Format {
    /// The Test fixtures card's note once the engine can mark: what the tab
    /// is for, and what to do with a row.
    static let fixturesNoteWithReview = "Keys in tests and docs are usually fake, so they don't count toward the score. "
        + "Open one to check. If it's real, rotate it. If it's fake, mark it reviewed and it won't come back unless the value changes."

    /// "6 findings in 4 files", "1 finding".
    static func reviewedCount(_ findings: [ScanFinding]) -> String {
        let files = Set(findings.map(\.filePath)).count
        let what = count(findings.count, "finding")
        return files > 1 ? what + " in " + count(files, "file") : what
    }

    static func reviewedBanner(_ findings: [ScanFinding]) -> String {
        reviewedCount(findings) + " marked reviewed"
    }

    static func reviewAllQuestion(_ findings: [ScanFinding]) -> (title: String, message: String) {
        (
            "Mark \(reviewedCount(findings)) reviewed?",
            "They leave Findings. One comes back if the value on its line changes. "
                + "If any of these keys is live, rotate it instead: marking it reviewed doesn't make it safe."
        )
    }

    static let reviewRiskyQuestion = (
        title: "Mark this finding reviewed?",
        message: "This looks like a live key. Mark it reviewed only if you know it's not one. "
            + "It leaves Findings, and comes back if the value on its line changes."
    )

    static func unreviewedBanner(_ n: Int) -> String {
        (n == 1 ? "1 mark removed" : "\(n) marks removed") + "; rescanning"
    }

    static func reviewedSheetTitle(_ n: Int) -> String {
        count(n, "reviewed finding")
    }

    static let reviewedSheetNote = "Hidden from Findings until the value on the line changes."

    /// A mark's row: the file, its line, and what was found when.
    static func reviewedFact(_ entry: ScanReviewEntry) -> String {
        shortLabel(entry.label) + " · reviewed " + ScanWording.when(entry.date)
    }

    /// "value matches GitHub Personal Access Token's known token format" as
    /// "GitHub Personal Access Token".
    static func shortLabel(_ label: String) -> String {
        let prefix = "value matches "
        let suffix = "'s known token format"
        guard label.hasPrefix(prefix), label.hasSuffix(suffix) else {
            return label
        }
        return String(label.dropFirst(prefix.count).dropLast(suffix.count))
    }
}
