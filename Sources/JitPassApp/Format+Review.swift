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
        + "Open one to check. If it's real, rotate it. If it's fake, mark it reviewed and it won't come back unless it changes."

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
            "They leave Findings. One comes back if what was found changes. "
                + "If any of these keys is live, rotate it instead: marking it reviewed doesn't make it safe."
        )
    }

    static let reviewRiskyQuestion = (
        title: "Mark this finding reviewed?",
        message: "This looks like a live key. Mark it reviewed only if you know it's not one. "
            + "It leaves Findings, and comes back if what was found changes."
    )

    static func unreviewedBanner(_ n: Int) -> String {
        (n == 1 ? "1 mark removed" : "\(n) marks removed") + " · the findings come back after this scan"
    }

    static func reviewedSheetTitle(_ n: Int) -> String {
        count(n, "reviewed finding")
    }

    static let reviewedSheetNote = "Hidden from Findings until what was found changes: the value on its line, "
        + "or anything in the file for a whole-file finding."

    /// After Unmark took the last one; the rescan on Done brings them back.
    static let reviewedSheetEmptyAfterUnmark = "Nothing is marked reviewed. The findings you unmarked come back after the rescan."
    static let reviewedSheetEmpty = "Nothing is marked reviewed."
    static let reviewedSheetEmptyTitle = "Reviewed findings"

    /// A mark's row fact, the date first so a long label gives way before
    /// it does: "Reviewed today · line 40 · GitHub Personal Access Token".
    static func reviewedFact(_ entry: ScanReviewEntry) -> String {
        var parts = ["Reviewed " + ScanWording.when(entry.date)]
        if let line = entry.line {
            parts.append("line \(line)")
        }
        parts.append(reviewedWhat(entry))
        return parts.joined(separator: " · ")
    }

    /// What was marked, in words: the token's vendor when scan named one,
    /// else the finding's kind ("Env file"), never the scanner's sentence.
    static func reviewedWhat(_ entry: ScanReviewEntry) -> String {
        let vendor = shortLabel(entry.label)
        if vendor != entry.label {
            return vendor
        }
        return reviewedKinds[entry.findingType] ?? ScanFinding.typeLabel(of: entry.findingType)
    }

    static let reviewedKinds = [
        "env_file_present": "Env file",
        "exposed_secret": "Real-looking key"
    ]

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
