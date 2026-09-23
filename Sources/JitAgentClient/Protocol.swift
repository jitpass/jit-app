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
    case grantCreate = "grant_create"
    case grantRevoke = "grant_revoke"
    case history
    /// The one streaming op (jitpass/jit#106): one `AgentResponse` line
    /// acknowledges, then one `SessionEvent` line per event until the peer
    /// hangs up. Never `wrap`, `unwrap` or `reveal_pid`; see the test.
    case subscribe
    /// Consent brokering (jitpass/jit#113): a `subscribe` with `broker` set
    /// is also streamed a `pending` event for each disclosed challenge before
    /// its Touch ID appears; `consent_list` returns the ones waiting, and
    /// `consent_answer` carries the human's answer. An allow only lets the
    /// agent go on to its own Touch ID; a deny refuses without one.
    case consentList = "consent_list"
    case consentAnswer = "consent_answer"
}

/// The two answers `consent_answer` accepts.
public enum ConsentDecision: String, Codable, Sendable {
    case allow
    case deny
}

public struct AgentRequest: Codable, Sendable {
    public var op: AgentOp
    public var minProtocol: Int?
    public var grantID: String?
    /// `grant_create`: the exact process to cover, the profile NAMES (the
    /// agent resolves them to secrets itself, so the prompt and the grant
    /// derive from the same facts), the project whose profiles to consult,
    /// and the requested lifetime, capped by the agent.
    public var targetPID: Int32?
    public var grantProfiles: [String]?
    public var projectRoot: String?
    public var ttlSeconds: Int64?
    /// Tree mode (jitpass/jit#110): `grantName` is the process name to
    /// cover under the session root at `targetPID`, and `anchorExplicit`
    /// says this app is not inside that tree and is naming it on purpose;
    /// the agent then accepts only a genuine session root and puts this
    /// app's name on the prompt.
    public var grantName: String?
    public var anchorExplicit: Bool?
    /// `grant_create` (jit 2.3): a folder per profile name instead of one
    /// `projectRoot` for all of them, which is what a sheet listing every
    /// profile on the Mac sends, and `standing` for a grant with no
    /// deadline (design/standing-grants.md): it holds its own key, survives
    /// restarts and reboots, and ends on revoke. Exclusive with
    /// `ttlSeconds`. An older agent ignores both and refuses the create
    /// for naming no profiles, which is the safe answer.
    public var grantProfileRoots: [GrantProfile]?
    public var standing: Bool?
    /// `subscribe`: this stream will answer consent requests. Ignored by an
    /// agent that predates brokering, whose stream then never carries one.
    public var broker: Bool?
    /// `consent_answer`: which pending request, and the answer.
    public var consentID: String?
    public var decision: ConsentDecision?

    public init(
        op: AgentOp, minProtocol: Int? = nil, grantID: String? = nil,
        targetPID: Int32? = nil, grantProfiles: [String]? = nil, projectRoot: String? = nil, ttlSeconds: Int64? = nil,
        grantName: String? = nil, anchorExplicit: Bool? = nil,
        grantProfileRoots: [GrantProfile]? = nil, standing: Bool? = nil,
        broker: Bool? = nil, consentID: String? = nil, decision: ConsentDecision? = nil
    ) {
        self.op = op
        self.minProtocol = minProtocol
        self.grantID = grantID
        self.targetPID = targetPID
        self.grantProfiles = grantProfiles
        self.projectRoot = projectRoot
        self.ttlSeconds = ttlSeconds
        self.grantName = grantName
        self.anchorExplicit = anchorExplicit
        self.grantProfileRoots = grantProfileRoots
        self.standing = standing
        self.broker = broker
        self.consentID = consentID
        self.decision = decision
    }

    enum CodingKeys: String, CodingKey {
        case op
        case minProtocol = "min_protocol"
        case grantID = "grant_id"
        case targetPID = "target_pid"
        case grantProfiles = "grant_profiles"
        case projectRoot = "project_root"
        case ttlSeconds = "ttl_seconds"
        case grantName = "grant_name"
        case anchorExplicit = "anchor_explicit"
        case grantProfileRoots = "grant_profile_roots"
        case standing
        case broker
        case consentID = "consent_id"
        case decision
    }
}

/// One session transition or use, with the kernel-derived provenance the
/// agent learned when it happened. Every field but `unixTime` is best-effort.
public struct SessionEvent: Codable, Sendable, Equatable {
    public var unixTime: Int64
    public var kind: String
    public var op: String?
    public var by: String?
    public var byPID: Int32?
    /// The identity on `by` came from a process scan, not the kernel; never
    /// render it as certainty.
    public var byLikely: Bool?
    public var launchedBy: String?
    public var cause: String?
    /// Secret names a use touched, and how many uses one event collapses.
    public var labels: [String]?
    public var count: Int?
    /// Links a brokered challenge's `pending` event to the `approved` or
    /// `denied` that answers it.
    public var consentID: String?
    /// On a serve: the reader was gone before anything was written, so it
    /// received nothing. The verdict in `op` is what it would have got.
    public var undelivered: Bool?

