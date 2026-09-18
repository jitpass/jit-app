// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// Whether this Mac has a vault, read off `jit status`. It is derived from
/// what is true and never from a saved flag, so someone who set jit up in a
/// terminal is never offered setup, and a setup that stopped half way is
/// seen for what it is on the next launch (docs/design/onboarding.md §3).
public enum VaultSetup: Equatable, Sendable {
    /// A master key exists. Today's app.
    case ready
    /// No key and nothing stored: a new user.
    case needsSetup
    /// No key, but secrets on disk: a home restored without its keychain,
    /// or a new Mac. Creating a fresh key over it is the wrong answer; a
    /// recovery file is the right one.
    case needsRestore
    /// The keychain would not say, the status read failed, or the jit
    /// answering predates the field (1.6.3). Never treated as a new user.
    case unknown

    public init(status: CLIStatus?) {
        guard let vault = status?.vault else {
            self = .unknown
            return
        }
        switch vault.initialized {
        case "yes": self = .ready
        case "no": self = vault.secretsStored > 0 ? .needsRestore : .needsSetup
        default: self = .unknown
        }
    }
}
