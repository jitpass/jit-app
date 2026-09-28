// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What Protects handled that a scan may not have seen yet. A scan that
/// started after a Protect finished read the disk after it, so its word
/// on those rows stands and the entry is done. A scan that started before
/// may hold the rows the Protect just removed: they are taken out of what
/// it lands, and the entry waits for a later scan.
public struct ProtectedSinceScan: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var files: [String]
        public var tools: [String]
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

    /// A scan that started at `started` lands with `report`.
    public mutating func land(_ report: ScanReport, startedAt started: Date) -> ScanReport {
        entries.removeAll { $0.at < started }
        let files = entries.flatMap(\.files)
        let tools = entries.flatMap(\.tools)
        return files.isEmpty && tools.isEmpty ? report : report.removingProtected(files: files, tools: tools)
    }
}
