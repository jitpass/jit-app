// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// How far a scan looks. Regular is `jit scan`: files and agent caches, by
/// shape, no vault, no prompt — what the schedule runs. Deep is `jit scan
/// --deep`: the same plus exact copies of every secret in the vault, which
/// needs the vault open (Touch ID unless the service holds a session), so
/// it is always by hand (design/scan-and-protect.md, D2).
public enum ScanMode: String, Sendable, CaseIterable {
    case regular
    case deep

    /// Deep is offered only once the vault holds a secret: an empty vault
    /// has nothing to search for, and a Touch ID for nothing is the one
    /// prompt this app must never raise (D8).
    public static func deepAvailable(secretsStored: Int?) -> Bool {
        (secretsStored ?? 0) > 0
    }

    public var name: String {
        switch self {
        case .regular: "Regular"
        case .deep: "Deep"
        }
    }

    /// The sheet row's one fact. For Deep it names how many secrets it
    /// will look for, or why it cannot be chosen yet.
    public static func fact(_ depth: ScanMode, secretsStored: Int?) -> String {
        switch depth {
        case .regular:
            return "Vendor tokens and keys, in files and agent caches, found by their format. No Touch ID."
        case .deep:
            guard deepAvailable(secretsStored: secretsStored) else {
                return "Regular, plus exact copies of the secrets you've vaulted. "
                    + "Available once your vault holds a secret — protect something first."
            }
            let n = secretsStored ?? 0
            let which = n == 1 ? "the 1 secret you've vaulted" : "the \(n) secrets you've vaulted"
            return "Regular, plus exact copies of \(which) — passwords and formatless keys shape can't catch."
        }
    }
}
