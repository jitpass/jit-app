// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What the audit says about one wrapped tool's key: how often it was
/// read, when last, and by which programs — the two facts no listing
/// has. "Last read by gh" proves the shim is on the path the tool takes;
/// "read by python3" is the decoy question, per tool.
public struct ToolActivity: Equatable, Sendable {
    public var reads = 0
    public var lastRead: Date?
    /// Programs that read the key, first seen first; "jit" itself is not
    /// a reader.
    public var readers: [String] = []

    public init(reads: Int = 0, lastRead: Date? = nil, readers: [String] = []) {
        self.reads = reads
        self.lastRead = lastRead
        self.readers = readers
    }

    /// Readers other than the tool the key belongs to.
    public func others(than tool: String) -> [String] {
        readers.filter { $0 != tool }
    }
}

public extension AuditReport {
    /// The reads of the secrets at `vaultPaths` ("wrap-gh/GH_TOKEN"): every
    /// use event naming one of them.
    func toolActivity(vaultPaths: [String]) -> ToolActivity {
        var activity = ToolActivity()
        guard !vaultPaths.isEmpty else {
            return activity
        }
        let wanted = Set(vaultPaths)
        for event in authEvents where event.kind == "use" {
            let hits = (event.labels ?? []).filter { wanted.contains($0) }.count
            guard hits > 0 else {
                continue
            }
            activity.reads += hits
            if activity.lastRead.map({ event.date > $0 }) ?? true {
                activity.lastRead = event.date
            }
            let reader = Self.program(event.launchedBy) ?? Self.program(event.by)
            if let reader, reader != "jit", !activity.readers.contains(reader) {
                activity.readers.append(reader)
            }
        }
        return activity
    }
}
