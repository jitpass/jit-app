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

    /// How long a call that puts a Touch ID prompt on screen may wait: the
    /// agent's own challenge ceiling is about two minutes.
    public static let promptTimeout: TimeInterval = 150

    public func send(_ request: AgentRequest) throws -> AgentResponse {
        try send(request, timeout: timeout)
    }

    public func send(_ request: AgentRequest, timeout: TimeInterval?) throws -> AgentResponse {
        let fd = try connect(timeout: timeout)
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

    /// Opens a `subscribe` stream. `onEvent` is called on a private thread
    /// for every event the agent records, in order; `onEnd` once, when the
    /// stream stops for any reason other than `cancel()`, with the error if
    /// there was one. The caller decides whether to reconnect, after
    /// re-syncing from `history()`, since anything recorded in the gap is
    /// only there. No timeout is applied to the stream itself: silence is
    /// the normal state of an idle session.
    public func subscribe(
        onEvent: @escaping @Sendable (SessionEvent) -> Void,
        onEnd: @escaping @Sendable (Error?) -> Void
    ) -> Subscription {
        let subscription = Subscription()
        let thread = Thread { [self] in
            do {
                let fd = try connect(timeout: nil)
                defer { close(fd) }
                subscription.attach(fd)
                var payload = try JSONEncoder().encode(AgentRequest(op: .subscribe))
                payload.append(0x0A)
                try UnixSocket.writeAll(fd, payload)
                let decoder = JSONDecoder()
                var acknowledged = false
                var refusal: AgentClientError?
                try UnixSocket.readLines(fd) { line in
                    if refusal != nil {
                        return
                    }
                    if !acknowledged {
                        acknowledged = true
                        if let ack = try? decoder.decode(AgentResponse.self, from: line), !ack.ok {
                            refusal = .agent(ack.error ?? "subscribe refused")
                        }
                        return
                    }
                    if let event = try? decoder.decode(SessionEvent.self, from: line) {
                        onEvent(event)
                    }
                }
                if let refusal {
                    throw refusal
                }
                if !subscription.isCancelled {
                    onEnd(nil)
                }
            } catch {
                if !subscription.isCancelled {
                    onEnd(error)
                }
            }
        }
        thread.name = "jitpass.subscribe"
        thread.start()
        return subscription
    }

    private func connect() throws -> Int32 {
        try connect(timeout: timeout)
    }

    private func connect(timeout: TimeInterval?) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixSocket.errnoError("socket")
        }
        if let timeout {
            UnixSocket.setTimeout(fd, timeout)
        }
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
        try send(AgentRequest(op: .history)).events ?? []
    }

    /// Creates an exact-process grant. The agent puts a disclosed Touch ID
    /// on screen naming the process and the profiles, so this blocks until
    /// the human answers; callers run it off the main thread.
    func createGrant(pid: Int32, profiles: [String], projectRoot: String?, ttl: TimeInterval) throws -> GrantStatus {
        let request = AgentRequest(
            op: .grantCreate, targetPID: pid, grantProfiles: profiles, projectRoot: projectRoot, ttlSeconds: Int64(ttl)
        )
        guard let grant = try send(request, timeout: Self.promptTimeout).grants?.first else {
            throw AgentClientError.agent("grant created but not reported back")
        }
        return grant
    }
}
