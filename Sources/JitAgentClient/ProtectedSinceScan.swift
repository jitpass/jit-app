// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What Protects, Redacts and review marks handled that a scan may not
/// have seen yet. A scan that
/// started after a Protect finished read the disk after it, so its word
/// on those rows stands and the entry is done. A scan that started before
/// may hold the rows the Protect just removed: they are taken out of what
/// it lands, and the entry waits for a later scan.
public struct ProtectedSinceScan: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var files: [String]
        public var tools: [String]
        public var redactedFiles: [String] = []
        public var redactedLines: [Int] = []
        public var reviewed: [ScanFinding] = []
        public var at: Date
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    public mutating func add(files: [String], tools: [String], at: Date) {
        guard !files.isEmpty || !tools.isEmpty else {
            return
        }
        entries.append(Entry(files: files, tools: tools, at: at))
    }

    /// A Redact's files, narrowed to `lines` when it was.
    public mutating func add(redacted files: [String], lines: [Int], at: Date) {
        guard !files.isEmpty else {
            return
        }
        entries.append(Entry(files: [], tools: [], redactedFiles: files, redactedLines: lines, at: at))
    }

    /// The rows a review mark took off the screen.
    public mutating func add(reviewed findings: [ScanFinding], at: Date) {
        guard !findings.isEmpty else {
            return
        }
        entries.append(Entry(files: [], tools: [], reviewed: findings, at: at))
    }

    /// A scan that started at `started` lands with `report`.
    public mutating func land(_ report: ScanReport, startedAt started: Date) -> ScanReport {
        entries.removeAll { $0.at < started }
        var out = report
        let files = entries.flatMap(\.files)
        let tools = entries.flatMap(\.tools)
        if !files.isEmpty || !tools.isEmpty {
            out = out.removingProtected(files: files, tools: tools)
        }
        for entry in entries where !entry.redactedFiles.isEmpty {
            out = out.removingCacheShapes(in: entry.redactedFiles, lines: entry.redactedLines)
        }
        let reviewed = entries.flatMap(\.reviewed)
        if !reviewed.isEmpty {
            out = out.removingReviewed(reviewed)
        }
        return out
    }
}
