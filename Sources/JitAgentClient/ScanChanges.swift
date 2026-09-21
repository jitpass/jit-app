// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

public extension ScanReport {
    /// The findings this scan has that a previous whole-Mac scan did not,
    /// by record id. Scaffolding is left out: a test fixture is counted by
    /// the scanner but is not news. What the Findings header counts and
    /// the "new" mark on a row means.
    func newFindings(known: Set<String>) -> [ScanFinding] {
        findings.filter { !$0.scaffolding && !known.contains($0.id) }
    }

    /// The ids to remember for the next comparison. Ids only, never a
    /// value or a path.
    var countedIDs: [String] {
        findings.filter { !$0.scaffolding }.map(\.id).sorted()
    }
}
