// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The wire protocol of the jit agent socket, mirrored from
/// `internal/agent/protocol.go` in jitpass/jit. Only the ops and fields the
/// app uses are modelled; unknown fields are ignored on decode, and the app
/// never sends `wrap`/`unwrap`, so a plaintext or a data key can never
/// reach this process.
///
/// Every request carries `min_protocol` when its safety depends on
/// enforcement the agent must have; the app's ops are all read-mostly and
/// need none, matching the CLI's own convention.
public enum AgentOp: String, Codable, Sendable, CaseIterable {
    case status
    case lock
    case unlock
    case grantList = "grant_list"
    case grantRevoke = "grant_revoke"
    case history
}

public struct AgentRequest: Codable, Sendable {
    public var op: AgentOp
    public var minProtocol: Int?
    public var grantID: String?

    public init(op: AgentOp, minProtocol: Int? = nil, grantID: String? = nil) {
        self.op = op
        self.minProtocol = minProtocol
        self.grantID = grantID
    }

    enum CodingKeys: String, CodingKey {
        case op
        case minProtocol = "min_protocol"
        case grantID = "grant_id"
    }
}

/// One session transition or use, with the kernel-derived provenance the
/// agent learned when it happened. Every field but `unixTime` is best-effort.
public struct SessionEvent: Codable, Sendable, Equatable {
    public var unixTime: Int64
    public var kind: String
    public var op: String?
    public var by: String?
    public var launchedBy: String?
    public var cause: String?

    public init(unixTime: Int64, kind: String, op: String? = nil, by: String? = nil, launchedBy: String? = nil, cause: String? = nil) {
        self.unixTime = unixTime
        self.kind = kind
        self.op = op
        self.by = by
        self.launchedBy = launchedBy
        self.cause = cause
    }

    enum CodingKeys: String, CodingKey {
        case unixTime = "unix_time"
        case kind, op, by
        case launchedBy = "launched_by"
        case cause
    }

    public var date: Date { Date(timeIntervalSince1970: TimeInterval(unixTime)) }
}

public struct GrantStatus: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var pid: Int32
    public var name: String?
    public var anchor: String?
    public var profiles: [String]
    public var createdUnix: Int64
    public var expiresUnix: Int64
    public var serves: Int64?
    public var rootAlive: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, name, anchor, profiles
        case createdUnix = "created_unix"
        case expiresUnix = "expires_unix"
        case serves
        case rootAlive = "root_alive"
    }

    public var expires: Date { Date(timeIntervalSince1970: TimeInterval(expiresUnix)) }
}

public struct AgentResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var protocolVersion: Int?
    public var unlocked: Bool?
    public var expiresInSeconds: Int64?
    public var lastUnlock: SessionEvent?
    public var lastLock: SessionEvent?
    public var grants: [GrantStatus]?
    public var history: [SessionEvent]?

    public init(ok: Bool) { self.ok = ok }

    enum CodingKeys: String, CodingKey {
        case ok, error, unlocked
        case protocolVersion = "protocol"
        case expiresInSeconds = "expires_in_seconds"
        case lastUnlock = "last_unlock"
        case lastLock = "last_lock"
        case grants, history
    }
}
