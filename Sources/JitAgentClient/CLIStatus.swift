// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The slice of `jit status --format json` the panel renders. Everything
/// else the CLI prints is left undecoded so a new field never breaks the
/// app. `jit status` is read-only and never prompts, which is what makes it
/// safe to run from a menu bar app on every open.
public struct CLIVaultStatus: Codable, Sendable, Equatable {
    public var secretsStored: Int
    /// "yes", "no" or "unknown": whether the master key exists (jit 1.6.3
    /// adds it). nil from an older jit, which `VaultSetup` reads as unknown.
    public var initialized: String?
    /// Where the master key is kept: "keychain" or "secure-enclave"
    /// (jit's `keystore.Kind`). nil from a jit before the Secure Enclave
    /// move, which cannot move the key either.
    public var keyStore: String?
    /// Where an interrupted `jit vault rekey --wrapper` was moving the key,
    /// "secure-enclave" or "keychain" (jitpass/jit#169). Omitted when no
    /// move is unfinished; while it is set, every vault change is refused
    /// until `jit vault rekey --wrapper <that value>` finishes it.
    public var moveUnfinished: String?
    /// A lost Secure Enclave key was replaced by `jit vault init`, and
    /// secrets sealed to the old one are still on disk, unopenable, until
    /// `jit vault import <file>` brings them back (jitpass/jit#169).
    /// Omitted, so nil, when false.
    public var restorePending: Bool?
    /// jit could not check which secrets are still sealed to the lost key
    /// (its record unreadable, or the vault not readable): jit's own error.
    /// `restorePending` is true with it, since an unchecked restore is
    /// never reported as done; but jit names no restore for it, so the app
    /// offers none. Omitted, so nil, otherwise.
    public var restoreCheckError: String?
    /// The last `jit vault export`, the recovery file: whether one is
    /// recorded, when, and whether a secret has been written since. jit
    /// reports none of them for an empty vault.
    public var exportRecorded: Bool?
    public var exportUnixTime: Int64?
    public var exportStale: Bool?
    /// The `_backups/…` entries `jit migrate undo` keeps. jit reports the
    /// recovery file only when secrets and backups together are not zero
    /// (status.go's gatherVaultStatus), so this says whether it could.
    public var backupsStored: Int?

    enum CodingKeys: String, CodingKey {
        case secretsStored = "secrets_stored"
        case backupsStored = "backups_stored"
        case initialized
        case keyStore = "key_store"
        case moveUnfinished = "move_unfinished"
        case restorePending = "restore_pending"
        case restoreCheckError = "restore_check_error"
        case exportRecorded = "export_recorded"
        case exportUnixTime = "export_unix_time"
        case exportStale = "export_stale"
    }

    public init(
        secretsStored: Int, initialized: String? = nil, keyStore: String? = nil,
        exportRecorded: Bool? = nil, exportUnixTime: Int64? = nil, exportStale: Bool? = nil, backupsStored: Int? = nil,
        moveUnfinished: String? = nil, restorePending: Bool? = nil, restoreCheckError: String? = nil
    ) {
        self.secretsStored = secretsStored
        self.initialized = initialized
        self.keyStore = keyStore
        self.exportRecorded = exportRecorded
        self.exportUnixTime = exportUnixTime
        self.exportStale = exportStale
        self.backupsStored = backupsStored
        self.moveUnfinished = moveUnfinished
        self.restorePending = restorePending
        self.restoreCheckError = restoreCheckError
    }
}

public struct CLIMountsStatus: Codable, Sendable, Equatable {
    public var registered: Int
    public var servingReal: Bool

    enum CodingKeys: String, CodingKey {
        case registered
        case servingReal = "serving_real"
    }
}

/// The zsh history guard: true only when the hook file exists and the rc
/// file sources it with a live line, which is `guard.Installed`'s meaning.
public struct CLIGuardStatus: Codable, Sendable, Equatable {
    public var installed: Bool

    public init(installed: Bool) {
        self.installed = installed
    }
}

