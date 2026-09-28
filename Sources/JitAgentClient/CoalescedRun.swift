// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// One run of a slow read at a time, and at most one more after it: asks
/// that land while it runs fold into a single rerun, which starts when it
/// ends. So results land in the order they were started, and a burst of
/// asks costs two runs, not one each.
public struct CoalescedRun: Sendable, Equatable {
    public private(set) var running = false
    public private(set) var rerun = false

    public init() {}

    /// Whether to start a run now; false means one is running and the ask
    /// is kept for after it.
    public mutating func ask() -> Bool {
        if running {
            rerun = true
            return false
        }
        running = true
        return true
    }

    /// The run ended: whether an ask was kept, to be made again now.
    public mutating func finished() -> Bool {
        running = false
        defer { rerun = false }
        return rerun
    }
}
