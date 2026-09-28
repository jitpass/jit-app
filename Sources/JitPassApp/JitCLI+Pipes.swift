// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

extension JitCLI {
    /// Starts reading `pipe` to its end on another thread; the returned call
    /// waits for it. A pipe holds 64 KB, so reading stdout to its end before
    /// touching stderr leaves jit blocked on a full stderr and the app
    /// blocked on stdout, forever.
    static func collect(_ pipe: Pipe) -> () -> Data {
        let handle = pipe.fileHandleForReading
        let box = Collected()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.data = handle.readDataToEndOfFile()
            done.signal()
        }
        return {
            done.wait()
            return box.data
        }
    }
}

/// Written once on the reading thread before the semaphore signals, read
/// once after the wait.
private final class Collected: @unchecked Sendable {
    var data = Data()
}
