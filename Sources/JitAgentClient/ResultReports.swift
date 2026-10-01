// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

// The JSON documents jit 2.3.8 writes for the commands whose text the app
// used to show in a window (`--format json`; jit's cli/wrapreport.go,
// undo.go, servicelog.go). Paths, names and vault paths, never a value.
// Fields new to an engine are optional on decode.

/// `jit wrap <tool> --format json` and `jit wrap add --format json`.
public struct WrapReport: Codable, Sendable, Equatable {
    public typealias Key = WrapReportKey
    public typealias Inject = WrapReportInject

    public var tool: String
    /// "shim", "native", "grant", "capture" or "rungrant".
    public var kind: String
    public var wrapped: Bool
    public var key: Key?
    public var shim: String?
    public var profile: String?
    public var grant: String?
    public var grantMigrated: Bool?
    public var vaulted: [String]
    public var injects: [Inject]?
    public var pathAddedTo: String?
    /// A native tool's migration, as `jit migrate <file> --format json`.
    public var migrate: MigrateReport?
    public var errors: [String]
    public var report: String

    enum CodingKeys: String, CodingKey {
        case tool, kind, wrapped, key, shim, profile, grant, vaulted, injects, migrate, errors, report
        case grantMigrated = "grant_migrated", pathAddedTo = "path_added_to"
    }

    public init(
        tool: String, kind: String, wrapped: Bool, key: Key? = nil, shim: String? = nil, profile: String? = nil,
        grant: String? = nil, grantMigrated: Bool? = nil, vaulted: [String] = [], injects: [Inject]? = nil,
        pathAddedTo: String? = nil, migrate: MigrateReport? = nil, errors: [String] = [], report: String = ""
    ) {
        self.tool = tool
        self.kind = kind
        self.wrapped = wrapped
        self.key = key
        self.shim = shim
        self.profile = profile
        self.grant = grant
        self.grantMigrated = grantMigrated
        self.vaulted = vaulted
        self.injects = injects
        self.pathAddedTo = pathAddedTo
        self.migrate = migrate
        self.errors = errors
        self.report = report
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        tool = try box.decode(String.self, forKey: .tool)
        kind = try box.decodeIfPresent(String.self, forKey: .kind) ?? ""
        wrapped = try box.decodeIfPresent(Bool.self, forKey: .wrapped) ?? false
        key = try box.decodeIfPresent(Key.self, forKey: .key)
        shim = try box.decodeIfPresent(String.self, forKey: .shim)
        profile = try box.decodeIfPresent(String.self, forKey: .profile)
        grant = try box.decodeIfPresent(String.self, forKey: .grant)
        grantMigrated = try box.decodeIfPresent(Bool.self, forKey: .grantMigrated)
        vaulted = try box.decodeIfPresent([String].self, forKey: .vaulted) ?? []
        injects = try box.decodeIfPresent([Inject].self, forKey: .injects)
        pathAddedTo = try box.decodeIfPresent(String.self, forKey: .pathAddedTo)
        migrate = try box.decodeIfPresent(MigrateReport.self, forKey: .migrate)
        errors = try box.decodeIfPresent([String].self, forKey: .errors) ?? []
        report = try box.decodeIfPresent(String.self, forKey: .report) ?? ""
    }

    public static func parse(_ data: Data) throws -> WrapReport {
        try JSONDecoder().decode(WrapReport.self, from: data)
    }
}

/// A shim tool's key. `from` is "file", "keyring", "vault" or "none".
public struct WrapReportKey: Codable, Sendable, Equatable {
    public var name: String
    public var vaultPath: String
    public var from: String
    public var source: String?
    public var scrubbed: Bool

    enum CodingKeys: String, CodingKey {
        case name = "var", vaultPath = "vault_path", from, source, scrubbed
    }

    public init(name: String, vaultPath: String, from: String, source: String? = nil, scrubbed: Bool = false) {
        self.name = name
        self.vaultPath = vaultPath
        self.from = from
        self.source = source
        self.scrubbed = scrubbed
    }
}

public struct WrapReportInject: Codable, Sendable, Equatable {
    public var name: String
    public var vaultPath: String?
    public var stored: Bool

    enum CodingKeys: String, CodingKey {
        case name = "var", vaultPath = "vault_path", stored
    }

    public init(name: String, vaultPath: String?, stored: Bool) {
        self.name = name
        self.vaultPath = vaultPath
        self.stored = stored
    }
}

