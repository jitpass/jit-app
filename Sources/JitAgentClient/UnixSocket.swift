// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The POSIX plumbing under `AgentClient`, kept separate so the client reads
/// as protocol logic and the test fake reuses the same address and I/O
/// helpers instead of re-deriving them.
enum UnixSocket {
    /// Builds a `sockaddr_un` for `path`, or throws when the path exceeds
    /// the kernel's `sun_path` limit (104 bytes on Darwin).
    static func address(for path: String) throws -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path) - 1
        guard bytes.count <= capacity else {
            throw AgentClientError.io("socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    /// Runs `body` with the address cast to the generic `sockaddr` form that
    /// `connect` and `bind` take, so callers never repeat the rebound.
    static func withSockaddr<T>(_ addr: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    static func setTimeout(_ fd: Int32, _ timeout: TimeInterval) {
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        for option in [SO_RCVTIMEO, SO_SNDTIMEO] {
            _ = withUnsafePointer(to: &tv) {
                setsockopt(fd, SOL_SOCKET, option, $0, socklen_t(MemoryLayout<timeval>.size))
            }
        }
    }

    static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { buf in
            var sent = 0
            while sent < buf.count {
                let n = write(fd, buf.baseAddress! + sent, buf.count - sent)
                if n < 0 {
                    throw errnoError("write")
                }
                sent += n
            }
        }
    }

    /// Reads until EOF or until `isComplete` accepts what has arrived.
    static func read(_ fd: Int32, until isComplete: (Data) -> Bool) throws -> Data {
        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n < 0 {
                throw errnoError("read")
            }
            if n == 0 {
                return received
            }
            received.append(chunk, count: n)
            if isComplete(received) {
                return received
            }
        }
    }

    /// Reads newline-delimited documents until EOF or a read error, handing
    /// each complete line to `onLine`. A trailing partial line is dropped:
    /// the agent always ends a document with a newline, so a partial one is
    /// a connection cut mid-write.
    static func readLines(_ fd: Int32, onLine: (Data) -> Void) throws {
        var pending = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n < 0 {
                throw errnoError("read")
            }
            if n == 0 {
                return
            }
            pending.append(chunk, count: n)
            while let newline = pending.firstIndex(of: 0x0A) {
                onLine(pending[pending.startIndex ..< newline])
                pending.removeSubrange(pending.startIndex ... newline)
            }
        }
    }

    static func errnoError(_ call: String) -> AgentClientError {
        if errno == EAGAIN || errno == EWOULDBLOCK {
            return .timeout
        }
        return .io("\(call): \(String(cString: strerror(errno)))")
    }
}
