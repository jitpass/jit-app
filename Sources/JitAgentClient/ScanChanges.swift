// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

public extension ScanReport {
    /// The cached copies this scan found that the previous one did not,
    /// by file: what a notification can say is new. Everything when there
    /// is no previous scan to compare with.
    func newAgentCopies(since previous: ScanReport?) -> [ScanFinding] {
        let known = Set(previous?.agentCopies.map(\.filePath) ?? [])
        return agentCopies.filter { !known.contains($0.filePath) }
    }
}
