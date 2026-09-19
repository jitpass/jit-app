// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import Foundation

/// The engine's `fixes` (doctor schema 2) applied to the Doctor window's
/// buttons. The app used to recover commands from the action's backticks
/// and guess "destructive" from a prefix, which is how origin_gone's
/// `jit vault rm` became a one-click delete; the engine now says which
/// commands delete something and which ask for Touch ID, and the app takes
/// its word, only ever adding caution to what a kind's builder decided.
extension DoctorAdvice {
    /// A command the app has no verb for, from the engine's classification:
    /// Run, or Choose… when it names a placeholder to fill.
    static func generic(_ fix: DoctorFix) -> DoctorAction {
        var needs = DoctorAction.Needs.nothing
        if let placeholder = fix.needs, !placeholder.contains("://") {
            needs = fix.argv.starts(with: ["vault", "export"]) && !fix.external
                ? .newFile(placeholder: placeholder) : .existingPath(placeholder: placeholder)
        }
        return DoctorAction(
            needs == .nothing ? "Run" : "Choose…", fix.command, destructive: fix.destructive, needs: needs, presence: fix.presence
        )
    }

    /// `action` with every fix it runs taken into account: destructive when
    /// any of them is (never the other way: a kind's builder may be more
    /// careful than the engine), Touch ID when any asks. Unchanged when the
    /// report has no fixes.
    static func reconciled(_ action: DoctorAction, with fixes: [DoctorFix]?) -> DoctorAction {
        guard let fixes, !fixes.isEmpty else {
            return action
        }
        let matched = fixes.filter { fix in
            fix.command == action.command || steps(of: action).contains { runs($0, fix) }
        }
        var action = action
        action.destructive = action.destructive || matched.contains(where: \.destructive)
        action.presence = action.presence || matched.contains(where: \.presence)
        return action
    }

    /// The invocations an action runs, without a leading "jit": its argv,
    /// or the terminal command's lines and `&&` steps split into words.
    static func steps(of action: DoctorAction) -> [[String]] {
        if let argv = action.argv {
            return argv
        }
        return action.command.components(separatedBy: "\n")
            .flatMap { $0.components(separatedBy: " && ") }
            .map { line in
                let words = line.split(separator: " ").map(String.init)
                return words.first == "jit" ? Array(words.dropFirst()) : words
            }
    }

    /// Whether `step` runs `fix`: the fix's words (as argv, with ~
    /// expanded, or as the command reads, with ~) lead the step's.
    static func runs(_ step: [String], _ fix: DoctorFix) -> Bool {
        let written = fix.command.split(separator: " ").map(String.init)
        let words = !fix.external && written.first == "jit" ? Array(written.dropFirst()) : written
        return [fix.argv, words].contains { !$0.isEmpty && step.starts(with: $0) }
    }

    /// An origin row: the secrets and the file they came from, and, from a
    /// schema 2 report, the profiles still using them, the fact that says
    /// "keep these".
    static func originRow(_ item: DoctorItem) -> String {
        let detail = item.detail ?? ""
        let verb = detail.range(of: " was migrated from ") ?? detail.range(of: " were migrated from ")
        var text = item.summary
        if let verb, let end = detail.range(of: ", which no longer exists") {
            text = "\(detail[..<verb.lowerBound]) · from \(detail[verb.upperBound ..< end.lowerBound])"
        } else if let groups = item.groups, !groups.isEmpty, let path = item.path {
            text = groups.joined(separator: ", ") + " · from " + path
        }
        if let profiles = item.profiles, !profiles.isEmpty {
            text += " · used by " + profiles.joined(separator: ", ")
        }
        return text
    }
}
