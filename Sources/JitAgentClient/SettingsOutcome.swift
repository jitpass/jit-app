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
        case .commandLineTool: value
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
        !ok && (verbatim.map(Self.serviceDown) ?? false)
    }

    /// jit's own phrasing when the socket is not there. Two spellings, and
    /// nothing is claimed from a line that carries neither.
    private static func serviceDown(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("not running") || lower.contains("no socket")
    }
}
