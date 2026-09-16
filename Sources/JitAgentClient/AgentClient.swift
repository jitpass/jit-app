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
        let fd = try connect()
        defer { close(fd) }

        // Go's json.Encoder terminates each document with a newline; mirror it.
        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)
        try UnixSocket.writeAll(fd, payload)

        // The agent writes one JSON document and closes. Stop as soon as the
        // buffer parses, so a reply split across reads is handled and a slow
        // prompt surfaces as a timeout rather than a corrupt decode.
        let decoder = JSONDecoder()
        let received = try UnixSocket.read(fd) { (try? decoder.decode(AgentResponse.self, from: $0)) != nil }
        guard !received.isEmpty else {
            throw AgentClientError.io("empty reply")
        }
        let response = try decoder.decode(AgentResponse.self, from: received)
        guard response.ok else {
            throw AgentClientError.agent(response.error ?? "unknown error")
        }
        return response
    }

    private func connect() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixSocket.errnoError("socket")
        }
        UnixSocket.setTimeout(fd, timeout)
        var addr = try UnixSocket.address(for: socketPath)
        let rc = UnixSocket.withSockaddr(&addr) { Darwin.connect(fd, $0, $1) }
        guard rc == 0 else {
            close(fd)
            if errno == ENOENT || errno == ECONNREFUSED {
                throw AgentClientError.notRunning
            }
            throw UnixSocket.errnoError("connect")
        }
        return fd
    }
}

// MARK: - Typed calls, one per row the app renders

public extension AgentClient {
    func status() throws -> AgentResponse {
        try send(AgentRequest(op: .status))
    }

    func lock() throws -> AgentResponse {
        try send(AgentRequest(op: .lock))
    }

    func unlock() throws -> AgentResponse {
        try send(AgentRequest(op: .unlock))
    }

    func grants() throws -> [GrantStatus] {
        try send(AgentRequest(op: .grantList)).grants ?? []
    }

    func revokeGrant(id: String) throws {
        _ = try send(AgentRequest(op: .grantRevoke, grantID: id))
    }

    func history() throws -> [SessionEvent] {
        try send(AgentRequest(op: .history)).history ?? []
    }
}
