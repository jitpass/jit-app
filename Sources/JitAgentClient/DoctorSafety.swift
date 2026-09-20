// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// What keeps a doctor button from doing more than the user was told: the
/// commands never offered, and the confirmation that says truthfully who
/// asks after the app's own dialog.
extension DoctorAdvice {
    /// `brew uninstall jitpass`: the jitpass cask is this app, so doctor's
    /// advice to drop the Homebrew jit would remove JitPass with it.
    static func uninstallsApp(_ command: String) -> Bool {
        let words = command.split(separator: " ").map(String.init)
        guard words.first == "brew", words.count > 1, ["uninstall", "remove", "rm", "zap"].contains(words[1]) else {
            return false
        }
        return words.dropFirst(2).contains { $0 == "jitpass" || $0.hasSuffix("/jitpass") }
    }

    /// jit commands that stop at their own y/N unless given --yes (or, for
    /// rm, --force): the only ones the app may say "jit asks again" about.
    static let askingCommands = [
        "jit vault rm ", "jit vault orphans ", "jit vault duplicates ", "jit vault import ", "jit unmount ",
        "jit migrate remove ", "jit vault rekey"
    ]

    /// What the app's own confirmation says for a destructive action: the
    /// command, what it does, and who asks after this, truthfully. A command
    /// the app runs carries --yes, so nothing asks again; in the terminal
    /// only a jit command with its own y/N does, sudo asks for a password
    /// and not whether you are sure.
    public static func confirmation(for action: DoctorAction) -> String {
        confirm(action).text
    }

    /// The sentence under the question: what this action does, and what it
    /// does not. `confirm` words the families that have checks of their
    /// own; everything else lands here.
    static func body(for action: DoctorAction) -> String {
        let command = action.command
        if action.argv != nil {
            let subject = Self.subject(of: action)
            if command.hasPrefix("jit vault set ") {
                return "The value you type is stored at \(subject). The value there now moves into the secret's history."
            }
            if action.argv?.contains(where: { $0.starts(with: ["vault", "import"]) }) == true {
                return "Every secret in \(subject) is stored. A secret already at the same path is overwritten, "
                    + "its current value archived first."
            }
            // Not a delete at all: no secret, no file, one line out of one
            // profile, so the generic "deletes for good" below would be
            // wrong twice over. It leads with the risk, because "Doctor
            // stops reporting it" read as a benefit when it is the whole
            // danger.
            if let drop = action.argv?.first(where: { $0.starts(with: ["profile", "drop"]) }) {
                let profile = drop.count > 2 ? drop[2] : ""
                let variables = drop.dropFirst(3).filter { !$0.hasPrefix("-") }
                let named = BoardText.list(Array(variables))
                let them = variables.count == 1 ? "it" : "them"
                return "Profile \(profile) stops passing \(named) to the tools it "
                    + "starts. If one of them does need \(them), it will fail with nothing to say why, and Doctor "
                    + "won't flag it again. No stored secret is deleted, and jit refuses to run this if the vault "
                    + "holds a value for \(them)."
            }
            // The only in-app case with nothing else to name it by: an
            // unknown destructive command keeps its line rather than
            // becoming "It deletes for good" with no object at all.
            return subject.isEmpty
                ? "This runs:\n\n\(command)\n\nIt deletes for good."
                : "It deletes \(subject) for good."
        }
        let opens = "This opens the terminal and runs:\n\n\(command)\n\n"
        if command.hasPrefix("sudo rm ") {
            let removed = homePath(String(command.dropFirst("sudo rm ".count)))
            return opens + "It deletes \(removed) for good. sudo may ask for your password; nothing asks whether you are sure."
        }
        let words = command.split(separator: " ")
        let asks = askingCommands.contains { command.hasPrefix($0) || command == $0.trimmingCharacters(in: .whitespaces) }
            && !words.contains("--yes") && !words.contains("-y") && !words.contains("--force")
        let effect = terminalEffect(command)
        return opens + (asks ? "\(effect). jit asks once more before it does." : "\(effect), and nothing asks again.")
    }

    /// What an in-app command acts on: every argument after the verb that
    /// is not a flag, shortened to ~. These dialogs no longer quote the
    /// command, and for `vault set` or `migrate forget` that line was the
    /// only place the path appeared, so the sentence has to name it.
    ///
    /// All of them, not the last one: `jit vault rm a/B c/D` deletes both,
    /// and a sentence naming only `c/D` would understate a delete, which is
    /// worse than the command line it replaced.
    private static func subject(of action: DoctorAction) -> String {
        BoardText.list(targets(of: action))
    }

    /// What a destructive terminal command does, in a clause: not every
    /// one the engine marks destructive deletes (an unmount or an undo puts
    /// plaintext back on disk).
    private static func terminalEffect(_ command: String) -> String {
        if command.hasPrefix("jit unmount") {
            return "It writes the secret values back to the file in plaintext"
        }
        if command.hasPrefix("jit migrate undo") {
            return "It puts the original file back, plaintext and all"
        }
        if command.hasPrefix("jit vault import") {
            return "Every secret in the file is stored, overwriting any at the same path"
        }
        return "It deletes for good"
    }
}
