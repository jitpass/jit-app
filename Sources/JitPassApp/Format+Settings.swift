// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation
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
        // The names, as the sheet listed them: "Moved JAMF_URL, WIZ_CLIENT_ID
        // and 2 more out of the vault".
        let names = r.moved.map { $0.split(separator: "/").last.map(String.init) ?? $0 }
        let shown = names.count > 4 ? names.prefix(3).joined(separator: ", ") + " and \(names.count - 3) more" : names
            .joined(separator: ", ")
        var line = "Moved " + shown + " out of the vault"
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

    static let vaultSecretsNote = "Reading one takes Touch ID or a grant."
    static let vaultSettingsNote = "Beside the vault, readable by any program. Move one in if it turns out to be a secret."
    static let vaultOnlySettingsNote = "Nothing from this file went into the vault. Scan judged every value a setting."

    /// A secret row's fact: what it is when that is more than a value,
    /// when it expires, when it changed, who uses it. Never the vault
    /// class ("dotenv"): that is where it came from, in jit's words.
    static func vaultSecretFact(_ secret: VaultSecret, now: Date = Date()) -> String {
        var parts: [String] = []
        if secret.isLinked {
            parts.append("1Password link")
        }
        if let expires = secret.expires {
            parts.append(expiry(expires, now: now))
        }
        if let updated = secret.updated {
            parts.append("updated " + ago(updated, now: now))
        }
        if !secret.usedBy.isEmpty {
            parts.append("used by " + secret.usedBy.joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
    }

    /// The Vault window's footer: "14 secrets · 22 settings · 38 backups".
    static func vaultFooter(_ listing: VaultListing?, settings: Int) -> String {
        guard let listing else {
            return "Reading the vault…"
        }
        var parts = [count(listing.secrets.count, "secret")]
        if listing.linkedCount > 0 {
            parts.append("\(listing.linkedCount) linked")
        }
        if settings > 0 {
            parts.append(count(settings, "setting"))
        }
        if !listing.backups.isEmpty {
            parts.append(count(listing.backups.count, "backup"))
        }
        return parts.joined(separator: " · ")
    }
}

/// The Vault window's row states: the Touch ID being waited on, and why a
/// settings-only profile cannot be deleted from here.
extension Format {
    /// "Waiting for Touch ID to reveal BILLING_CLIENT_SECRET…": the verb and
    /// the variable, never the vault path.
    static func vaultWaiting(_ verb: String?, path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let verb else {
            return "Waiting for Touch ID…"
        }
        return "Waiting for Touch ID to \(verb) \(name)…"
    }

    /// A cancelled Touch ID, under its row: what did not happen, in grey.
    static func vaultCancelled(_ verb: String) -> String {
        switch verb {
        case "reveal": "Not revealed"
        case "copy": "Not copied"
        default: "Nothing changed"
        }
    }

    static let vaultSettingsOnlyDeleteHelp = "This profile holds only plain settings. They are removed with their project, "
        + "or one at a time with Move to Vault; jit has no command yet to delete them on their own."

    static func vaultSettingsOnlyCountHelp(_ n: Int) -> String {
        count(n, "setting") + ", no secrets"
    }
}

/// The Vault sidebar's dot, in words (its tooltip).
extension Format {
    /// Green: from a file still on disk. Amber: that file is gone, the one
    /// state to act on. Grey: no file on record, so nothing to check.
    /// "used by the mcp-tickets profile in ~/work/ops", or several by name;
    /// nil when no profile names them.
    static func vaultUsedBy(_ users: [VaultSecretUser]) -> String? {
        let named = users.compactMap(\.profile)
        guard let first = users.first, let name = first.profile else {
            return nil
        }
        if named.count == 1 {
            return "used by the \(name) profile" + (first.project.map { " in " + home($0) } ?? "")
        }
        return "used by the " + named.joined(separator: ", ") + " profiles"
    }

    static func vaultOriginHelp(_ group: VaultGroup, exists: Bool?, users: [VaultSecretUser] = []) -> String {
        if let origin = group.origin {
            return exists == true
                ? "From \(origin), still on this Mac."
                : "From \(origin), which is gone. Maintenance… finds profiles left from deleted files."
        }
        if group.secrets.isEmpty {
            return "Plain settings only: no file on record to check."
        }
        if let used = vaultUsedBy(users) {
            return "No file on record to check; " + used + "."
        }
        if group.secrets.allSatisfy({ $0.origin == nil }) {
            return "Set by hand: no file on record to check."
        }
        return "From several files: no one file to check."
    }
}

extension Format {
    /// Move Them Out…, before the check: what will be read, and that
    /// nothing moves until the next step.
    static func checkSettingsTitle(_ candidates: Int, known: Bool) -> String {
        guard known else {
            return "Check these profiles for settings?"
        }
        return candidates == 1 ? "1 entry may be a setting" : "\(candidates) entries may be settings"
    }

    /// Before the check. `known`: the engine said which names are
    /// credentials, so only the others are in question.
    static func checkSettingsNote(_: Int, known: Bool) -> String {
        guard known else {
            return "jit reads these entries and says which are settings: URLs, IDs, lists. "
                + "Secrets, and names that look like one, stay in the vault. Nothing moves until you see the list."
        }
        return "Their names look like settings: URLs, IDs, lists. jit reads the values to be sure, and one "
            + "that turns out to be a secret stays. The ones named like secrets stay in the vault either way. "
            + "Nothing moves until you see the result."
    }

    static func settingsLookHeading(_ n: Int) -> String {
        "Named like settings · \(n)"
    }

    static func settingsCheckTitle(moves: Int) -> String {
        moves == 0 ? "Every one is a secret: nothing to move" : "\(moves) of them are settings"
    }

    static let settingsCheckNote = "This is what jit read. Settings leave the vault and become plain; files keep working. "
        + "Move to Vault puts any of them back."

    static func settingsMovesHeading(_ n: Int) -> String {
        "Moves out of the vault · \(n)"
    }

    static func settingsStaysHeading(_ n: Int) -> String {
        "Stays in the vault · \(n)"
    }

    static let settingsCheckFirstFoot = "Touch ID follows. Nothing moves yet."
    static let settingsCheckThenFoot = "Touch ID follows once more."
}
