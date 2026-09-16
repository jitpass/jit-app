// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The slice of `jit status --format json` the panel renders. Everything
/// else the CLI prints is left undecoded so a new field never breaks the
/// app. `jit status` is read-only and never prompts, which is what makes it
/// safe to run from a menu bar app on every open.
public struct CLIVaultStatus: Codable, Sendable, Equatable {
    public var secretsStored: Int

    enum CodingKeys: String, CodingKey {
        case secretsStored = "secrets_stored"
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

public struct CLIStatus: Codable, Sendable, Equatable {
    public var vault: CLIVaultStatus?
    public var mounts: CLIMountsStatus?

    public init(vault: CLIVaultStatus?, mounts: CLIMountsStatus?) {
        self.vault = vault
        self.mounts = mounts
    }
}