/// A captured temporary credential with a known end: what a wrapped SSO
/// tool's login minted. Metadata only, never a value.
public struct CLISession: Codable, Sendable, Equatable, Identifiable {
    public var profile: String
    public var origin: String?
    public var expiresUnix: Int64?
    public var live: Bool
    public var remainingSeconds: Int64?
    /// The command that mints a fresh one ("clisso get stage"), when jit
    /// can name it.
    public var mint: String?

    enum CodingKeys: String, CodingKey {
        case profile, origin, live, mint
        case expiresUnix = "expires_unix"
        case remainingSeconds = "remaining_seconds"
    }

    public init(profile: String, origin: String? = nil, expiresUnix: Int64? = nil, live: Bool, mint: String? = nil) {
        self.profile = profile
        self.origin = origin
        self.expiresUnix = expiresUnix
        self.live = live
        self.mint = mint
    }

    public var id: String {
        profile
    }

    /// nil when the stamp is unknown (a capture from before jit recorded expiry).
    public var expires: Date? {
        (expiresUnix ?? 0) > 0 ? Date(timeIntervalSince1970: TimeInterval(expiresUnix ?? 0)) : nil
    }

    /// The tool that minted it, read off the mint command's first word.
    public var mintTool: String? {
        mint?.split(separator: " ").first.map(String.init)
    }
}

/// One protected file the service serves: the path where the file was,
/// now a pipe that answers the real values only through jit.
public struct CLIMount: Codable, Sendable, Equatable, Identifiable {
    public var path: String
    /// The last time anything opened the file, as the service saw it —
    /// authoritative where the audit's record of the same read can land up
    /// to an hour later. nil from a jit that does not report it.
    public var lastServe: CLIMountServe?

    enum CodingKeys: String, CodingKey {
        case path
        case lastServe = "last_serve"
    }

    public init(path: String, lastServe: CLIMountServe? = nil) {
        self.path = path
        self.lastServe = lastServe
    }

    public var id: String {
        path
    }
}

public struct CLIMountServe: Codable, Sendable, Equatable {
    public var unixTime: Int64
    public var decoy: Bool?
    public var undelivered: Bool?

    enum CodingKeys: String, CodingKey {
        case unixTime = "unix_time"
        case decoy, undelivered
    }

    public init(unixTime: Int64, decoy: Bool? = nil, undelivered: Bool? = nil) {
        self.unixTime = unixTime
        self.decoy = decoy
        self.undelivered = undelivered
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(unixTime))
    }
}

/// The service's own slice of `jit status`: only its mount list is read.
public struct CLIAgentStatus: Codable, Sendable, Equatable {
    public var mounts: [CLIMount]?

    public init(mounts: [CLIMount]?) {
        self.mounts = mounts
    }
}

public struct CLIStatus: Codable, Sendable, Equatable {
    public var vault: CLIVaultStatus?
    public var mounts: CLIMountsStatus?
    public var guardStatus: CLIGuardStatus?
    public var sessions: [CLISession]?
    public var agent: CLIAgentStatus?

    enum CodingKeys: String, CodingKey {
        case vault, mounts, sessions, agent
        case guardStatus = "guard"
    }

    public init(
        vault: CLIVaultStatus?,
        mounts: CLIMountsStatus?,
        guardStatus: CLIGuardStatus? = nil,
        sessions: [CLISession]? = nil,
        agent: CLIAgentStatus? = nil
    ) {
        self.vault = vault
        self.mounts = mounts
        self.guardStatus = guardStatus
        self.sessions = sessions
        self.agent = agent
    }

    /// The protected files, in the registry's order; empty from a jit
    /// that does not list them.
    public var protectedFiles: [CLIMount] {
        agent?.mounts ?? []
    }

    /// The sessions a tool minted, by the mint command's first word.
    public func sessions(mintedBy tool: String) -> [CLISession] {
        (sessions ?? []).filter { $0.mintTool == tool }
    }
}
