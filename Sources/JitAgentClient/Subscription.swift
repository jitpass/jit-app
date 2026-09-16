// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A handle on one `subscribe` stream. `cancel()` shuts the socket down,
/// which unblocks the reading thread; after it, `onEnd` is not called.
public final class Subscription: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var cancelled = false

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func attach(_ fd: Int32) {
        lock.withLock {
            self.fd = fd
            if cancelled {
                Self.shutdown(fd)
            }
        }
    }

    public func cancel() {
        lock.withLock {
            guard !cancelled else {
                return
            }
            cancelled = true
            if fd >= 0 {
                Self.shutdown(fd)
            }
        }
    }

    /// `shutdown` rather than `close`: closing a descriptor another thread is
    /// blocked reading on is undefined, while shutdown makes that read return
    /// zero and lets the thread close it itself.
    private static func shutdown(_ fd: Int32) {
        _ = Darwin.shutdown(fd, SHUT_RDWR)
    }
}
