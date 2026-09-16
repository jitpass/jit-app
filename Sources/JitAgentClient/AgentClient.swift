// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

public enum AgentClientError: Error, Equatable {
    /// Nothing is listening on the socket: the service is not running.
    case notRunning
    /// The agent answered `ok: false` with this message.
    case agent(String)
    /// The connection timed out. The agent is most likely blocked on a
    /// Touch ID prompt that this process cannot see.
    case timeout
    case io(String)
}

/// A one-request-per-connection client for the jit agent socket, the same
/// shape as `agent.Client` in Go: dial, send one JSON request, read one JSON
/// response, close. Pure Foundation and POSIX so it is testable against a
/// fake server on a temporary socket path.
public struct AgentClient: Sendable {
    public let socketPath: String
    public let timeout: TimeInterval

    /// The default socket lives beside the vault, mirroring
    /// `agent.SocketPath(vaultRootDir())` in the CLI.
    public static func defaultSocketPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        home.appendingPathComponent("Library/Application Support/jitpass/agent.sock").path
    }

    public init(socketPath: String = AgentClient.defaultSocketPath(), timeout: TimeInterval = 5) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    public func send(_ request: AgentRequest) throws -> AgentResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentClientError.io("socket: \(errnoString())") }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        _ = withUnsafePointer(to: &tv) {
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        _ = withUnsafePointer(to: &tv) {
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path) - 1
        guard pathBytes.count <= capacity else { throw AgentClientError.io("socket path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            if errno == ENOENT || errno == ECONNREFUSED { throw AgentClientError.notRunning }
            throw AgentClientError.io("connect: \(errnoString())")
        }

        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A) // Go's json.Encoder terminates with a newline; mirror it.
        try payload.withUnsafeBytes { buf in
            var sent = 0
            while sent < buf.count {
                let n = write(fd, buf.baseAddress! + sent, buf.count - sent)
                if n < 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { throw AgentClientError.timeout }
                    throw AgentClientError.io("write: \(errnoString())")
                }
                sent += n
            }
        }

        // The agent writes one JSON document and closes. Accumulate until it
        // parses, so a reply split across reads is handled and a slow prompt
        // surfaces as a timeout rather than a corrupt decode.
        var received = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { throw AgentClientError.timeout }
                throw AgentClientError.io("read: \(errnoString())")
            }
            if n == 0 { break }
            received.append(chunk, count: n)
            if let response = try? JSONDecoder().decode(AgentResponse.self, from: received) {
                return try Self.check(response)
            }
        }
        guard !received.isEmpty else { throw AgentClientError.io("empty reply") }
        return try Self.check(JSONDecoder().decode(AgentResponse.self, from: received))
    }

    static func check(_ response: AgentResponse) throws -> AgentResponse {
        guard response.ok else { throw AgentClientError.agent(response.error ?? "unknown error") }
        return response
    }

    private func errnoString() -> String { String(cString: strerror(errno)) }
}

// MARK: - Typed convenience calls, one per row the app renders.

public extension AgentClient {
    func status() throws -> AgentResponse { try send(AgentRequest(op: .status)) }
    func lock() throws -> AgentResponse { try send(AgentRequest(op: .lock)) }
    func unlock() throws -> AgentResponse { try send(AgentRequest(op: .unlock)) }
    func grants() throws -> [GrantStatus] { try send(AgentRequest(op: .grantList)).grants ?? [] }
    func revokeGrant(id: String) throws { _ = try send(AgentRequest(op: .grantRevoke, grantID: id)) }
    func history() throws -> [SessionEvent] { try send(AgentRequest(op: .history)).history ?? [] }
}
