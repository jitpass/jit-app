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

    enum CodingKeys: String, CodingKey {
        case secretsStored = "secrets_stored"
        case initialized
    }

    public init(secretsStored: Int, initialized: String? = nil) {
        self.secretsStored = secretsStored
        self.initialized = initialized
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

public struct CLIStatus: Codable, Sendable, Equatable {
    public var vault: CLIVaultStatus?
    public var mounts: CLIMountsStatus?
    public var guardStatus: CLIGuardStatus?
    public var sessions: [CLISession]?

    enum CodingKeys: String, CodingKey {
        case vault, mounts, sessions
        case guardStatus = "guard"
    }

    public init(
        vault: CLIVaultStatus?,
        mounts: CLIMountsStatus?,
        guardStatus: CLIGuardStatus? = nil,
        sessions: [CLISession]? = nil
    ) {
        self.vault = vault
        self.mounts = mounts
        self.guardStatus = guardStatus
        self.sessions = sessions
    }

    /// The sessions a tool minted, by the mint command's first word.
    public func sessions(mintedBy tool: String) -> [CLISession] {
        (sessions ?? []).filter { $0.mintTool == tool }
    }
}
