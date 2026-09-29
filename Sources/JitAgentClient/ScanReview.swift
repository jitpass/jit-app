// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A finding the user checked and marked not live, as `jit review --list
/// --format json` lists it: the mark's own id, where it was and what it
/// was, never the value.
public struct ScanReviewEntry: Codable, Sendable, Equatable, Identifiable {
    /// The mark's id, as jit keeps it (an HMAC, unique per mark): what
    /// `jit unreview --id` takes. Absent from an engine that did not
    /// print one, and then the row falls back to where it was.
    public var markID: String?
    public var path: String
    public var line: Int?
    public var findingType: String
    public var label: String
    public var reviewedAt: Int64

    public var id: String {
        markID ?? path + ":" + String(line ?? 0) + ":" + findingType + ":" + label
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(reviewedAt))
    }

    enum CodingKeys: String, CodingKey {
        case path, line, label
        case markID = "id"
        case findingType = "finding_type"
        case reviewedAt = "reviewed_at"
    }

    public init(markID: String? = nil, path: String, line: Int?, findingType: String, label: String, reviewedAt: Int64) {
        self.markID = markID
        self.path = path
        self.line = line
        self.findingType = findingType
        self.label = label
        self.reviewedAt = reviewedAt
    }
}

/// What `jit review|unreview --format json` answers. `skipped` counts the
/// findings on the named lines that could not be marked (a copy of a
/// secret jit holds, one Protect can fix). `missed` is each `FILE[:LINE]`
/// the rescan found nothing on: it changed since the scan listed it.
public struct ScanReviewResult: Decodable, Sendable, Equatable {
    public var reviewed: [ScanReviewEntry]?
    public var unreviewed: [ScanReviewEntry]?
    public var skipped: Int?
    public var missed: [String]?
}

public enum ScanReview {
    /// The findings a review run marked: those whose file and line jit
    /// names in its answer. jit echoes the path it was given.
    public static func marked(_ findings: [ScanFinding], by result: ScanReviewResult) -> [ScanFinding] {
        let key = { (path: String, line: Int?) in path + ":" + String(line ?? 0) }
        let done = Set((result.reviewed ?? []).map { key($0.path, $0.line) })
        return findings.filter { done.contains(key($0.filePath, $0.line)) }
    }

    /// The `FILE[:LINE]` arguments that mark exactly these findings: one per
    /// line, and the bare file once for a finding with no line.
    public static func targets(_ findings: [ScanFinding]) -> [String] {
        var out: [String] = []
        for f in findings {
            let target = f.line.map { f.filePath + ":" + String($0) } ?? f.filePath
            if !out.contains(target) {
                out.append(target)
            }
        }
        return out
    }

    /// `jit review` for exactly these findings: `--only` with each one's
    /// record id, so a file or line holding others marks none of them,
    /// then the files and lines to rescan.
    public static func arguments(for findings: [ScanFinding]) -> [String] {
        var ids: [String] = []
        for f in findings where !ids.contains(f.id) {
            ids.append(f.id)
        }
        return ["review"] + ids.flatMap { ["--only", $0] } + targets(findings) + ["--format", "json"]
    }

    /// `jit unreview` for exactly these marks, by their ids.
    public static func unreviewArguments(_ markIDs: [String]) -> [String] {
        ["unreview"] + markIDs.flatMap { ["--id", $0] } + ["--format", "json"]
    }

    public static let listArguments = ["review", "--list", "--format", "json"]

    /// Whether an engine that wrote this summary has `jit review`.
    public static func supported(_ summary: ScanSummary) -> Bool {
        guard let version = summary.schemaVersion else {
            return false
        }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        return parts.lexicographicallyPrecedes([0, 25, 0]) == false
    }
}

public extension ScanFinding {
    /// A mark is for a real-looking value the user checked: a test fixture
    /// or a finding only they can fix. Never a copy of a secret jit already
    /// holds (Redact or rotate), and never one Protect can move.
    var reviewable: Bool {
        !isVaultCopy && !isAgentCopy && !isCacheShape && !migratable
    }
}

public extension ScanReport {
    /// The report without the findings just marked reviewed, counted in the
    /// summary as the next scan will count them.
    func removingReviewed(_ marked: [ScanFinding]) -> ScanReport {
        // Id and line: jit gives two exports of one key in one file the
        // same record id, so the report on screen drops only the rows the
        // user picked. The mark itself matches the value in the file, so
        // the next scan also hides another line holding the same value.
        let key = { (f: ScanFinding) in f.id + ":" + String(f.line ?? 0) }
        let marks = Set(marked.map(key))
        var copy = self
        copy.findings = findings.filter { !marks.contains(key($0)) }
        let removed = findings.count - copy.findings.count
        copy.summary.reviewed = (summary.reviewed ?? 0) + removed
        return copy
    }
}
