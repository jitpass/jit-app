// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The CLI's coverage ledger, in distinct secrets, from the summary record.
/// Same arithmetic as `audit.Coverage` in the engine: protected over total
/// in whole percent, 100 when jit knows of nothing, and the two gains sum
/// with the base to exactly 100.
public extension ScanSummary {
    var percent: Int {
        secretsTotal == 0 ? 100 : secretsProtected * 100 / secretsTotal
    }

    /// The score once every remedy jit can run has run.
    var percentAfterMigrate: Int {
        secretsTotal == 0 ? 100 : (secretsProtected + secretsMigratable) * 100 / secretsTotal
    }

    /// Secrets left once jit has done its part: the "only you" bucket.
    var secretsManual: Int {
        max(0, secretsTotal - secretsProtected - secretsMigratable)
    }

    /// The "to 100%" line the CLI prints under its bar, or nil at 100.
    var toFullLine: String? {
        guard percent < 100 else {
            return nil
        }
        var parts: [String] = []
        if secretsMigratable > 0 {
            parts.append("one command +\(percentAfterMigrate - percent)%")
        }
        if secretsManual > 0 {
            let n = secretsManual
            parts.append("\(n) secret\(n == 1 ? "" : "s") only you can fix +\(100 - percentAfterMigrate)%")
        }
        return parts.isEmpty ? nil : "to 100%: " + parts.joined(separator: " · ")
    }
}
