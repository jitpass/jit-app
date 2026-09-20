// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The app's one question before a destructive doctor action, in the parts
/// a sheet draws: what it asks, what changes, what jit refuses to do, and
/// the command behind a disclosure for anyone who wants to check it.
///
/// The command is not in the question any more. It used to be the first
/// thing read — "This runs: jit migrate forget ~/…" — in the one dialog
/// that exists to explain, which asked the reader to parse a command line
/// to find out what happens to their file.
public struct DoctorConfirmation: Equatable, Sendable {
    /// "Delete this file?" — a question about the thing on screen.
    public var question: String
    /// One sentence: what changes, and what does not.
    public var lead: String
    /// What jit checks before it does anything. These are promises, not
    /// warnings: they are the reason this is safe to press.
    public var checks: [String]
    /// The files it acts on, home-shortened, when its targets are files.
    /// Before deleting a command line from a question, check it was not
    /// the only place a path appeared: here it was, so the question keeps
    /// them, drawn as files rather than as arguments.
    public var files: [String]
    /// What the disclosure reveals, exactly as the app will run it.
    public var command: String
    /// The destructive button's label.
    public var button: String
    /// Touch ID follows the button.
    public var presence: Bool

    public init(
        question: String, lead: String, checks: [String] = [], files: [String] = [], command: String, button: String,
        presence: Bool = false
    ) {
        self.question = question
        self.lead = lead
        self.checks = checks
        self.files = files
        self.command = command
        self.button = button
        self.presence = presence
    }

    /// The question and everything under it as one block of text, for a
    /// caller with nowhere to draw the parts.
    public var text: String {
        ([lead] + (files.isEmpty ? [] : [files.joined(separator: "\n")]) + checks).joined(separator: "\n\n")
            + (presence ? "\n\nTouch ID follows." : "")
    }
}

public extension DoctorAdvice {
    /// The sheet's question for a destructive action.
    static func confirm(_ action: DoctorAction) -> DoctorConfirmation {
        if let own = action.confirmation {
            return own
        }
        let targets = targets(of: action)
        let files = targets.count
        var checks: [String] = []
        let question: String
        let lead: String
        if action.argv?.contains(where: { $0.starts(with: ["migrate", "forget"]) }) == true {
            question = files > 1 ? "Delete these \(files) files?" : "Delete this file?"
            lead = (files > 1 ? "All \(files) files go." : "The file goes.")
                + " Nothing else does: no secret, no profile, no mount."
            checks = [
                "If a mount is still serving \(files > 1 ? "one of them" : "it"), jit stops and deletes nothing.",
                "If the secrets \(files > 1 ? "they list are" : "it lists are") back in the vault, jit stops and deletes nothing."
            ]
        } else {
            question = action.title.hasSuffix("?") ? action.title : action.title + "?"
            lead = body(for: action)
        }
        return DoctorConfirmation(
            question: question, lead: lead, checks: checks, files: targets.filter { $0.hasPrefix("~/") || $0.hasPrefix("/") },
            command: commandLine(action), button: action.title, presence: action.presence
        )
    }

    /// What an in-app action acts on: every argument after the verb that is
    /// not a flag, shortened to ~.
    static func targets(of action: DoctorAction) -> [String] {
        (action.argv?.first ?? []).dropFirst(2).filter { !$0.hasPrefix("-") }.map(homePath)
    }

    /// The command the disclosure shows: what the app will actually run,
    /// `--yes` and all, not the tidied version in the action's help.
    static func commandLine(_ action: DoctorAction) -> String {
        guard let argv = action.argv, !argv.isEmpty else {
            return action.command
        }
        return argv.map { arguments in "jit " + arguments.map(homePath).joined(separator: " ") }.joined(separator: "\n")
    }
}
