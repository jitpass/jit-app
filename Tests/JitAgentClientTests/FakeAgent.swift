// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
@testable import JitAgentClient

/// A single-shot Unix socket server with the agent's framing: accept, read
/// one newline-terminated JSON request, write one JSON reply, close. Built
/// on the same `UnixSocket` helpers as the client so the two cannot drift.
final class FakeAgent {
    typealias Handler = (AgentRequest) -> String

    private let listenFD: Int32
    private let thread: Thread

    init(path: String, handler: @escaping Handler) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = try UnixSocket.address(for: path)
        let bound = UnixSocket.withSockaddr(&addr) { bind(fd, $0, $1) }
        guard bound == 0, listen(fd, 1) == 0 else {
            throw AgentClientError.io("bind/listen failed")
        }
        listenFD = fd
        thread = Thread {
            while true {
                let conn = accept(fd, nil, nil)
                if conn < 0 {
                    return
                }
                Self.serve(conn, handler)
                close(conn)
            }
        }
        thread.start()
    }

    func stop() {
        close(listenFD)
    }

    private static func serve(_ conn: Int32, _ handler: Handler) {
        let request = try? UnixSocket.read(conn) { $0.last == 0x0A }
        let reply = request
            .flatMap { try? JSONDecoder().decode(AgentRequest.self, from: $0) }
            .map(handler) ?? #"{"ok":false,"error":"bad request"}"#
        try? UnixSocket.writeAll(conn, Data(reply.utf8))
    }
}
