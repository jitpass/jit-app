// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What a change to one setting did, said in the window rather than in a
/// terminal pane: a success is one line in the banner, a failure is a row
/// under the control that asked, carrying a sentence that translates jit's
/// refusal and jit's own words verbatim under it (docs/design: windows.md,
/// "Saying what happened, without a terminal").
public struct SettingsOutcome: Equatable, Sendable {
    /// The control the outcome belongs to, so a failure lands on the row
    /// the reader just used and not under the whole window.
    public enum Row: String, Sendable, Equatable {
        case lockTimer
        case consent
        case history
        case vaultKey
        case launchAtLogin
        case commandLineTool
    }

    public var row: Row
    public var ok: Bool
    /// The sentence itself: past tense on success, what did not happen on
    /// a failure.
    public var title: String
    /// What to do about it. Empty on success, where the title is the whole
    /// of it.
    public var detail: String
    /// jit's own line, kept only where it is the diagnosis.
    public var verbatim: String?

    public init(row: Row, ok: Bool, title: String, detail: String = "", verbatim: String? = nil) {
        self.row = row
        self.ok = ok
        self.title = title
        self.detail = detail
        self.verbatim = verbatim
    }
}

public extension SettingsOutcome {
    /// The banner's line: what changed, and the restart when there was
    /// one. The value is named, because "Saved" is not an answer.
    static func applied(_ row: Row, value: String) -> SettingsOutcome {
        SettingsOutcome(row: row, ok: true, title: sentence(row, value: value))
    }

    private static func sentence(_ row: Row, value: String) -> String {
        switch row {
        case .lockTimer: "Lock timer set to \(value). jit restarted."
        case .consent: "Consent \(value). jit restarted."
        case .history: "zsh history guard \(value)."
        case .launchAtLogin: "Launch at login \(value)."
        case .commandLineTool, .vaultKey: value
        }
    }

    /// A refusal. The cause is stated only where jit's own line says it:
    /// the service being down is the one jit names, and anything else
    /// keeps its words without a cause invented over them.
    static func failed(_ row: Row, line: String) -> SettingsOutcome {
        SettingsOutcome(
            row: row,
            ok: false,
            title: didNot(row),
            detail: serviceDown(line) ? downDetail(row) : "jit did not make the change. Its own words are below.",
            verbatim: line.isEmpty ? nil : line
        )
    }

    private static func didNot(_ row: Row) -> String {
        switch row {
        case .lockTimer: "The lock timer did not change"
        case .consent: "The consent setting did not change"
        case .history: "The history guard did not change"
        case .vaultKey: "The vault key did not move"
        case .launchAtLogin: "Launch at login did not change"
        case .commandLineTool: "jit was not linked"
        }
    }

    private static func downDetail(_ row: Row) -> String {
        let kept = switch row {
        case .lockTimer: "the timer"
        case .consent: "the setting"
        default: "what"
        }
        return "jit is not running, so it kept \(kept) it had. Start the service and set it again."
    }

    /// Whether the outcome's row offers to start the service: only where
    /// jit said that is what stopped it.
    var offersStart: Bool {
        !ok && row != .vaultKey && (verbatim.map(Self.serviceDown) ?? false)
    }

    /// The vault key's failure offers the move again: every refusal before
    /// the last step leaves the key where it was, and one after it is
    /// finished by running the same move again.
    var offersRetry: Bool {
        !ok && row == .vaultKey
    }

    /// jit's own phrasing when the socket is not there. Two spellings, and
    /// nothing is claimed from a line that carries neither.
    private static func serviceDown(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("not running") || lower.contains("no socket")
    }
}

/// The Vault key row's outcomes: the banner after a move, and the failure
/// that takes the row's place (the mockup's frames E and F).
public extension SettingsOutcome {
    static func vaultKeyMoved(to place: VaultKeyPlace) -> SettingsOutcome {
        let title = switch place {
        case .secureEnclave: "Moved the vault key into the Secure Enclave · every secret opens as before"
        case .keychain: "Moved the vault key back to your keychain"
        }
        return SettingsOutcome(row: .vaultKey, ok: true, title: title)
    }

    /// A move jit refused. The title says where the key is now, read from
    /// jit after the failure; the sentence says what stopped it, in the
    /// reader's words where jit's line names the cause, and "nothing
    /// changed" only where the key is still where it was. `newSecrets` is
    /// how far behind the recovery file is, when the counts are known.
    static func vaultKeyFailed(
        to target: VaultKeyPlace, now place: VaultKeyPlace?, line: String, newSecrets: Int? = nil
    ) -> SettingsOutcome {
        let verbatim = line.isEmpty ? nil : line
        guard let place, place != target else {
            return SettingsOutcome(
                row: .vaultKey, ok: false, title: "The move did not finish",
                detail: "Try again to finish it. jit's own words are below.", verbatim: verbatim
            )
        }
        let title = switch place {
        case .keychain: "Still in your login keychain"
        case .secureEnclave: "Still in the Secure Enclave"
        }
        return SettingsOutcome(row: .vaultKey, ok: false, title: title, detail: stopped(line, newSecrets: newSecrets), verbatim: verbatim)
    }

    /// jit's refusals, from internal/cli/vaultmove.go and the two key
    /// stores' own errors. A line that names none of them keeps its words
    /// with no cause invented over them.
    private static func stopped(_ line: String, newSecrets: Int?) -> String {
        let lower = line.lowercased()
        if lower.contains("local authentication failed"), lower.contains("cancel") {
            return "Touch ID was cancelled, so nothing changed."
        }
        if lower.contains("can't use the secure enclave") {
            return "This copy of jit can't reach the Secure Enclave, so nothing changed."
        }
        if lower.contains("older than your newest secret") {
            if let newSecrets {
                return "The recovery file is from before \(newSecrets) new secret\(newSecrets == 1 ? "" : "s"), so nothing changed."
            }
            return "The recovery file is older than your newest secret, so nothing changed."
        }
        if lower.contains("save a recovery file first") {
            return "There is no recovery file yet, so nothing changed."
        }
        return "jit did not move it. Its own words are below."
    }
}