/// `jit migrate undo --format json`: with --dry-run the plan, else what
/// each restore did.
public struct UndoReport: Codable, Sendable, Equatable {
    public typealias File = UndoReportFile

    public var dryRun: Bool
    public var files: [File]
    public var errors: [String]
    public var report: String

    enum CodingKeys: String, CodingKey {
        case files, errors, report
        case dryRun = "dry_run"
    }

    public init(dryRun: Bool, files: [File], errors: [String] = [], report: String = "") {
        self.dryRun = dryRun
        self.files = files
        self.errors = errors
        self.report = report
    }

    public static func parse(_ data: Data) throws -> UndoReport {
        try JSONDecoder().decode(UndoReport.self, from: data)
    }
}

/// `action` is "restore", "recreate" or "remove". `secrets` are the
/// vault paths recorded from this file: their values are on disk
/// again, and they stay in the vault.
public struct UndoReportFile: Codable, Sendable, Equatable {
    public var path: String
    public var action: String
    public var backedUpUnix: Int64
    public var mount: Bool
    public var secrets: [String]
    public var restored: Bool
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case path, action, mount, secrets, restored, error
        case backedUpUnix = "backed_up_unix"
    }

    public init(
        path: String, action: String = "restore", backedUpUnix: Int64 = 0, mount: Bool = false, secrets: [String] = [],
        restored: Bool = false, error: String? = nil
    ) {
        self.path = path
        self.action = action
        self.backedUpUnix = backedUpUnix
        self.mount = mount
        self.secrets = secrets
        self.restored = restored
        self.error = error
    }
}

/// `jit service log --format json`: the rows jit's text view draws,
/// oldest first.
public struct ServiceLog: Codable, Sendable, Equatable {
    public var path: String
    public var entries: [Entry]

    /// One row: a mount note (`subjects` its mounts), a lifecycle line
    /// (no subjects), or a line jit didn't recognise (`raw`, byte-exact).
    public struct Entry: Codable, Sendable, Equatable {
        public var date: String?
        public var time: String?
        public var subjects: [String]?
        public var message: String?
        public var count: Int?
        /// "risk", "warn" or "ok".
        public var level: String?
        public var raw: String?

        public init(
            date: String? = nil, time: String? = nil, subjects: [String]? = nil, message: String? = nil, count: Int? = nil,
            level: String? = nil, raw: String? = nil
        ) {
            self.date = date
            self.time = time
            self.subjects = subjects
            self.message = message
            self.count = count
            self.level = level
            self.raw = raw
        }
    }

    public init(path: String, entries: [Entry]) {
        self.path = path
        self.entries = entries
    }

    public static func parse(_ data: Data) throws -> ServiceLog {
        try JSONDecoder().decode(ServiceLog.self, from: data)
    }
}

/// `gh auth status --json hosts` (gh 2.x): each signed-in account. gh
/// leaves the token out of its JSON; nothing here would hold one. With
/// --json gh exits 0 even for a rejected key, so `state` is the verdict.
public struct GhAuthStatus: Codable, Sendable, Equatable {
    public var hosts: [String: [Account]]

    public struct Account: Codable, Sendable, Equatable {
        /// "success" when the key works.
        public var state: String
        public var active: Bool
        public var host: String
        public var login: String
        /// "keyring", or the variable the key came from ("GH_TOKEN" when
        /// jit's shim injected it).
        public var tokenSource: String?
        /// Comma separated, as gh prints them.
        public var scopes: String?

        public init(state: String, active: Bool, host: String, login: String, tokenSource: String? = nil, scopes: String? = nil) {
            self.state = state
            self.active = active
            self.host = host
            self.login = login
            self.tokenSource = tokenSource
            self.scopes = scopes
        }
    }

    public init(hosts: [String: [Account]]) {
        self.hosts = hosts
    }

    /// Every account, the active one first on each host, hosts in name
    /// order.
    public var accounts: [Account] {
        hosts.keys.sorted().flatMap { host in
            (hosts[host] ?? []).enumerated().sorted { lhs, rhs in
                lhs.element.active != rhs.element.active ? lhs.element.active : lhs.offset < rhs.offset
            }.map(\.element)
        }
    }

    public static let arguments = ["auth", "status", "--json", "hosts"]

    public static func parse(_ data: Data) throws -> GhAuthStatus {
        try JSONDecoder().decode(GhAuthStatus.self, from: data)
    }
}
