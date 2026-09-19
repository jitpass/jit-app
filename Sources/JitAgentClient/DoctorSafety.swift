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
        confirmationBody(for: action) + (action.presence ? " Touch ID follows." : "")
    }

    private static func confirmationBody(for action: DoctorAction) -> String {
        let command = action.command
        if action.argv != nil {
            if command.hasPrefix("jit vault set ") {
                return "This runs:\n\n\(command)\n\nThe value you type replaces the stored one; "
                    + "the old one stays in the secret's history. Nothing asks again."
            }
            if action.argv?.contains(where: { $0.starts(with: ["vault", "import"]) }) == true {
                return "This runs:\n\n\(command)\n\nEvery secret in the file is stored; a secret at the same path "
                    + "is overwritten, its current value archived first. Nothing asks again."
            }
            // Not a delete at all — no secret, no file, one line out of one
            // profile — so the generic "deletes for good" below would be
            // wrong twice over. It names the variables in prose rather than
            // only in the command line, which is the line people skim; and
            // it leads with the risk, because "Doctor stops reporting it"
            // read as a benefit when it is the whole danger.
            if let drop = action.argv?.first(where: { $0.starts(with: ["profile", "drop"]) }) {
                let profile = drop.count > 2 ? drop[2] : ""
                let variables = drop.dropFirst(3).filter { !$0.hasPrefix("-") }
                let named = BoardText.list(Array(variables))
                let them = variables.count == 1 ? "it" : "them"
                return "This runs:\n\n\(command)\n\nProfile \(profile) stops passing \(named) to the tools it "
                    + "starts. If one of them does need \(them), it will fail with nothing to say why, and Doctor "
                    + "won't flag it again. No stored secret is deleted, and jit refuses to run this if the vault "
                    + "holds a value for \(them). Nothing asks again."
            }
            if action.argv?.contains(where: { $0.starts(with: ["migrate", "forget"]) }) == true {
                return "This runs:\n\n\(command)\n\nIt deletes that file and nothing else: no secret, no profile, "
                    + "no mount. jit refuses if a mount is still serving that file, or if the secrets it lists are "
                    + "still in the vault. Nothing asks again."
            }
            return "This runs:\n\n\(command)\n\nIt deletes for good, and nothing asks again."
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
