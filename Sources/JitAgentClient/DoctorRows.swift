// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// How a finding READS as one row — its text, and whether that text is a
/// path. Separate from DoctorAdvice's button building, which answers the
/// different question of what the row lets you DO about it.
public extension DoctorAdvice {
    /// What the row says. The group title and note already say what the
    /// kind means, so a row repeats none of it: a mount row is its path, an
    /// origin row is the secrets and the file they came from, a profile
    /// row is the profile and the variable. Anything else is doctor's own
    /// sentence.
    static func rowText(_ item: DoctorItem) -> String {
        switch item.kind {
        case "mount", "mount_stale", "install", "completion", "jit_path", "jit_path_upgrade", "1password_link":
            return item.path.map(homePath) ?? item.summary
        case "origin_gone":
            return originRow(item)
        case _ where ownershipKinds.contains(item.kind):
            return ownershipRow(item)
        default:
            if let profile = item.profile, let variable = item.variable, item.detail?.isEmpty ?? true {
                return "\(profile) · \(variable)"
            }
            return item.summary
        }
    }

    /// Rows that are a path read best in monospace, truncated at the start.
    static func rowIsPath(_ item: DoctorItem) -> Bool {
        switch item.kind {
        case "mount", "mount_stale", "install", "completion", "jit_path", "jit_path_upgrade", "1password_link":
            item.path != nil
        case "origin_gone", "missing", "corrupt", "bad_path":
            true
        case "pointer_missing":
            item.file != nil && item.path != nil
        default:
            false
        }
    }

    static func homePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
