// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The last whole-Mac scan, as the app keeps it between launches: the
/// report the Findings window and the panel show, who ran it and when,
/// and when the last deep run was (its vault copies carry). Without this
/// every relaunch opened on "not scanned" until the schedule came round,
/// and the AI Agents, Tools and Decoys windows had nothing to read.
///
/// What the record holds is what the report holds: paths, key names, the
/// scanner's evidence sentences. Never a value — the app does not decode
/// `value_preview`, so it cannot write one.
public struct LastScan: Codable, Equatable, Sendable {
    public var report: ScanReport
    public var at: Date
    public var kind: ScanRunKind
    public var deepAt: Date?

    public init(report: ScanReport, at: Date, kind: ScanRunKind, deepAt: Date?) {
        self.report = report
        self.at = at
        self.kind = kind
        self.deepAt = deepAt
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .withoutEscapingSlashes // paths and vault paths, readable as written
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> LastScan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(LastScan.self, from: data)
    }
}

extension ScanRunKind: Codable {}
