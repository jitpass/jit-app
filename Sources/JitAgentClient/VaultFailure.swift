// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// A vault command's failure, as the Vault window says it.
public enum VaultFailure {
    /// jit refused because only the signed jit inside JitPass.app can reach
    /// the Secure Enclave: running the same command again cannot change
    /// that. The same test as Doctor's (DoctorFailureLine on the
    /// Findings/Doctor branch); the two are twins until they merge.
    public static func needsInstalledApp(_ text: String) -> Bool {
        let flat = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return flat.contains("only the jit inside jitpass.app can reach it")
            || flat.contains("can't use the secure enclave")
    }

    public static let installedAppLine =
        "Only the jit inside the installed JitPass can reach this vault's key. Do it from there."

    /// What the row or sheet says: jit's words, or the plain sentence for a
    /// refusal only the installed app can get past.
    public static func plain(_ text: String) -> String {
        needsInstalledApp(text) ? installedAppLine : text
    }
}

/// Why the settings check left an entry in the vault.
public enum SettingStayReason: Equatable, Sendable {
    /// jit read it and counts it a secret.
    case secret
    /// The name looks like a secret and the value could not say otherwise.
    case looksSecret
    /// A setting, kept because a pointer file names it.
    case pointerFile
    /// A setting, kept because no profile names it.
    case noProfile
    /// It could not be read.
    case unreadable
    /// jit's own words, for a reason this app does not know.
    case other(String)
}

public extension MigrateSettingsResult {
    /// Why `path` stays, from jit's result: a check, a skip with jit's
    /// reason, or else a secret (read, and neither moved nor excused).
    func stayReason(_ path: String) -> SettingStayReason {
        if checks.contains(path) {
            return .looksSecret
        }
        guard let skip = skipped.first(where: { $0.path == path }) else {
            return .secret
        }
        let reason = skip.reason
        if reason.contains("pointer file names it") {
            return .pointerFile
        }
        if reason.contains("no profile names it") {
            return .noProfile
        }
        if reason.hasPrefix("could not be read") {
            return .unreadable
        }
        return .other(reason)
    }
}
