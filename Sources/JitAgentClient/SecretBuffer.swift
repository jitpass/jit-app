// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A decrypted value in memory the app owns and can wipe. A Swift `String`
/// cannot be scrubbed (its storage is a heap block with no handle, and every
/// framework it touches may copy it), so the value lives here as raw bytes
/// and becomes a `String` only for the moment it is on screen. `wipe()` uses
/// `memset_s`, which the optimiser may not remove as a dead store, and runs
/// again on deinit so a dropped buffer never keeps its bytes.
///
/// This is the honest half of "never kept": the bytes the app allocates are
/// zeroed. The `String` made for display, and whatever the text system
/// copies to lay it out, are released but not zeroed; the hardened runtime
/// and the process boundary are what protect those.
public final class SecretBuffer: @unchecked Sendable {
    private let bytes: UnsafeMutableRawBufferPointer
    private let length: Int
    private var wiped = false

    /// Copies `data` in and zeroes `data`'s own storage, so the caller's
    /// copy is gone as soon as this one exists.
    public init(consuming data: inout Data) {
        length = data.count
        bytes = .allocate(byteCount: max(data.count, 1), alignment: 1)
        bytes.initializeMemory(as: UInt8.self, repeating: 0)
        data.copyBytes(to: bytes)
        data.resetBytes(in: 0 ..< data.count)
    }

    deinit {
        wipe()
        bytes.deallocate()
    }

    public var count: Int {
        wiped ? 0 : length
    }

    public var isEmpty: Bool {
        wiped || length == 0
    }

    /// The value as text, for display. Each call makes a new `String`; the
    /// caller drops it when the display ends. Empty once wiped.
    public var text: String {
        guard !wiped else {
            return ""
        }
        return String(bytes: UnsafeRawBufferPointer(bytes).prefix(length), encoding: .utf8) ?? ""
    }

    /// Overwrites every byte with zero. Safe to call more than once.
    public func wipe() {
        guard !wiped else {
            return
        }
        wiped = true
        _ = memset_s(bytes.baseAddress, bytes.count, 0, bytes.count)
    }

    /// True once the bytes have been overwritten.
    public var isWiped: Bool {
        wiped
    }

    /// For tests: whether the underlying storage reads as all zeros.
    public var storageIsZero: Bool {
        bytes.allSatisfy { $0 == 0 }
    }
}
