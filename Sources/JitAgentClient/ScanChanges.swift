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

    /// A row list with the rows holding something new first, in their own
    /// order, then the rest in theirs. News is what a reader opens the
    /// window for, so it is never buried under rows they saw last time.
    /// `new` nil (no earlier scan to compare with) leaves the order alone.
    static func newFirst<Row>(_ rows: [Row], new: Set<String>?, findings: (Row) -> [ScanFinding]) -> [Row] {
        guard let new, !new.isEmpty else {
            return rows
        }
        let fresh = rows.filter { findings($0).contains { new.contains($0.id) } }
        let rest = rows.filter { !findings($0).contains { new.contains($0.id) } }
        return fresh + rest
    }

    /// `groups(in:)`, news first.
    func groups(in tier: ScanTier, new: Set<String>?) -> [ScanFileGroup] {
        Self.newFirst(groups(in: tier), new: new, findings: \.findings)
    }

    func agentCacheGroups(new: Set<String>?) -> [ScanAgentGroup] {
        Self.newFirst(agentCacheGroups, new: new, findings: \.findings)
    }

    func cacheShapeGroups(new: Set<String>?) -> [ScanFileGroup] {
        Self.newFirst(cacheShapeGroups, new: new, findings: \.findings)
    }

    /// The ids to remember for the next comparison. Ids only, never a
    /// value or a path.
    var countedIDs: [String] {
        findings.filter { !$0.scaffolding }.map(\.id).sorted()
    }

    /// A regular run's report, with the vault copies a previous report holds
    /// carried onto it. A regular scan does not read the vault, so it finds
    /// none of them; without this every rescan — a Protect's, the
    /// schedule's — read as if the copies were gone. They stay until the
    /// user handles them, with one check the app can make without the
    /// vault: `unchanged` says the row's file is as the deep scan saw it,
    /// still there and not written since. A Redact, a Clean Caches or a
    /// migrate that touched the file takes its rows with it; a deep scan
    /// replaces them all. A deep report carries nothing: it searched.
    func carryingVaultCopies(from previous: ScanReport, unchanged: (String) -> Bool) -> ScanReport {
        guard summary.deep != true else {
            return self
        }
        let found = Set(findings.map(\.id))
        let carried = previous.vaultCopies.filter { !found.contains($0.id) && unchanged($0.filePath) }
        guard !carried.isEmpty else {
            return self
        }
        var copy = self
        copy.findings += carried
        copy.summary.totalFindings += carried.count
        return copy
    }
}
