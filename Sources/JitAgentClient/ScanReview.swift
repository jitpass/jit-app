// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A finding the user checked and marked not live, as `jit scan review
/// --list --format json` lists it: where it was and what it was, never
/// the value.
public struct ScanReviewEntry: Codable, Sendable, Equatable, Identifiable {
    public var path: String
    public var line: Int?
    public var findingType: String
    public var label: String
    public var reviewedAt: Int64

    public var id: String {
        path + ":" + String(line ?? 0)
    }

    /// The argument `jit scan unreview` takes for this mark.
    public var target: String {
        line.map { path + ":" + String($0) } ?? path
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(reviewedAt))
    }

    enum CodingKeys: String, CodingKey {
        case path, line, label
        case findingType = "finding_type"
        case reviewedAt = "reviewed_at"
    }

    public init(path: String, line: Int?, findingType: String, label: String, reviewedAt: Int64) {
        self.path = path
        self.line = line
        self.findingType = findingType
        self.label = label
        self.reviewedAt = reviewedAt
    }
}

/// What `jit scan review|unreview --format json` answers.
public struct ScanReviewResult: Decodable, Sendable, Equatable {
    public var reviewed: [ScanReviewEntry]?
    public var unreviewed: [ScanReviewEntry]?
}

public enum ScanReview {
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

    /// Whether an engine that wrote this summary has `jit scan review`.
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
        // same record id, and marking one line leaves the other.
        let key = { (f: ScanFinding) in f.id + ":" + String(f.line ?? 0) }
        let marks = Set(marked.map(key))
        var copy = self
        copy.findings = findings.filter { !marks.contains(key($0)) }
        let removed = findings.count - copy.findings.count
        copy.summary.reviewed = (summary.reviewed ?? 0) + removed
        return copy
    }
}
