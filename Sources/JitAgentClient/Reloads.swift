// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A read that runs one at a time, with a reload asked while it runs kept
/// rather than dropped, as `ScanQueue` keeps a scan. The Audit window used
/// to drop it: a filter change during a load landed the old filter's
/// report under the new chips, and a stream event's reload was lost
/// (2026-09-27). Any number of asks while it runs become one more run.
public struct ReloadGate: Equatable, Sendable {
    public private(set) var running = false
    public private(set) var pending = false

    public init() {}

    /// True when the read should start now; false when one is running,
    /// and this ask waits for it to land.
    public mutating func ask() -> Bool {
        guard !running else {
            pending = true
            return false
        }
        running = true
        return true
    }

    /// The running read landed. True when an ask came in meanwhile: start
    /// the read again, now, and it is running.
    public mutating func landed() -> Bool {
        guard pending else {
            running = false
            return false
        }
        pending = false
        return true
    }
}

/// What to read again after an action wrote the vault (a Protect, a wrap
/// that stored a key, Doctor's migrate), so an open window does not keep
/// the listing from before it: Decoys said "no vault entry names this
/// file as its origin" over a file just protected, and Vault missed the
/// new secrets (2026-09-27).
public enum VaultRefresh: Equatable, Sendable {
    /// Nothing shows the listing; the next window to open reads it.
    case none
    /// The listing alone: the Vault window, or the panel's vault row.
    case listing
    /// The Decoys window's reload, which reads the listing with its
    /// mounts and serve events.
    case decoys

    public static func after(decoysOpen: Bool, vaultOpen: Bool, listed: Bool) -> VaultRefresh {
        if decoysOpen {
            return .decoys
        }
        return vaultOpen || listed ? .listing : .none
    }
}
