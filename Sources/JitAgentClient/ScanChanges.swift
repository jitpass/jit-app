// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

public extension ScanReport {
    /// The cached copies this scan found that the previous one did not,
    /// by file: what a notification can say is new. Everything when there
    /// is no previous scan to compare with.
    func newAgentCopies(since previous: ScanReport?) -> [ScanFinding] {
        newAgentCopies(known: Set(previous?.agentCopyPaths ?? []))
    }

    /// The same, against the files a scan found before, as saved between
    /// launches: paths only, never a value.
    func newAgentCopies(known: Set<String>) -> [ScanFinding] {
        agentCopies.filter { !known.contains($0.filePath) }
    }

    /// The files holding cached copies: what is saved to compare with.
    var agentCopyPaths: [String] {
        Array(Set(agentCopies.map(\.filePath))).sorted()
    }
}
