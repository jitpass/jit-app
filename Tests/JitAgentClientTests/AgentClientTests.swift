// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import XCTest
@testable import JitAgentClient

/// Drives the real client against a fake agent on a temporary socket, so the
/// framing (one JSON in, one JSON out, close) is tested end to end without
/// jit installed.
final class AgentClientTests: XCTestCase {
    private var path = ""

    override func setUp() {
        path = NSTemporaryDirectory() + "jitpass-test-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDown() { unlink(path) }

    func testNotRunningWhenNothingListens() {
        XCTAssertThrowsError(try AgentClient(socketPath: path, timeout: 1).status()) { error in
            XCTAssertEqual(error as? AgentClientError, .notRunning)
        }
    }

    func testStatusRoundTrip() throws {
        let server = try FakeAgent(path: path) { request in
            XCTAssertEqual(request.op, .status)
            return #"{"ok":true,"protocol":1,"unlocked":true,"expires_in_seconds":30}"#
        }
        defer { server.stop() }
        let r = try AgentClient(socketPath: path, timeout: 2).status()
        XCTAssertEqual(r.unlocked, true)
        XCTAssertEqual(r.expiresInSeconds, 30)
    }

    func testAgentErrorSurfaces() throws {
        let server = try FakeAgent(path: path) { _ in #"{"ok":false,"error":"no such grant"}"# }
        defer { server.stop() }
        XCTAssertThrowsError(try AgentClient(socketPath: path, timeout: 2).revokeGrant(id: "g-x")) { error in
            XCTAssertEqual(error as? AgentClientError, .agent("no such grant"))
        }
    }
}

/// Minimal single-shot Unix socket server: accept, read one line, reply, close.
final class FakeAgent {
    private let fd: Int32
    private let thread: Thread

    init(path: String, handler: @escaping (AgentRequest) -> String) throws {
        let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        fd = listenFD
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listenFD, 1) == 0 else { throw AgentClientError.io("bind/listen failed") }
        thread = Thread {
            while true {
                let conn = accept(listenFD, nil, nil)
                if conn < 0 { return }
                var buf = [UInt8](repeating: 0, count: 4096)
                var data = Data()
                while true {
                    let n = read(conn, &buf, buf.count)
                    if n <= 0 { break }
                    data.append(buf, count: n)
                    if data.last == 0x0A { break }
                }
                let reply: String
                if let req = try? JSONDecoder().decode(AgentRequest.self, from: data) {
                    reply = handler(req)
                } else {
                    reply = #"{"ok":false,"error":"bad request"}"#
                }
                _ = reply.withCString { write(conn, $0, strlen($0)) }
                close(conn)
            }
        }
        thread.start()
    }

    func stop() { close(fd) }
}
