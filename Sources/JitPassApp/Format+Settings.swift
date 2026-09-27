// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import JitAgentClient

/// The Vault window's words for plain settings (design/secrets-only-vault.md).
extension Format {
    /// "billing-sync/EXPORT_SECRETS_FILE is a plain setting now", or with a
    /// count; for a counted secret, what that costs.
    static func moved(_ result: SettingMoveResult, out: Bool) -> String {
        let state = out ? "a plain setting now" : "in the vault now"
        guard result.moved.count == 1, let one = result.moved.first else {
            return "\(result.moved.count) values are " + (out ? "plain settings now" : "in the vault now")
        }
        var line = one.path + " is " + state
        if out, one.scan == "secret" {
            line += " · the scan counts it as a secret, so Findings will show it"
        }
        return line
    }

    /// "Moved 13 settings out of the vault · 2 names that look like secrets stayed".
    static func checkedSettings(_ r: MigrateSettingsResult) -> String {
        if r.moved.isEmpty {
            return "Checked \(r.read) \(r.read == 1 ? "entry" : "entries") · none were settings"
        }
        var line = "Moved \(r.moved.count) setting\(r.moved.count == 1 ? "" : "s") out of the vault"
        if !r.checks.isEmpty {
            line += " · \(r.checks.count) name\(r.checks.count == 1 ? "" : "s") that look like secrets stayed"
        }
        return line
    }

    /// The profile line: "2 secrets · 7 settings".
    static func profileCounts(secrets: Int, settings: Int) -> String {
        var parts = ["\(secrets) secret\(secrets == 1 ? "" : "s")"]
        if settings > 0 {
            parts.append("\(settings) setting\(settings == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    /// The Vault window's bar with nothing selected.
    static let vaultSelectHint = "Select a secret. Every read or change of a secret is its own Touch ID; "
        + "nothing here rides the service session. Settings need none."
}