    public init(
        unixTime: Int64, kind: String, op: String? = nil, by: String? = nil, byPID: Int32? = nil, byLikely: Bool? = nil,
        launchedBy: String? = nil, cause: String? = nil, labels: [String]? = nil, count: Int? = nil, consentID: String? = nil,
        undelivered: Bool? = nil
    ) {
        self.unixTime = unixTime
        self.kind = kind
        self.op = op
        self.by = by
        self.byPID = byPID
        self.byLikely = byLikely
        self.launchedBy = launchedBy
        self.cause = cause
        self.labels = labels
        self.count = count
        self.consentID = consentID
        self.undelivered = undelivered
    }

    enum CodingKeys: String, CodingKey {
        case unixTime = "unix_time"
        case kind, op, by
        case byPID = "by_pid"
        case byLikely = "by_likely"
        case launchedBy = "launched_by"
        case cause, labels, count
        case consentID = "consent_id"
        case undelivered
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(unixTime))
    }
}

/// One profile a grant names and the folder it is read from: the project
/// directory whose `.jit/profiles` holds the manifest, or nil for the global
/// store. Names and folders only; the agent resolves them to secrets.
public struct GrantProfile: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var root: String?

    public init(name: String, root: String? = nil) {
        self.name = name
        self.root = root
    }
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
    /// The concrete vault paths the grant covers; nil from an agent that
    /// predates the field.
    public var secrets: [String]?
    public var lastServeUnix: Int64?
    /// Standing grants (design/standing-grants.md): no deadline, anchored
    /// to the app at `anchorPath` by executable rather than to a pid, and
    /// `rotated` lists the covered secrets that changed since the grant was
    /// made and are therefore no longer served. All nil from an older agent.
    public var standing: Bool?
    public var anchorPath: String?
    public var profileRoots: [GrantProfile]?
    public var rotated: [String]?

    public init(
        id: String, pid: Int32 = 0, name: String? = nil, anchor: String? = nil, profiles: [String] = [],
        createdUnix: Int64 = 0, expiresUnix: Int64 = 0, serves: Int64? = nil, rootAlive: Bool = true,
        secrets: [String]? = nil, lastServeUnix: Int64? = nil, standing: Bool? = nil, anchorPath: String? = nil,
        profileRoots: [GrantProfile]? = nil, rotated: [String]? = nil
    ) {
        self.id = id
        self.pid = pid
        self.name = name
        self.anchor = anchor
        self.profiles = profiles
        self.createdUnix = createdUnix
        self.expiresUnix = expiresUnix
        self.serves = serves
        self.rootAlive = rootAlive
        self.secrets = secrets
        self.lastServeUnix = lastServeUnix
        self.standing = standing
        self.anchorPath = anchorPath
        self.profileRoots = profileRoots
        self.rotated = rotated
    }

    enum CodingKeys: String, CodingKey {
        case id, pid, name, anchor, profiles, secrets, standing, rotated
        case createdUnix = "created_unix"
        case expiresUnix = "expires_unix"
        case serves
        case lastServeUnix = "last_serve_unix"
        case rootAlive = "root_alive"
        case anchorPath = "anchor_path"
        case profileRoots = "profile_roots"
    }

    public var expires: Date {
        Date(timeIntervalSince1970: TimeInterval(expiresUnix))
    }

    public var isStanding: Bool {
        standing ?? false
    }

    public var lastServe: Date? {
        lastServeUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// The secrets that no longer serve because they were rotated.
    public var rotatedSecrets: [String] {
        rotated ?? []
    }
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
    /// Answers `history`; the Go field is `Events`, so the key is `events`.
    public var events: [SessionEvent]?
    /// Set on `status` by an agent at or after jitpass/jit#105; nil before.
    public var ceilingInSeconds: Int64?
    public var ttlSeconds: Int64?
    public var consentEnabled: Bool?

    public init(ok: Bool) {
        self.ok = ok
    }

    enum CodingKeys: String, CodingKey {
        case ok, error, unlocked
        case protocolVersion = "protocol"
        case expiresInSeconds = "expires_in_seconds"
        case lastUnlock = "last_unlock"
        case lastLock = "last_lock"
        case grants, events
        case ceilingInSeconds = "ceiling_in_seconds"
        case ttlSeconds = "ttl_seconds"
        case consentEnabled = "consent_enabled"
    }
}
